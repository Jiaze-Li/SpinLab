import Foundation

struct SampleSemanticDescriptor: Hashable {
    private static let ruleProvider: any SpinLabRuleProviding = SpinLabRuleProvider.shared

    var batch: String?
    var processingTokens: Set<String>
    var material: String?
    var orientation: String?

    init(
        batch: String?,
        processingTokens: Set<String> = [],
        material: String?,
        orientation: String?
    ) {
        self.batch = Self.normalizedBatch(batch)
        self.processingTokens = Set(processingTokens.compactMap(Self.normalizedProcessingToken))
        self.material = Self.normalizedMaterial(material)
        self.orientation = Self.normalizedOrientation(orientation)
    }

    var canonicalKey: String? {
        guard let batch else {
            return nil
        }
        return [
            batch,
            processingComponent,
            material ?? "UNKNOWN",
            orientation ?? "UNKNOWN"
        ].joined(separator: "|")
    }

    var hasSubstrateSignal: Bool {
        !processingTokens.isEmpty || material != nil || orientation != nil
    }

    private var processingComponent: String {
        processingTokens.sorted().joined(separator: "+")
    }

    // Use when processing tokens are already validated by an external rule provider
    // (e.g. FileRoutingRuleBook with injected rules) — bypasses the global-singleton
    // re-validation in init so injected-provider test scenarios work correctly.
    static func withPrevalidatedTokens(
        batch: String?,
        processingTokens: Set<String>,
        material: String?,
        orientation: String?
    ) -> SampleSemanticDescriptor {
        var d = SampleSemanticDescriptor(batch: batch, processingTokens: [], material: material, orientation: orientation)
        d.processingTokens = processingTokens
        return d
    }

    static func fromSampleKey(_ sampleKey: String) -> SampleSemanticDescriptor? {
        let parts = sampleKey.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4 else {
            return nil
        }

        // Tokens in a canonical sampleKey are already in their canonical form — bypass
        // normalizedProcessingToken validation so they are preserved regardless of the
        // current rule set configuration.
        let rawTokens = parts[1]
            .split(separator: "+", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var descriptor = SampleSemanticDescriptor(
            batch: parts[0],
            processingTokens: [],
            material: parts[2],
            orientation: parts[3]
        )
        descriptor.processingTokens = Set(rawTokens)
        return descriptor
    }

    static func fromLibrarySubstrate(
        batchId: String,
        substrateTokens: [String],
        material: String?,
        orientation: String?
    ) -> SampleSemanticDescriptor {
        let processing = substrateTokens.compactMap(normalizedProcessingTokenForRules)
        return SampleSemanticDescriptor(
            batch: batchId,
            processingTokens: Set(processing),
            material: material,
            orientation: orientation
        )
    }

    private static func normalizedBatch(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed.uppercased()
    }

    private static func normalizedMaterial(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.uppercased() != "UNKNOWN" else {
            return nil
        }
        return trimmed.uppercased()
    }

    private static func normalizedOrientation(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.uppercased() != "UNKNOWN" else {
            return nil
        }
        return trimmed.uppercased()
    }

    private static func normalizedProcessingToken(_ token: String?) -> String? {
        guard let token else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let compiled = ruleProvider.ruleSet().compiled
        let normalized = FilenameRuleSet.normalizeForSubstrate(trimmed)
        for entry in compiled.substrateTreatmentEntries {
            if entry.equalsKeysNormalized.contains(normalized)
                || entry.containsNeedlesNormalized.contains(where: { normalized.contains($0) }) {
                return entry.displayName
            }
        }
        return nil
    }

    static func normalizedProcessingTokenForRules(_ token: String?) -> String? {
        normalizedProcessingToken(token)
    }
}
