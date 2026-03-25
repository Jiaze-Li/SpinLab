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
        let separators = CharacterSet(charactersIn: "/／,，;；|")
        let chunks = cellValue.components(separatedBy: separators)
        var seen: Set<String> = []
        var ordered: [String] = []

        for chunk in chunks {
            let normalized = normalizedLookupSampleID(chunk)
            guard !normalized.isEmpty, !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            ordered.append(normalized)
        }

        return ordered
    }

    func normalizedLookupSampleID(_ sampleID: String) -> String {
        sampleID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func normalizedHeader(_ header: String) -> String {
        header.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }
}
