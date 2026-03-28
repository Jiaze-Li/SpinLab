import Foundation

protocol RegistryLookupRuleProviding {
    func shouldIndexSheet(named sheetName: String, headerByColumn: [Int: String]) -> Bool
    func sampleColumnIndex(headerByColumn: [Int: String]) -> Int?
    func sampleIDCandidates(from cellValue: String) -> [String]
    func normalizedLookupSampleID(_ sampleID: String) -> String
}

struct RegistryLookupRuleBook: RegistryLookupRuleProviding {
    private let sampleHeaderKeys: Set<String> = [
        "sampleid",
        "sample",
        "编号",
        "样品编号"
    ]
    private let sampleTokenSeparators: CharacterSet
    private let parseSampleIDsFromTokens: ([String]) -> [String]

    init(ruleLoadResult: RuleLoader.LoadResult = RuleLoader.shared.loadCached()) {
        let separatorString = ruleLoadResult.ruleSet.tokenization.separators + "/／,，;；|"
        sampleTokenSeparators = CharacterSet(charactersIn: separatorString)
        parseSampleIDsFromTokens = ruleLoadResult.ruleSet.sampleIDs(from:)
    }

    func shouldIndexSheet(named sheetName: String, headerByColumn: [Int: String]) -> Bool {
        let trimmedName = sheetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return false
        }
        guard !trimmedName.hasPrefix("__") else {
            return false
        }
        return sampleColumnIndex(headerByColumn: headerByColumn) != nil
    }

    func sampleColumnIndex(headerByColumn: [Int: String]) -> Int? {
        for column in headerByColumn.keys.sorted() {
            guard let header = headerByColumn[column] else {
                continue
            }
            if sampleHeaderKeys.contains(normalizedHeader(header)) {
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

    private func normalizedHeader(_ header: String) -> String {
        header.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }
}
