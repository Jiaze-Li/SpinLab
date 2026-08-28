import Foundation

/// Payload-wide identity snapshot for a single rendered series.
///
/// `identityKey` is unique within one payload and stable across rerenders of the
/// same selected data. `sourceRef` / `sampleID` are retained for legacy fallback
/// matching when restoring older overrides or orders.
struct WorkbenchSeriesIdentity: Hashable, Sendable {
    let identityKey: String
    let sampleID: String?
    let sourceRef: String?
    let metadataSignature: String?
    let originalIndex: Int
}

/// Shared identity-key resolver for reorderable Workbench series.
///
/// The resolver is intentionally workflow-agnostic so Plot System code can persist
/// stable order tokens without depending on workflow store helpers.
enum WorkbenchSeriesOrderKeyResolver {
    static let seriesIdentityMetadataKey = "seriesIdentityKey"
    /// Carries the originating `WorkflowMeasurementSearchHit.id` (sidecarPath) through to a
    /// rendered series, unchanged, independent of `seriesIdentityKey` (which is namespaced
    /// per workflow/tab/role for ordering and rename, not for hit lookup). One hit may produce
    /// several series with the SAME sourceHitID (e.g. AHE's per-channel fan-out) — this is the
    /// explicit 1-hit-to-many representation, not a fallback/guess.
    static let sourceHitIDMetadataKey = "sourceHitID"

    static func resolve(for series: WorkbenchPlotSeries, originalIndex: Int) -> String {
        if let seriesIdentityKey = normalizedIdentityComponent(series.metadata[seriesIdentityMetadataKey]) {
            return seriesIdentityKey
        }
        if let sourceRef = series.sourceRef, !sourceRef.isEmpty {
            return sourceRef
        }
        if let sampleID = series.sampleID, !sampleID.isEmpty {
            return sampleID
        }
        return String(originalIndex)
    }

    static func resolveIdentities(for series: [WorkbenchPlotSeries]) -> [WorkbenchSeriesIdentity] {
        let candidates = series.enumerated().map { index, series in
            IdentityCandidate(
                seriesIdentityKey: normalizedIdentityComponent(series.metadata[seriesIdentityMetadataKey]),
                sourceRef: normalizedIdentityComponent(series.sourceRef),
                sampleID: normalizedIdentityComponent(series.sampleID),
                metadataSignature: metadataSignature(for: series.metadata),
                originalIndex: index
            )
        }
        let keys = uniqueIdentityKeys(for: candidates)
        return zip(candidates, keys).map { candidate, key in
            WorkbenchSeriesIdentity(
                identityKey: key,
                sampleID: candidate.sampleID,
                sourceRef: candidate.sourceRef,
                metadataSignature: candidate.metadataSignature,
                originalIndex: candidate.originalIndex
            )
        }
    }

    static func resolveIdentityKeys(for series: [WorkbenchPlotSeries]) -> [String] {
        resolveIdentities(for: series).map(\.identityKey)
    }

    static func resolveOrderKeys(_ currentSeriesOrder: [String]?, series: [WorkbenchPlotSeries]) -> [String] {
        let keyedSeries = resolveIdentities(for: series)
        guard let currentSeriesOrder, !currentSeriesOrder.isEmpty else {
            return keyedSeries.map(\.identityKey)
        }

        let byKey = Dictionary(uniqueKeysWithValues: keyedSeries.map { ($0.identityKey, $0.originalIndex) })
        let bySampleID = Dictionary(grouping: keyedSeries, by: { $0.sampleID ?? "" })
        let bySourceRef = Dictionary(grouping: keyedSeries, by: { $0.sourceRef ?? "" })
        var orderedKeys: [String] = []
        var consumed = Set<Int>()

        func append(index: Int) {
            guard consumed.insert(index).inserted else { return }
            orderedKeys.append(keyedSeries[index].identityKey)
        }

        for token in currentSeriesOrder {
            if let index = byKey[token] {
                append(index: index)
                continue
            }
            if let matches = bySourceRef[token], !matches.isEmpty {
                for match in matches.sorted(by: { $0.originalIndex < $1.originalIndex }) {
                    append(index: match.originalIndex)
                }
                continue
            }
            // Legacy migration only: old persisted orders may still use sampleID tokens.
            if let matches = bySampleID[token], !matches.isEmpty {
                for match in matches.sorted(by: { $0.originalIndex < $1.originalIndex }) {
                    append(index: match.originalIndex)
                }
            }
        }

        for item in keyedSeries where !consumed.contains(item.originalIndex) {
            append(index: item.originalIndex)
        }
        return orderedKeys
    }

