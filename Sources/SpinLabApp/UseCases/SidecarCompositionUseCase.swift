import Foundation

struct SidecarCompositionBase {
    var workflow: String
    var workflowDisplayName: String
    var channels: [String]
    var sourceFilePath: String
    var existingSidecar: SpinLabFileSidecar?
}

enum SidecarCompositionUseCase {
    /// Pure function — no I/O. Import and Recompute share this identical implementation.
    static func buildRuleSnapshot(
        hints: SpinLabDomain.ParsedFilenameHints,
        ruleSetFingerprint: String,
        ruleSetVersion: Int,
        evaluatedAt: Date
    ) -> SidecarRuleSnapshot {
        let sampleIDField: SourcedValue?
        if let firstID = hints.sampleIDs.first, let ref = hints.hintSources["sampleID"] {
            sampleIDField = SourcedValue(value: firstID, source: ref)
        } else {
            sampleIDField = nil
        }

        var conditionsFields: [String: SourcedValue] = [:]
        for (id, value) in hints.conditionValues {
            guard let ref = hints.hintSources["condition.\(id)"] else { continue }
            conditionsFields[id] = SourcedValue(value: value, source: ref)
        }

        let substrateTagsFields: [SourcedValue] = hints.substrateTags.enumerated().compactMap { idx, tag in
            guard let ref = hints.hintSources["substrateTags[\(idx)]"] else { return nil }
            return SourcedValue(value: tag, source: ref)
        }

        return SidecarRuleSnapshot(
            ruleSetVersion: ruleSetVersion,
            ruleSetFingerprint: ruleSetFingerprint,
            appliedAt: evaluatedAt,
            fields: SidecarRuleFields(
                sampleID: sampleIDField,
                conditions: conditionsFields,
                substrateTags: substrateTagsFields
            )
        )
    }

    /// Compose the final sidecar. `preserveUserOverrides: true` → keep existing sidecar's
    /// userOverrides (Recompute). `false` → start with empty overrides (Import).
    static func composeSidecarV2(
        base: SidecarCompositionBase,
        snapshot: SidecarRuleSnapshot,
        preserveUserOverrides: Bool,
        now: Date
    ) -> SpinLabFileSidecar {
        let overrides = preserveUserOverrides
            ? (base.existingSidecar?.userOverrides ?? .empty)
            : .empty
        return SpinLabFileSidecar(
            workflow: base.workflow,
            workflowDisplayName: base.workflowDisplayName,
            channels: base.channels,
            sourceFilePath: base.sourceFilePath,
            appliedAt: now,
            ruleSnapshot: snapshot,
            userOverrides: overrides
        )
    }
}
