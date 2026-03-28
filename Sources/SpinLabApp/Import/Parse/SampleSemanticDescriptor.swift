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

    static func fromSampleKey(_ sampleKey: String) -> SampleSemanticDescriptor? {
        let parts = sampleKey.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4 else {
            return nil
        }

        let processing = parts[1]
            .split(separator: "+", omittingEmptySubsequences: true)
            .map(String.init)
        return SampleSemanticDescriptor(
            batch: parts[0],
            processingTokens: Set(processing),
            material: parts[2],
            orientation: parts[3]
        )
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
        guard let token else {
            return nil
        }
        let normalizedInput = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedInput.isEmpty else {
            return nil
        }

        let treatmentKeywords = ruleProvider.sharedSubstrateRules().treatmentKeywords
            .mapValues { keywords in keywords.map { $0.lowercased() } }
        for canonical in treatmentKeywords.keys.sorted() {
            guard let keywords = treatmentKeywords[canonical] else {
                continue
            }
            if keywords.contains(where: { keyword in
                if keyword.count <= 1 {
                    return normalizedInput == keyword
                }
                return normalizedInput == keyword || normalizedInput.contains(keyword)
            }) {
                return canonical
            }
        }
        return nil
    }

    static func normalizedProcessingTokenForRules(_ token: String?) -> String? {
        normalizedProcessingToken(token)
    }
}