    private struct IdentityCandidate {
        let seriesIdentityKey: String?
        let sourceRef: String?
        let sampleID: String?
        let metadataSignature: String?
        let originalIndex: Int

        var components: [String] {
            [seriesIdentityKey, sourceRef, sampleID, metadataSignature, String(originalIndex)].compactMap { $0 }
        }

        func key(depth: Int) -> String {
            components.prefix(depth).joined(separator: "|")
        }
    }

    private static func uniqueIdentityKeys(for candidates: [IdentityCandidate]) -> [String] {
        guard !candidates.isEmpty else { return [] }
        let maxDepth = 5
        for depth in 1...maxDepth {
            let keys = candidates.map { $0.key(depth: depth) }
            if Set(keys).count == keys.count {
                return keys
            }
        }
        return candidates.map { $0.key(depth: maxDepth) }
    }

    private static func normalizedIdentityComponent(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func metadataSignature(for metadata: [String: String]) -> String? {
        let filteredMetadata = metadata.filter { $0.key != seriesIdentityMetadataKey }
        guard !filteredMetadata.isEmpty else { return nil }
        return filteredMetadata
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
    }
}

enum WorkbenchSeriesIdentityMetadata {
    static func namespacedKey(
        workflowID: String,
        tabKey: String,
        seriesRole: String,
        stableSemanticID: String
    ) -> String {
        "\(workflowID):\(tabKey):\(seriesRole):\(stableSemanticID)"
    }

    static func seriesIdentityKey(
        workflowID: String,
        tabKey: String,
        seriesRole: String,
        stableSemanticID: String
    ) -> String {
        namespacedKey(
            workflowID: workflowID,
            tabKey: tabKey,
            seriesRole: seriesRole,
            stableSemanticID: stableSemanticID
        )
    }

    static func stableSemanticID(sourceRef: String?, sampleID: String?, fallback: String? = nil) -> String? {
        let source = sourceRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !source.isEmpty { return source }
        let sample = sampleID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !sample.isEmpty { return sample }
        let fallback = fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fallback.isEmpty ? nil : fallback
    }

    static func metadata(
        base: [String: String] = [:],
        seriesIdentityKey: String,
        sourceHitID: String? = nil
    ) -> [String: String] {
        var metadata = base
        metadata[WorkbenchSeriesOrderKeyResolver.seriesIdentityMetadataKey] = seriesIdentityKey
        if let sourceHitID, !sourceHitID.isEmpty {
            metadata[WorkbenchSeriesOrderKeyResolver.sourceHitIDMetadataKey] = sourceHitID
        }
        return metadata
    }
}

extension WorkbenchPlotSeries {
    func withSeriesIdentityKey(_ key: String) -> WorkbenchPlotSeries {
        var copy = self
        copy.metadata[WorkbenchSeriesOrderKeyResolver.seriesIdentityMetadataKey] = key
        return copy
    }
}

enum WorkbenchPlotSeriesIdentityTabKey {
    static let threeOmegaR1omegaVsH = "r1omega-vs-h"
    static let threeOmegaR3omegaVsH = "r3omega-vs-h"
    static let threeOmegaRAHE1omegaVsT = "rahe-1omega-vs-t"
    static let threeOmegaRAHE3omegaVsT = "rahe-3omega-vs-t"
    static let threeOmegaRAHE1omegaVsDevice = "rahe-1omega-vs-device"
    static let threeOmegaRAHE3omegaVsDevice = "rahe-3omega-vs-device"
    static let threeOmegaRAHE = "rahe"
    static let threeOmegaHcVsT = "hc-vs-t"
    static let threeOmegaRT = "rt-vs-t"
    static let threeOmegaScaling = "scaling"
    static let threeOmegaScalingVsAngle = "scaling-vs-angle"
    static let xyRxxVsPhi = "rxx-vs-phi"
    static let xyRxyVsPhi = "rxy-vs-phi"
    static let ivFirstHarmonicVsCurrent = "first-harmonic-vs-current"
    static let ivSecondHarmonicVsCurrent = "second-harmonic-vs-current"
    static let ahe = "ahe"
}
