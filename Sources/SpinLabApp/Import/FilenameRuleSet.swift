import Foundation

struct FilenameRuleSet: Decodable {
    struct Tokenization: Decodable {
        var separators: String
        var caseFold: String
    }

    enum Source: String, Decodable {
        case file
        case parent
        case grandparent
    }

    struct SampleIdRules: Decodable {
        var patterns: [String]
    }

    struct BatchRules: Decodable {
        var preferSampleId: Bool
        var fallbackPatterns: [String]
    }

    struct ChannelRules: Decodable {
        var aliases: [String: String]
    }

    struct ConditionRules: Decodable {
        var temperaturePattern: String
        var currentPattern: String
        var fieldPattern: String
    }

    enum MatchScope: String, Decodable {
        case tokens
        case joined
    }

    enum MatchType: String, Decodable {
        case equals
        case equalsAny
        case contains
        case containsAny
        case equalsOrContainsAny
        case regex
    }

    struct MatchSpec: Decodable {
        var scope: MatchScope
        var type: MatchType
        var value: String?
        var values: [String]?
    }

    struct MapRule: Decodable {
        var match: MatchSpec
        var value: String
    }

    struct CompiledMapRule {
        var match: MatchSpec
        var regex: NSRegularExpression?
        var value: String
    }

    struct CompiledRules {
        var sampleIdRegexes: [NSRegularExpression] = []
        var batchRegexes: [NSRegularExpression] = []
        var temperatureRegex: NSRegularExpression?
        var currentRegex: NSRegularExpression?
        var fieldRegex: NSRegularExpression?
        var measurementNameRules: [CompiledMapRule] = []
        var measurementTagRules: [CompiledMapRule] = []
        var substrateTagRules: [CompiledMapRule] = []
        var deviceRules: [CompiledMapRule] = []
        var rotationHintRules: [CompiledMapRule] = []
        var channelAliases: [String: String] = [:]
    }

    var version: Int
    var tokenization: Tokenization
    var sources: [Source]
    var sampleId: SampleIdRules
    var batch: BatchRules
    var measurementNameRules: [MapRule]
    var measurementTagRules: [MapRule]
    var substrateTagRules: [MapRule]
    var channel: ChannelRules
    var deviceRules: [MapRule]
    var rotationHintRules: [MapRule]
    var conditions: ConditionRules

    var compiled: CompiledRules = CompiledRules()
    var loadWarnings: [String] = []

    private enum CodingKeys: String, CodingKey {
        case version
        case tokenization
        case sources
        case sampleId
        case batch
        case measurementNameRules
        case measurementTagRules
        case substrateTagRules
        case channel
        case deviceRules
        case rotationHintRules
        case conditions
    }

    mutating func compile() -> [String] {
        var warnings: [String] = []

        compiled.sampleIdRegexes = sampleId.patterns.compactMap { pattern in
            compileRegex(pattern, warnings: &warnings, label: "sampleId")
        }

        compiled.batchRegexes = batch.fallbackPatterns.compactMap { pattern in
            compileRegex(pattern, warnings: &warnings, label: "batch")
        }

        compiled.temperatureRegex = compileRegex(conditions.temperaturePattern, warnings: &warnings, label: "conditions.temperature")
        compiled.currentRegex = compileRegex(conditions.currentPattern, warnings: &warnings, label: "conditions.current")
        compiled.fieldRegex = compileRegex(conditions.fieldPattern, warnings: &warnings, label: "conditions.field")

        compiled.measurementNameRules = compileMapRules(measurementNameRules, warnings: &warnings, label: "measurementNameRules")
        compiled.measurementTagRules = compileMapRules(measurementTagRules, warnings: &warnings, label: "measurementTagRules")
        compiled.substrateTagRules = compileMapRules(substrateTagRules, warnings: &warnings, label: "substrateTagRules")
        compiled.deviceRules = compileMapRules(deviceRules, warnings: &warnings, label: "deviceRules")
        compiled.rotationHintRules = compileMapRules(rotationHintRules, warnings: &warnings, label: "rotationHintRules")

        compiled.channelAliases = channel.aliases.reduce(into: [:]) { partial, entry in
            partial[entry.key.lowercased()] = entry.value
        }

        return warnings
    }

    func sampleIDs(from tokens: [String]) -> [String] {
        var seen: Set<String> = []
        return tokens.compactMap { token in
            guard let normalized = normalizeSampleIDToken(token) else {
                return nil
            }
            guard seen.insert(normalized).inserted else {
                return nil
            }
            return normalized
        }
    }

    func batchName(from tokens: [String]) -> String? {
        if batch.preferSampleId, let sampleId = sampleIDs(from: tokens).first {
            return sampleId
        }

        for token in tokens {
            if compiled.batchRegexes.contains(where: { regexMatch(regex: $0, text: token) }) {
                return token
            }
        }

        return nil
    }

    func measurementName(from tokens: [String], joined: String) -> String? {
        firstMatchValue(from: compiled.measurementNameRules, tokens: tokens, joined: joined)
    }

