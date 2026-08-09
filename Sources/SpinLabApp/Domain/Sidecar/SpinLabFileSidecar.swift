import Foundation

// MARK: - Primitive value types

struct SourcedValue: Codable, Hashable, Sendable {
    var value: String
    var source: String  // ruleRef string per §1.1
}

struct ManualValueOverride: Codable, Hashable, Sendable {
    var value: String
    var reason: String
    var at: Date
}

enum WorkflowSource: String, Codable, Hashable, Sendable {
    case auto
    case manual
}

// MARK: - Composite sidecar types

struct SidecarUserOverrides: Codable, Hashable, Sendable {
    var conditions: [String: ManualValueOverride]
    static let empty = SidecarUserOverrides(conditions: [:])
}

struct SidecarRuleFields: Codable, Hashable, Sendable {
    var sampleID: SourcedValue?                 // nil when rule didn't match
    var conditions: [String: SourcedValue]
    var substrateTags: [SourcedValue]
}

struct SidecarRuleSnapshot: Codable, Hashable, Sendable {
    var ruleSetVersion: Int
    var ruleSetFingerprint: String
    var appliedAt: Date
    var fields: SidecarRuleFields
}

// MARK: - SpinLabFileSidecar (v2)

struct SpinLabFileSidecar: Codable, Hashable, Sendable {
    var version: Int                            // = 2
    var workflow: String
    var autoDetectedWorkflow: String
    var workflowOverride: String?
    var workflowSource: WorkflowSource
    var workflowDisplayName: String
    var channels: [String]
    var sourceFilePath: String
    var appliedAt: Date
    var ruleSnapshot: SidecarRuleSnapshot
    var userOverrides: SidecarUserOverrides
    /// Canonical TestRecord sample identity — the final RouteTarget.sampleId at apply
    /// time, already guaranteed to equal LibrarySample.id. Distinct from
    /// ruleSnapshot.fields.sampleID, which remains rule-output provenance only.
    /// Optional for backward compatibility with sidecars written before this field existed.
    var sampleKey: String?
    /// The measurement's actual clock time, NOT sidecar/import/recompute write time
    /// (that remains `appliedAt`). Optional for backward compatibility.
    var measurementTimestamp: SidecarMeasurementTimestamp?

    init(
        workflow: String,
        autoDetectedWorkflow: String? = nil,
        workflowOverride: String? = nil,
        workflowSource: WorkflowSource? = nil,
        workflowDisplayName: String,
        channels: [String],
        sourceFilePath: String,
        appliedAt: Date,
        ruleSnapshot: SidecarRuleSnapshot,
        userOverrides: SidecarUserOverrides = .empty,
        sampleKey: String? = nil,
        measurementTimestamp: SidecarMeasurementTimestamp? = nil
    ) {
        self.version = 2
        self.workflow = workflow
        self.autoDetectedWorkflow = Self.trimmedNonEmpty(autoDetectedWorkflow) ?? workflow
        self.workflowOverride = Self.trimmedNonEmpty(workflowOverride)
        if let workflowSource {
            self.workflowSource = workflowSource
        } else if self.workflowOverride != nil || self.workflow != self.autoDetectedWorkflow {
            self.workflowSource = .manual
        } else {
            self.workflowSource = .auto
        }
        self.workflowDisplayName = workflowDisplayName
        self.channels = channels
        self.sourceFilePath = sourceFilePath
        self.appliedAt = appliedAt
        self.ruleSnapshot = ruleSnapshot
        self.userOverrides = userOverrides
        self.sampleKey = sampleKey
        self.measurementTimestamp = measurementTimestamp
    }

    // MARK: Custom Codable — handles v1 → v2 migration on decode

