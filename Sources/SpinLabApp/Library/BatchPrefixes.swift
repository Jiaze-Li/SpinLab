import Foundation

/// The batch prefixes (PN, PT, LNO …) SpinLab knows. The Rules Book's sample-identification
/// "starts with" entries are the only list of them; every screen and import step reads it from here.
enum BatchPrefixes {
    static func from(_ sampleId: FilenameRuleSetSchema.SampleIdRules) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for match in sampleId.matches where match.type == .startsWith {
            let prefix = match.value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !prefix.isEmpty, seen.insert(prefix).inserted { result.append(prefix) }
        }
        return result
    }

    @MainActor
    static func current(provider: any SpinLabRuleProviding = SpinLabRuleProvider.shared) -> [String] {
        from(provider.ruleSet().sampleId)
    }
}
