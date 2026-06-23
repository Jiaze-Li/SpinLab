import Foundation

protocol RegistryLookupRuleProviding {
    func shouldIndexSheet(named sheetName: String, headerByColumn: [Int: String]) -> Bool
    func sampleColumnIndex(headerByColumn: [Int: String]) -> Int?
    func sampleIDCandidates(from cellValue: String) -> [String]
    func normalizedLookupSampleID(_ sampleID: String) -> String
}

struct RegistryLookupRuleBook: RegistryLookupRuleProviding {
    private let sampleHeaderKeys: Set<String>
    private let excludedSheetNames: Set<String>
    private let sampleTokenSeparators: CharacterSet
    private let parseSampleIDsFromTokens: ([String]) -> [String]

    init(ruleProvider: any SpinLabRuleProviding = SpinLabRuleProvider.shared) {
        let ruleSet = ruleProvider.ruleSet()
        let registryRules = ruleSet.registry
        let headerAliases = registryRules?.sampleHeaderAliases ?? []
        sampleHeaderKeys = Set(headerAliases.map(Self.normalizedHeader))

        excludedSheetNames = Set(registryRules?.excludedSheetNames ?? [])

        let separatorString = ruleSet.tokenization.separators
            + (registryRules?.sampleCellSeparators ?? "")
        sampleTokenSeparators = CharacterSet(charactersIn: separatorString)
        parseSampleIDsFromTokens = ruleSet.sampleIDs(from:)
    }

    init(ruleLoadResult: RuleLoader.LoadResult) {
        self.init(ruleProvider: InlineRuleProvider(loadResult: ruleLoadResult))
    }

    func shouldIndexSheet(named sheetName: String, headerByColumn: [Int: String]) -> Bool {
        guard !RegistrySheetFilter.shouldSkipSheet(named: sheetName, excludedSheetNames: excludedSheetNames) else {
            return false
        }
        return sampleColumnIndex(headerByColumn: headerByColumn) != nil
    }

    func sampleColumnIndex(headerByColumn: [Int: String]) -> Int? {
        for column in headerByColumn.keys.sorted() {
            guard let header = headerByColumn[column] else {
                continue
            }
            if sampleHeaderKeys.contains(Self.normalizedHeader(header)) {
                return column
            }
        }
        return nil
    }

    func sampleIDCandidates(from cellValue: String) -> [String] {
        let chunks = cellValue.components(separatedBy: sampleTokenSeparators)
        var seen: Set<String> = []
        var ordered: [String] = []

        for chunk in chunks {
            let parsed = parseSampleIDsFromTokens([chunk])
            guard let normalized = parsed.first,
                  !normalized.isEmpty,
                  !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            ordered.append(normalized)
        }

        return ordered
    }

    func normalizedLookupSampleID(_ sampleID: String) -> String {
        if let normalized = parseSampleIDsFromTokens([sampleID]).first {
            return normalized
        }
        return sampleID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func normalizedHeader(_ header: String) -> String {
        header.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }
}
