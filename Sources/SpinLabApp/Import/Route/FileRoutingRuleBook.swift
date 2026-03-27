import Foundation

struct FileRoutingRuleBook {
    nonisolated(unsafe) private static var semanticRuleCache: (fingerprint: String, rules: FileRoutingSemanticRules)?
    private static let semanticRuleCacheLock = NSLock()

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

        descriptor = SampleSemanticDescriptor(
            batch: descriptor.batch,
            processingTokens: descriptor.processingTokens.union(substrate.processingTokens),
            material: descriptor.material ?? substrate.material,
            orientation: descriptor.orientation ?? substrate.orientation
        )

        if let fallback {
            descriptor = SampleSemanticDescriptor(
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
            if let token = treatmentToken(from: processingRaw) {
                processingTokens.insert(token)
            }
            return SampleSemanticDescriptor(
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
                return SampleSemanticDescriptor(
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
            return SampleSemanticDescriptor(
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

    private func treatmentToken(from normalized: String) -> String? {
        let probe = normalizeSubstrateToken(normalized).uppercased()
        let semanticRules = Self.loadSemanticRulesForCurrentFingerprint()
        for (needle, canonical) in semanticRules.treatmentNeedles {
            let normalizedNeedle = needle.uppercased()
            if normalizedNeedle.count <= 1 {
                if probe == normalizedNeedle {
                    return canonical
                }
                continue
            }
            if probe.contains(normalizedNeedle) {
                return canonical
            }
        }
        return nil
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

        for tag in tags {
            let normalized = normalizeSubstrateToken(tag)
            if let treatment = treatmentToken(from: normalized) {
                processingTokens.insert(treatment)
            }
            if material == nil {
                material = materialToken(from: normalized)
            }
            if orientation == nil,
               let candidate = orientationToken(from: normalized) {
                orientation = candidate
            }
        }

        return SampleSemanticDescriptor(
            batch: nil,
            processingTokens: processingTokens,
            material: material,
            orientation: orientation
        )
    }

    private func materialToken(from normalized: String) -> String? {
        let probe = normalized.uppercased()
        let semanticRules = Self.loadSemanticRulesForCurrentFingerprint()
        for (needle, canonical) in semanticRules.materialNeedles {
            if probe.contains(needle) {
                return canonical
            }
        }
        return nil
    }

    private func normalizeSubstrateToken(_ token: String) -> String {
        token.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")
    }

    private func orientationToken(from normalized: String) -> String? {
        let semanticRules = Self.loadSemanticRulesForCurrentFingerprint()
        for token in semanticRules.orientationNeedles.sorted(by: { $0.count > $1.count }) {
            if normalized.contains(token) {
                return token == "100" ? "001" : token
            }
        }
        return nil
    }

    private static func loadSemanticRulesForCurrentFingerprint() -> FileRoutingSemanticRules {
        let ruleLoadResult = RuleLoader.shared.loadCached()
        let fingerprint = ruleLoadResult.metadata.fingerprint

        semanticRuleCacheLock.lock()
        defer { semanticRuleCacheLock.unlock() }

        if let cached = semanticRuleCache, cached.fingerprint == fingerprint {
            return cached.rules
        }

        let refreshedRules = FileRoutingSemanticRules.load()
        semanticRuleCache = (fingerprint: fingerprint, rules: refreshedRules)
        return refreshedRules
    }
}
