import Foundation

/// Resolves a title template string by substituting #token placeholders.
/// Shared by all workflow renderers (3ω, AHE, etc.).
///
/// Tokens: #tab, #device, #sample, #method, plus any numericDisplay keys (#氧压, #能量, etc.)
/// Unresolved tokens are silently removed. Extra whitespace is collapsed.
struct WorkbenchTitleResolver {

    static func resolve(template: String, tokens: [String: String]) -> String {
        var result = template
        for (key, value) in tokens {
            result = result.replacingOccurrences(of: "#\(key)", with: value)
        }
        result = result.replacingOccurrences(of: "#\\S+", with: "", options: .regularExpression)
        return result.split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
