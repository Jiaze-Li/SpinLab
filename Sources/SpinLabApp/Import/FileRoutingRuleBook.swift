import Foundation

struct FileRoutingRuleBook {
    struct FileTokenDescriptor {
        var batch: String?
        var treatment: String?
        var material: String?
        var orientation: String?

        var hasSubstrateSignal: Bool {
            treatment != nil || material != nil || orientation != nil
        }

        var isEmpty: Bool {
            batch == nil && !hasSubstrateSignal
        }
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
        fallback: FileTokenDescriptor?
    ) -> FileTokenDescriptor? {
        var descriptor = explicitDescriptor(from: sampleInput) ?? FileTokenDescriptor()
        let substrate = substrateDescriptor(from: sampleTags)

        descriptor.treatment = descriptor.treatment ?? substrate.treatment
        descriptor.material = descriptor.material ?? substrate.material
        descriptor.orientation = descriptor.orientation ?? substrate.orientation

        if let fallback {
            descriptor.batch = descriptor.batch ?? fallback.batch
            descriptor.treatment = descriptor.treatment ?? fallback.treatment
            descriptor.material = descriptor.material ?? fallback.material
            descriptor.orientation = descriptor.orientation ?? fallback.orientation
        }

        return descriptor.isEmpty ? nil : descriptor
    }

    func resolvedFileToken(
        sampleInput: String?,
        sampleTags: [String],
        fallback: FileTokenDescriptor?
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

    func renderFileToken(from descriptor: FileTokenDescriptor) -> String? {
        let substrateComponent: String? = {
            var substrate = ""
            if let material = descriptor.material, let orientation = descriptor.orientation {
                substrate = "\(material)(\(orientation))"
            } else if let material = descriptor.material {
                substrate = material
            } else if let orientation = descriptor.orientation {
                substrate = orientation
            }

            if let treatment = descriptor.treatment {
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

    private func explicitDescriptor(from sampleInput: String?) -> FileTokenDescriptor? {
        guard let input = normalizedSampleInput(sampleInput) else {
            return nil
        }

        let keyParts = input.split(separator: "|", omittingEmptySubsequences: false)
        if keyParts.count == 4 {
            let batch = cleaned(String(keyParts[0]))?.uppercased()
            let processingRaw = cleaned(String(keyParts[1]))?.uppercased() ?? ""
            let materialRaw = cleaned(String(keyParts[2]))?.uppercased() ?? ""
            let orientationRaw = cleaned(String(keyParts[3]))?.uppercased() ?? ""
            return FileTokenDescriptor(
                batch: batch,
                treatment: treatmentToken(from: processingRaw),
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
                return FileTokenDescriptor(
                    batch: batch,
                    treatment: substrate.treatment,
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
            return FileTokenDescriptor(
                batch: head.uppercased(),
                treatment: substrate.treatment,
                material: substrate.material,
                orientation: substrate.orientation
            )
        }

        return FileTokenDescriptor(batch: input.uppercased(), treatment: nil, material: nil, orientation: nil)
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
        let lower = normalized.lowercased()
        if lower.contains("hf") {
            return "HF"
        }
        if lower.contains("bake") || lower.contains("baked") {
            return "baked"
        }
        if lower == "o" || lower.contains("origin") || lower.contains("original") {
            return "o"
        }
        return nil
    }

    private func substrateTokens(from raw: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/|,;+"))
        let tokens = raw
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return tokens.isEmpty ? [raw] : tokens
    }

    private func substrateDescriptor(from tags: [String]) -> FileTokenDescriptor {
        var descriptor = FileTokenDescriptor()

        for tag in tags {
            let normalized = normalizeSubstrateToken(tag)
            if descriptor.treatment == nil {
                descriptor.treatment = treatmentToken(from: normalized)
            }
            if descriptor.material == nil {
                descriptor.material = materialToken(from: normalized)
            }
            if descriptor.orientation == nil,
               let orientation = orientationToken(from: normalized) {
                descriptor.orientation = orientation
            }
        }

        return descriptor
    }

    private func materialToken(from normalized: String) -> String? {
        if normalized.contains("sto") {
            return "STO"
        }
        if normalized.contains("ngo") {
            return "NGO"
        }
        if normalized.contains("mao") {
            return "MAO"
        }
        if normalized.contains("mgo") {
            return "MGO"
        }
        if normalized.contains("al2o3") {
            return "AL2O3"
        }
        if normalized == "si" || normalized.contains("onsi") {
            return "SI"
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
        guard let range = normalized.range(of: #"(111|001|110|100|0001)"#, options: .regularExpression) else {
            return nil
        }
        return String(normalized[range])
    }
}
