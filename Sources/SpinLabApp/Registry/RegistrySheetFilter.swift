import Foundation

enum RegistrySheetFilter {
    static func shouldSkipSheet(named sheetName: String, excludedSheetNames: Set<String>) -> Bool {
        let trimmedName = sheetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return true
        }
        if trimmedName.hasPrefix("__") {
            return true
        }
        return excludedSheetNames.contains(trimmedName)
    }
}