    func measurementTags(from tokens: [String]) -> [String] {
        collectMatchValues(from: compiled.measurementTagRules, tokens: tokens, joined: nil)
    }

    func substrateTags(from tokens: [String]) -> [String] {
        collectMatchValues(from: compiled.substrateTagRules, tokens: tokens, joined: nil)
    }

    func deviceName(from tokens: [String]) -> String? {
        firstMatchValue(from: compiled.deviceRules, tokens: tokens, joined: nil)
    }

    func rotationHint(from tokens: [String]) -> String? {
        firstMatchValue(from: compiled.rotationHintRules, tokens: tokens, joined: nil)
    }

    func temperature(from tokens: [String]) -> String? {
        firstRegexMatch(in: tokens, regex: compiled.temperatureRegex)
    }

    func current(from tokens: [String]) -> String? {
        firstRegexMatch(in: tokens, regex: compiled.currentRegex)
    }

    func field(from tokens: [String]) -> String? {
        firstRegexMatch(in: tokens, regex: compiled.fieldRegex)
    }

    func normalizeChannel(_ token: String) -> String? {
        compiled.channelAliases[token.lowercased()]
    }

    private func compileRegex(_ pattern: String, warnings: inout [String], label: String) -> NSRegularExpression? {
        guard !pattern.isEmpty else {
            return nil
        }
        do {
            return try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            warnings.append("Failed to compile regex for \(label): \(pattern)")
            return nil
        }
    }

    private func compileMapRules(_ rules: [MapRule], warnings: inout [String], label: String) -> [CompiledMapRule] {
        rules.map { rule in
            var compiledRule = CompiledMapRule(match: rule.match, regex: nil, value: rule.value)
            if rule.match.type == .regex, let pattern = rule.match.value {
                compiledRule.regex = compileRegex(pattern, warnings: &warnings, label: label)
            }
            return compiledRule
        }
    }

    private func normalizeSampleIDToken(_ token: String) -> String? {
        let uppercased = token.uppercased()
        for regex in compiled.sampleIdRegexes {
            if regexMatch(regex: regex, text: uppercased) {
                return uppercased
            }
        }
        return nil
    }

    private func firstMatchValue(from rules: [CompiledMapRule], tokens: [String], joined: String?) -> String? {
        for rule in rules {
            if matches(rule: rule, tokens: tokens, joined: joined) {
                return rule.value
            }
        }
        return nil
    }

    private func collectMatchValues(from rules: [CompiledMapRule], tokens: [String], joined: String?) -> [String] {
        var collected: [String] = []
        for rule in rules {
            if matches(rule: rule, tokens: tokens, joined: joined) {
                collected.append(rule.value)
            }
        }
        return collected
    }

    private func matches(rule: CompiledMapRule, tokens: [String], joined: String?) -> Bool {
        switch rule.match.scope {
        case .tokens:
            return tokens.contains(where: { tokenMatches(token: $0, rule: rule) })
        case .joined:
            guard let joined else {
                return false
            }
            return stringMatches(text: joined, rule: rule)
        }
    }

    private func tokenMatches(token: String, rule: CompiledMapRule) -> Bool {
        stringMatches(text: token, rule: rule)
    }

    private func stringMatches(text: String, rule: CompiledMapRule) -> Bool {
        let haystack = text.lowercased()
        let values = rule.match.values?.map { $0.lowercased() }
        let value = rule.match.value?.lowercased()

        switch rule.match.type {
        case .equals:
            guard let value else { return false }
            return haystack == value
        case .equalsAny:
            guard let values else { return false }
            return values.contains(haystack)
        case .contains:
            guard let value else { return false }
            return haystack.contains(value)
        case .containsAny:
            guard let values else { return false }
            return values.contains(where: { haystack.contains($0) })
        case .equalsOrContainsAny:
            guard let values else { return false }
            return values.contains(haystack) || values.contains(where: { haystack.contains($0) })
        case .regex:
            guard let regex = rule.regex else { return false }
            return regexMatch(regex: regex, text: text)
        }
    }

    private func regexMatch(regex: NSRegularExpression, text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private func firstRegexMatch(in tokens: [String], regex: NSRegularExpression?) -> String? {
        guard let regex else { return nil }
        for token in tokens {
            if regexMatch(regex: regex, text: token) {
                return token
            }
        }
        return nil
    }

    static func fallback() -> FilenameRuleSet {
        FilenameRuleSet(
            version: 1,
            tokenization: Tokenization(separators: "_- ()", caseFold: "preserve"),
            sources: [.file, .parent, .grandparent],
            sampleId: SampleIdRules(patterns: []),
            batch: BatchRules(preferSampleId: true, fallbackPatterns: []),
            measurementNameRules: [],
            measurementTagRules: [],
            substrateTagRules: [],
            channel: ChannelRules(aliases: [:]),
            deviceRules: [],
            rotationHintRules: [],
            conditions: ConditionRules(temperaturePattern: "", currentPattern: "", fieldPattern: "")
        )
    }
}
