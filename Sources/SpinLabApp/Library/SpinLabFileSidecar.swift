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
    var workflowDisplayName: String
    var channels: [String]
    var sourceFilePath: String
    var appliedAt: Date
    var ruleSnapshot: SidecarRuleSnapshot
    var userOverrides: SidecarUserOverrides

    init(
        workflow: String,
        workflowDisplayName: String,
        channels: [String],
        sourceFilePath: String,
        appliedAt: Date,
        ruleSnapshot: SidecarRuleSnapshot,
        userOverrides: SidecarUserOverrides = .empty
    ) {
        self.version = 2
        self.workflow = workflow
        self.workflowDisplayName = workflowDisplayName
        self.channels = channels
        self.sourceFilePath = sourceFilePath
        self.appliedAt = appliedAt
        self.ruleSnapshot = ruleSnapshot
        self.userOverrides = userOverrides
    }

    // MARK: Custom Codable — handles v1 → v2 migration on decode

    private enum CodingKeys: String, CodingKey {
        case version, workflow, workflowDisplayName, channels, sourceFilePath, appliedAt
        case ruleSnapshot, userOverrides
        case v1Conditions = "conditions"        // v1-only key; not emitted on encode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let detectedVersion = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        workflow = try c.decodeIfPresent(String.self, forKey: .workflow) ?? ""
        workflowDisplayName = try c.decodeIfPresent(String.self, forKey: .workflowDisplayName) ?? workflow
        channels = try c.decodeIfPresent([String].self, forKey: .channels) ?? []
        sourceFilePath = try c.decodeIfPresent(String.self, forKey: .sourceFilePath) ?? ""
        appliedAt = try c.decodeIfPresent(Date.self, forKey: .appliedAt) ?? .now

        if detectedVersion >= 2 {
            version = detectedVersion
            ruleSnapshot = try c.decode(SidecarRuleSnapshot.self, forKey: .ruleSnapshot)
            userOverrides = try c.decodeIfPresent(SidecarUserOverrides.self, forKey: .userOverrides) ?? .empty
        } else {
            // v1 → v2 in-memory migration; caller is responsible for atomic write-back.
            version = 2
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
        try c.encode(workflowDisplayName, forKey: .workflowDisplayName)
        try c.encode(channels, forKey: .channels)
        try c.encode(sourceFilePath, forKey: .sourceFilePath)
        try c.encode(appliedAt, forKey: .appliedAt)
        try c.encode(ruleSnapshot, forKey: .ruleSnapshot)
        try c.encode(userOverrides, forKey: .userOverrides)
        // v1Conditions is intentionally NOT encoded (top-level `conditions` is a v1-only field)
    }
}

// MARK: - Effective value accessors

extension SpinLabFileSidecar {
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
}
