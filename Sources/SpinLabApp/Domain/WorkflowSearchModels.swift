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
    static let preferred: [String] = [
        "生长温度", "氧压", "生长脉冲频率", "样品高度", "镜前能量",
        "激光器电压", "激光器输出能量", "预打次数", "生长次数",
        "能量", "电压", "温度", "磁场", "电阻"
    ]
    static let oxygenFilterKeys = ["氧压"]
    static let temperatureFilterKeys = ["生长温度", "温度"]
    static let energyFilterKeys = ["能量", "激光器输出能量", "镜前能量"]
}

/// Unit suffix → canonical numeric field name mapping for search query parsing.
enum NumericUnitMap {
    static let entries: [(suffix: String, field: String)] = [
        ("mj", "能量"),
        ("mt", "氧压"),
        ("c", "生长温度"),
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

/// Typed input reference for a Workbench hit. Legacy hits carry no reference and are identified by
/// their sidecar path; a standard Dataset is identified by its asset ID, never by a path or file name.
enum WorkbenchInputRef: Codable, Hashable, Sendable {
    case datasetV2(datasetID: String, sourceID: String, sampleUID: String, originalFileName: String, channelIDs: [String])

    var stableID: String {
        switch self {
        case let .datasetV2(datasetID, _, _, _, _): return datasetID
        }
    }

    var datasetID: String {
        switch self {
        case let .datasetV2(datasetID, _, _, _, _): return datasetID
        }
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
    /// Set only for standard (V2) Datasets; nil for legacy sidecar hits. For a V2 hit the path fields are
    /// empty and every consumer must key on this reference instead.
    var inputRef: WorkbenchInputRef? = nil

    /// TEMPORARY IDENTITY DEBT: hit.id is the sidecar's file path, not a stable
    /// TestRecord identity. This is intentional for Phase 2 — Selection and Analysis
    /// Packs key off this value today, so changing it is deferred to the testRecordID
    /// migration in a later phase.
    var id: String { inputRef?.stableID ?? sidecarPath }

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
