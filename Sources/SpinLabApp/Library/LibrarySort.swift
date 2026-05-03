import Foundation

enum LibrarySort {
    static func batchSortKey(_ value: String) -> (prefix: String, number: Int?, suffix: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^([A-Za-z]+)(\\d+)?(.*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (trimmed, nil, "")
        }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range) else {
            return (trimmed, nil, "")
        }
        let prefix = Range(match.range(at: 1), in: trimmed).map { String(trimmed[$0]) } ?? trimmed
        let number = Range(match.range(at: 2), in: trimmed).flatMap { Int(trimmed[$0]) }
        let suffix = Range(match.range(at: 3), in: trimmed).map { String(trimmed[$0]) } ?? ""
        return (prefix.uppercased(), number, suffix)
    }

    static func sortedExistingDrawerSamples<T>(
        _ items: [T],
        prefix: (T) -> String,
        batchId: (T) -> String,
        substrate: (T) -> String
    ) -> [T] {
        items.sorted {
            let lp = prefix($0), rp = prefix($1)
            if lp != rp { return lp < rp }
            if compareBatch(batchId($0), batchId($1)) { return true }
            if compareBatch(batchId($1), batchId($0)) { return false }
            return substrate($0) < substrate($1)
        }
    }

    static func compareBatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = batchSortKey(lhs)
        let right = batchSortKey(rhs)
        if left.prefix != right.prefix {
            return left.prefix < right.prefix
        }
        if let ln = left.number, let rn = right.number, ln != rn {
            return ln < rn
        }
        if left.number != nil && right.number == nil {
            return true
        }
        if left.number == nil && right.number != nil {
            return false
        }
        if left.suffix != right.suffix {
            return left.suffix < right.suffix
        }
        return lhs < rhs
    }
}
