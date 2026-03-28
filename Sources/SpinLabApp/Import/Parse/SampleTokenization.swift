import Foundation

enum SampleTokenization {
    static func split(_ value: String, separators: String) -> [String] {
        value
            .split(whereSeparator: { separators.contains($0) })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func matchingTokens(from value: String) -> [String] {
        let upper = value.uppercased()
        let pattern = #"[^A-Z0-9]+"#
        let replaced = upper.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        return replaced
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .flatMap(splitAlphaNumericToken)
            .map { token in
                if let canonical = SampleSemanticDescriptor.normalizedProcessingTokenForRules(token) {
                    return canonical.uppercased()
                }
                return token
            }
            .filter { $0 != "UNKNOWN" }
            .filter { !$0.isEmpty }
    }

    private static func splitAlphaNumericToken(_ token: String) -> [String] {
        guard !token.isEmpty else {
            return []
        }

        var result: [String] = []
        var current = ""
        var currentIsDigit: Bool?

        for scalar in token.unicodeScalars {
            let isDigit = CharacterSet.decimalDigits.contains(scalar)
            if let currentIsDigit, currentIsDigit != isDigit {
                if !current.isEmpty {
                    result.append(current)
                }
                current = ""
            }
            current.append(Character(scalar))
            currentIsDigit = isDigit
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result
    }
}
