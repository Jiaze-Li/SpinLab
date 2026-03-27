import Foundation

struct ArchivedRecordResolverService {
    let registrySubstrateRules: any RegistrySubstrateRuleProviding

    func metadataValue(in lookup: SampleRegistryLookupResult?, keys: [String]) -> String? {
        guard let lookup else {
            return nil
        }

        let normalizedKeys = keys.map { normalizeKey($0) }
        for (key, value) in lookup.metadata {
            if normalizedKeys.contains(normalizeKey(key)),
               let cleaned = normalized(value) {
                return cleaned
            }
        }
        return nil
    }

    func measurementNotes(
        for pending: SpinLabDomain.PendingImport,
        draft: PendingImportConfirmationDraft,
        registryLookup: SampleRegistryLookupResult?
    ) -> String {
        var lines: [String] = []

        let temp = draft.temperature.trimmingCharacters(in: .whitespacesAndNewlines)
        if !temp.isEmpty {
            lines.append("Measurement temperature: \(temp)")
        }

        let growthTemperature = pending.parsedHints.growthTemperature
            ?? metadataValue(in: registryLookup, keys: ["生长温度", "Growth Temperature", "growthtemperature"])
        if let growthTemperature {
            lines.append("Growth temperature: \(growthTemperature)")
        }

        if let rotationHint = pending.parsedHints.rotationHint {
            lines.append("Rotation hint: \(rotationHint)")
        }

        if let warning = substrateWarning(for: pending, registryLookup: registryLookup) {
            lines.append("Substrate warning: \(warning)")
        }

        return lines.joined(separator: "\n")
    }

    func substrateWarning(
        for pending: SpinLabDomain.PendingImport,
        registryLookup: SampleRegistryLookupResult?
    ) -> String? {
        guard let lookup = registryLookup else {
            return nil
        }
        let resolution = resolvedSubstrate(
            from: lookup,
            substrateTags: pending.parsedHints.substrateTags,
            allowsOriginToken: hasStandaloneOriginToken(for: pending)
        )
        return resolution.warning
    }

    private func resolvedSubstrate(
        from lookup: SampleRegistryLookupResult,
        substrateTags: [String],
        allowsOriginToken: Bool
    ) -> RegistrySubstrateResolution {
        registrySubstrateRules.resolvedSubstrate(
            sampleID: lookup.sampleID,
            substrateValue: metadataValue(in: lookup, keys: ["substrate", "Substrate", "衬底"]),
            substrateTags: substrateTags,
            allowsOriginToken: allowsOriginToken
        )
    }

    private func hasStandaloneOriginToken(for pending: SpinLabDomain.PendingImport) -> Bool {
        registrySubstrateRules.hasStandaloneOriginToken(
            fileName: pending.fileName,
            originalFilePath: pending.originalFilePath
        )
    }

    private func normalizeKey(_ key: String) -> String {
        key.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
