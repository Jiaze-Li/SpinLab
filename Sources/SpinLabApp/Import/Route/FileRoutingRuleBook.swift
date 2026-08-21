import Foundation

struct FileRoutingRuleBook {
    nonisolated(unsafe) private static var classifierCache: (fingerprint: String, classifier: SubstrateSemanticClassifier)?
    private static let classifierCacheLock = NSLock()

    private let injectedRuleProvider: (any SpinLabRuleProviding)?

    init(ruleProvider: (any SpinLabRuleProviding)? = nil) {
        self.injectedRuleProvider = ruleProvider
    }

    private func classifier() -> SubstrateSemanticClassifier {
        if let ruleProvider = injectedRuleProvider {
            return SubstrateSemanticClassifier(compiled: ruleProvider.ruleSet().compiled)
        }
        return Self.classifierForCurrentFingerprint()
    }

    func normalizedSampleInput(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func hasSampleSignal(sampleInput: String?, sampleTags: [String]) -> Bool {
        if normalizedSampleInput(sampleInput) != nil {
            return true
        }
        return substrateDescriptor(from: sampleTags).hasSubstrateSignal
    }

    func resolvedDescriptor(
        sampleInput: String?,
        sampleTags: [String],
        fallback: SampleSemanticDescriptor?
    ) -> SampleSemanticDescriptor? {
        var descriptor = explicitDescriptor(from: sampleInput)
            ?? SampleSemanticDescriptor(batch: nil, processingTokens: [], material: nil, orientation: nil)
        let substrate = substrateDescriptor(from: sampleTags)

        descriptor = SampleSemanticDescriptor.withPrevalidatedTokens(
            batch: descriptor.batch,
            processingTokens: descriptor.processingTokens.union(substrate.processingTokens),
            material: descriptor.material ?? substrate.material,
            orientation: descriptor.orientation ?? substrate.orientation
        )

        if let fallback {
            descriptor = SampleSemanticDescriptor.withPrevalidatedTokens(
                batch: descriptor.batch ?? fallback.batch,
                processingTokens: descriptor.processingTokens.union(fallback.processingTokens),
                material: descriptor.material ?? fallback.material,
                orientation: descriptor.orientation ?? fallback.orientation
            )
        }

        return descriptor.batch == nil && !descriptor.hasSubstrateSignal ? nil : descriptor
    }

    func resolvedFileToken(
        sampleInput: String?,
        sampleTags: [String],
        fallback: SampleSemanticDescriptor?
    ) -> String? {
        guard let descriptor = resolvedDescriptor(
            sampleInput: sampleInput,
            sampleTags: sampleTags,
            fallback: fallback
        ) else {
            return nil
        }
        return renderFileToken(from: descriptor)
    }

    func renderFileToken(from descriptor: SampleSemanticDescriptor) -> String? {
        if let canonical = descriptor.canonicalKey {
            return canonical
        }

        let substrateComponent: String? = {
            var substrate = ""
            if let material = descriptor.material, let orientation = descriptor.orientation {
                substrate = "\(material)(\(orientation))"
            } else if let material = descriptor.material {
                substrate = material
            } else if let orientation = descriptor.orientation {
                substrate = orientation
            }

            let treatment = descriptor.processingTokens.sorted().joined(separator: " ")
            if !treatment.isEmpty {
                return substrate.isEmpty ? treatment : "\(treatment) \(substrate)"
            }
            return substrate.isEmpty ? nil : substrate
        }()

        if let batch = descriptor.batch {
            if let substrateComponent {
                return "\(batch) - \(substrateComponent)"
            }
            return batch
        }

        return substrateComponent
    }

    private func explicitDescriptor(from sampleInput: String?) -> SampleSemanticDescriptor? {
        guard let input = normalizedSampleInput(sampleInput) else {
            return nil
        }

        let keyParts = input.split(separator: "|", omittingEmptySubsequences: false)
        if keyParts.count == 4 {
            let batch = cleaned(String(keyParts[0]))?.uppercased()
            let processingRaw = cleaned(String(keyParts[1])) ?? ""
            let materialRaw = cleaned(String(keyParts[2]))?.uppercased() ?? ""
            let orientationRaw = cleaned(String(keyParts[3]))?.uppercased() ?? ""
            var processingTokens: Set<String> = []
            if let token = classifier().treatment(inSegment: processingRaw) {
                processingTokens.insert(token)
            }
            return SampleSemanticDescriptor.withPrevalidatedTokens(
                batch: batch,
                processingTokens: processingTokens,
                material: materialRaw == "UNKNOWN" ? nil : materialRaw,
                orientation: orientationRaw == "UNKNOWN" ? nil : orientationRaw
            )
        }

        if input.contains("-") {
            let parts = input.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let batch = cleaned(String(parts[0]))?.uppercased()
                let substrateRaw = cleaned(String(parts[1]))
                let substrate = substrateDescriptor(from: substrateTokens(from: substrateRaw ?? ""))
                return SampleSemanticDescriptor.withPrevalidatedTokens(
                    batch: batch,
                    processingTokens: substrate.processingTokens,
                    material: substrate.material,
                    orientation: substrate.orientation
                )
            }
        }

        let components = input.split(whereSeparator: \.isWhitespace).map(String.init)
        if components.count > 1,
           let head = components.first,
           looksLikeBatchToken(head) {
            let substrate = substrateDescriptor(from: Array(components.dropFirst()))
            return SampleSemanticDescriptor.withPrevalidatedTokens(
                batch: head.uppercased(),
                processingTokens: substrate.processingTokens,
                material: substrate.material,
                orientation: substrate.orientation
            )
        }

        return SampleSemanticDescriptor(batch: input.uppercased(), processingTokens: [], material: nil, orientation: nil)
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func looksLikeBatchToken(_ token: String) -> Bool {
        let upper = token.uppercased()
        let hasLetter = upper.range(of: #"[A-Z]"#, options: .regularExpression) != nil
        let hasDigit = upper.range(of: #"\d"#, options: .regularExpression) != nil
        return hasLetter && hasDigit
    }

    private func substrateTokens(from raw: String) -> [String] {
        let separators = " /|,;+"
        let tokens = SampleTokenization.split(raw, separators: separators)
        return tokens.isEmpty ? [raw] : tokens
    }

    private func substrateDescriptor(from tags: [String]) -> SampleSemanticDescriptor {
        var processingTokens: Set<String> = []
        var material: String?
        var orientation: String?
        let classifier = self.classifier()

        for tag in tags {
            if let treatment = classifier.treatment(inSegment: tag) {
                processingTokens.insert(treatment)
            }
            if material == nil {
                material = classifier.material(inSegment: tag)
            }
            if orientation == nil,
               let candidate = classifier.orientation(inSegment: tag) {
                orientation = candidate
            }
        }

        // classifier already validated every field using this ruleBook's own ruleProvider —
        // bypass SampleSemanticDescriptor.init's re-validation via the global singleton so
        // injected-provider scenarios work correctly.
        return SampleSemanticDescriptor.withPrevalidatedTokens(
            batch: nil,
            processingTokens: processingTokens,
            material: material,
            orientation: orientation
        )
    }

    private static func classifierForCurrentFingerprint() -> SubstrateSemanticClassifier {
        let ruleProvider: any SpinLabRuleProviding = SpinLabRuleProvider.shared
        let ruleLoadResult = ruleProvider.loadResult()
        let fingerprint = ruleLoadResult.metadata.fingerprint

        classifierCacheLock.lock()
        defer { classifierCacheLock.unlock() }

        if let cached = classifierCache, cached.fingerprint == fingerprint {
            return cached.classifier
        }

        let refreshed = SubstrateSemanticClassifier(compiled: ruleLoadResult.ruleSet.compiled)
        classifierCache = (fingerprint: fingerprint, classifier: refreshed)
        return refreshed
    }
}
