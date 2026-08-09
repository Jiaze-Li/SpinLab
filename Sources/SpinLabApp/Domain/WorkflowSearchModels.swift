import Foundation

struct WorkflowSearchQuery: Codable, Hashable, Sendable {
    var rawText: String

    init(rawText: String) {
        self.rawText = rawText
    }
}

// MARK: - Numeric search support

/// Preferred display order for numeric fields. Aligned with Library UI.
enum NumericFieldOrder {
    static let preferred: [String] = ["厚度", "氧压", "温度", "能量", "电压", "磁场", "电阻"]
}

/// Unit suffix → canonical numeric field name mapping for search query parsing.
enum NumericUnitMap {
    static let entries: [(suffix: String, field: String)] = [
        ("mj", "能量"),
        ("mt", "氧压"),
        ("c", "温度"),
        ("ps", "厚度"),
        ("kv", "电压"),
    ]

    /// Attempts to parse a raw token like "60mj" into (value, fieldName).
    /// Returns nil if the token doesn't match any known numeric+unit pattern.
    static func parse(_ rawToken: String) -> (value: Double, field: String)? {
        let trimmed = rawToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()
        guard !trimmed.isEmpty else { return nil }
        for entry in entries {
            if trimmed.hasSuffix(entry.suffix) {
                let numPart = String(trimmed.dropLast(entry.suffix.count))
                if let value = Double(numPart), value != 0 {
                    return (value, entry.field)
                }
            }
        }
        return nil
    }

    /// Default relative tolerance (±6%).
    static let relativeTolerance: Double = 0.06
    /// Minimum absolute tolerance floor.
    static let absoluteToleranceFloor: Double = 1.0

    /// Computes tolerance for a given value: max(|value| × 6%, 1.0).
    static func tolerance(for value: Double) -> Double {
        max(abs(value) * relativeTolerance, absoluteToleranceFloor)
    }
}

struct WorkflowMeasurementSearchHit: Identifiable, Codable, Hashable, Sendable {
    var sidecarPath: String
    var measurementFilePath: String
    var sourceFilePath: String
    var workflowID: String
    var workflowDisplayName: String
    var workflowCanonicalID: String
    var batchID: String
    var sampleKey: String
    var sampleSubstrate: String
    var conditions: [String: String]
    var channels: [String]
    var appliedAt: Date
    /// Projected verbatim from sidecar.measurementTimestamp (Phase 1 TestRecord fact) —
    /// not reinterpreted, not backed by appliedAt. nil for sidecars that never resolved
    /// one (including all pre-Phase-1 sidecars). Not yet consumed for
    /// sorting/filtering/display — that is deferred to the Workbench-facing phase.
    var measurementTimestamp: SidecarMeasurementTimestamp? = nil

    /// TEMPORARY IDENTITY DEBT: hit.id is the sidecar's file path, not a stable
    /// TestRecord identity. This is intentional for Phase 2 — Selection and Analysis
    /// Packs key off this value today, so changing it is deferred to the testRecordID
    /// migration in a later phase.
    var id: String { sidecarPath }

    var sampleBatchAndSubstrate: String {
        if let descriptor = SampleSemanticDescriptor.fromSampleKey(sampleKey),
           let batch = descriptor.batch {
            let treatment = descriptor.processingTokens.sorted().joined(separator: "+")
            let material = descriptor.material ?? ""
            let orientation = descriptor.orientation ?? ""
            let substrate = "\(material)\(orientation)"
            return [batch, treatment, substrate]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }

        if sampleSubstrate.isEmpty {
            return batchID
        }
        return "\(batchID) \(sampleSubstrate)"
    }

    var conditionSummary: String {
        guard !conditions.isEmpty else {
            return "-"
        }
        return conditions
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }
}
