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
