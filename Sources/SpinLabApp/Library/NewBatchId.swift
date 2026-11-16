import Foundation

/// A new batch id is entered in two parts: a prefix picked from the Rules Book list, then a number.
/// "Other" lets the user type a whole batch id when it does not fit that shape (for example 106/SRO1).
enum NewBatchId {
    static let other = "Other"

    static func isValidNumber(_ number: String) -> Bool {
        let trimmed = number.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// "PN" + "117" -> "PN117". Empty until the number is valid, so an unfinished entry never becomes a batch.
    static func compose(prefix: String, number: String) -> String {
        guard isValidNumber(number) else { return "" }
        return prefix + number.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits an existing id such as "PN117" into a known prefix and its digits; nil when it has another shape.
    static func split(_ batchId: String, prefixes: [String]) -> (prefix: String, number: String)? {
        let upper = batchId.uppercased()
        for prefix in prefixes.sorted(by: { $0.count > $1.count }) where upper.hasPrefix(prefix) {
            let rest = String(batchId.dropFirst(prefix.count))
            if isValidNumber(rest) { return (prefix, rest) }
        }
        return nil
    }
}
