import Foundation

/// The tokens a title template can actually use: the ones the renderer always supplies for the
/// workflow/tab plus those the current data provides. Nothing else is offered (CS-9).
enum WorkbenchTitleTokens {
    static func available(renderer: [String], data: [String: String]) -> [String] {
        let present = data.filter { !$0.value.isEmpty && !renderer.contains($0.key) }
        let fixed = ["sample", "测试温度"]
        let numeric = present.keys.filter { !fixed.contains($0) }.sorted()
        return (renderer + fixed.filter { present[$0] != nil } + numeric).map { "#\($0)" }
    }
}

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