    private enum CodingKeys: String, CodingKey {
        case version, workflow, autoDetectedWorkflow, workflowOverride, workflowSource, workflowDisplayName, channels, sourceFilePath, appliedAt
        case ruleSnapshot, userOverrides
        case sampleKey, measurementTimestamp
        case v1Conditions = "conditions"        // v1-only key; not emitted on encode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let detectedVersion = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        workflow = try c.decodeIfPresent(String.self, forKey: .workflow) ?? ""
        autoDetectedWorkflow = Self.trimmedNonEmpty(try c.decodeIfPresent(String.self, forKey: .autoDetectedWorkflow)) ?? workflow
        workflowOverride = Self.trimmedNonEmpty(try c.decodeIfPresent(String.self, forKey: .workflowOverride))
        workflowSource = try c.decodeIfPresent(WorkflowSource.self, forKey: .workflowSource)
            ?? (workflowOverride != nil ? .manual : .auto)
        workflowDisplayName = try c.decodeIfPresent(String.self, forKey: .workflowDisplayName) ?? workflow
        channels = try c.decodeIfPresent([String].self, forKey: .channels) ?? []
        sourceFilePath = try c.decodeIfPresent(String.self, forKey: .sourceFilePath) ?? ""
        appliedAt = try c.decodeIfPresent(Date.self, forKey: .appliedAt) ?? .now
        // Absent on sidecars written before Phase 1 of the TestRecord architecture — nil is expected.
        sampleKey = try c.decodeIfPresent(String.self, forKey: .sampleKey)
        measurementTimestamp = try c.decodeIfPresent(SidecarMeasurementTimestamp.self, forKey: .measurementTimestamp)

        if detectedVersion >= 2 {
            version = detectedVersion
            ruleSnapshot = try c.decode(SidecarRuleSnapshot.self, forKey: .ruleSnapshot)
            userOverrides = try c.decodeIfPresent(SidecarUserOverrides.self, forKey: .userOverrides) ?? .empty
        } else {
            // v1 → v2 in-memory migration; caller is responsible for atomic write-back.
            version = 2
            autoDetectedWorkflow = workflow
            workflowOverride = nil
            workflowSource = .auto
            let v1Conditions = try c.decodeIfPresent([String: String].self, forKey: .v1Conditions) ?? [:]
            let migratedConditions: [String: SourcedValue] = v1Conditions.reduce(into: [:]) { acc, pair in
                acc[pair.key] = SourcedValue(
                    value: pair.value,
                    source: RuleRef.migrationV1(fieldPath: "conditions.\(pair.key)")
                )
            }
            ruleSnapshot = SidecarRuleSnapshot(
                ruleSetVersion: 0,
                ruleSetFingerprint: "legacy:v1-unknown",
                appliedAt: appliedAt,
                fields: SidecarRuleFields(
                    sampleID: nil,
                    conditions: migratedConditions,
                    substrateTags: []
                )
            )
            userOverrides = .empty
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(workflow, forKey: .workflow)
        try c.encode(autoDetectedWorkflow, forKey: .autoDetectedWorkflow)
        try c.encodeIfPresent(workflowOverride, forKey: .workflowOverride)
        try c.encode(workflowSource, forKey: .workflowSource)
        try c.encode(workflowDisplayName, forKey: .workflowDisplayName)
        try c.encode(channels, forKey: .channels)
        try c.encode(sourceFilePath, forKey: .sourceFilePath)
        try c.encode(appliedAt, forKey: .appliedAt)
        try c.encode(ruleSnapshot, forKey: .ruleSnapshot)
        try c.encode(userOverrides, forKey: .userOverrides)
        try c.encodeIfPresent(sampleKey, forKey: .sampleKey)
        try c.encodeIfPresent(measurementTimestamp, forKey: .measurementTimestamp)
        // v1Conditions is intentionally NOT encoded (top-level `conditions` is a v1-only field)
    }
}

// MARK: - Effective value accessors

extension SpinLabFileSidecar {
    var resolvedWorkflow: String {
        Self.trimmedNonEmpty(workflowOverride)
        ?? Self.trimmedNonEmpty(autoDetectedWorkflow)
        ?? Self.trimmedNonEmpty(workflow)
        ?? ""
    }

    /// userOverrides.conditions layered on top of ruleSnapshot.fields.conditions.
    var effectiveConditions: [String: String] {
        var result = ruleSnapshot.fields.conditions.mapValues(\.value)
        for (key, override) in userOverrides.conditions {
            result[key] = override.value
        }
        return result
    }

    func isConditionManuallyOverridden(_ id: String) -> Bool {
        userOverrides.conditions[id] != nil
    }

    /// "manual" when user-overridden, otherwise the ruleRef string.
    func effectiveConditionSource(_ id: String) -> String? {
        if userOverrides.conditions[id] != nil { return "manual" }
        return ruleSnapshot.fields.conditions[id]?.source
    }

    /// Rule-layer value before any userOverride (UI mixed-state tooltip use).
    func ruleSnapshotConditionValue(_ id: String) -> String? {
        ruleSnapshot.fields.conditions[id]?.value
    }

    var effectiveSampleID: String? { ruleSnapshot.fields.sampleID?.value }
    var effectiveSubstrateTags: [String] { ruleSnapshot.fields.substrateTags.map(\.value) }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
