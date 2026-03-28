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

    struct RegistryRules: Decodable {
        var sampleHeaderAliases: [String]
        var excludedSheetNames: [String]
        var sampleCellSeparators: String
        var batchHeaderAliases: [String]
        var substrateHeaderAliases: [String]
        var numericKeyAliases: [String: [String]]
        var substrateMaterialTokens: [String]
        var substrateProcessingKeywords: [String: [String]]
        var metadataLookupAliases: [String: [String]]
    }

    struct ImportRules: Decodable {
        var supportedFileExtensions: [String]
        var ignoredFileExtensions: [String]
    }

    struct SharedRules: Decodable {
        var tokenization: Tokenization
        var sampleId: SampleIdRules
        var substrateTagRules: [MapRule]
        var substrate: SharedSubstrateRules?
    }

    struct SharedSubstrateRules: Decodable {
        var tokenSeparators: String
        var originStandaloneTokens: [String]
        var originContainsTokens: [String]
        var treatmentKeywords: [String: [String]]
        var materialTokens: [String]
        var materialAliases: [String: String]?
        var materialDisplayNames: [String: String]?
        var orientationTokens: [String]?
        var orientationAliases: [String: String]?
        var orientationPattern: String
    }

    struct InboxRules: Decodable {
        var sources: [Source]
        var batch: BatchRules
        var measurementNameRules: [MapRule]
        var measurementTagRules: [MapRule]
        var channel: ChannelRules
        var deviceRules: [MapRule]
        var rotationHintRules: [MapRule]
        var conditions: ConditionRules
    }

    struct LibraryRules: Decodable {
        var registry: RegistryRules?
        var importRules: ImportRules?
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
    var registry: RegistryRules?
    var importRules: ImportRules?
    var sharedSubstrate: SharedSubstrateRules?

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
        case registry
        case importRules
        case shared
        case inbox
        case library
    }

    init(
        version: Int,
        tokenization: Tokenization,
        sources: [Source],
        sampleId: SampleIdRules,
        batch: BatchRules,
        measurementNameRules: [MapRule],
        measurementTagRules: [MapRule],
        substrateTagRules: [MapRule],
        channel: ChannelRules,
        deviceRules: [MapRule],
        rotationHintRules: [MapRule],
        conditions: ConditionRules,
        registry: RegistryRules?,
        importRules: ImportRules?,
        sharedSubstrate: SharedSubstrateRules?
    ) {
        self.version = version
        self.tokenization = tokenization
        self.sources = sources
        self.sampleId = sampleId
        self.batch = batch
        self.measurementNameRules = measurementNameRules
        self.measurementTagRules = measurementTagRules
        self.substrateTagRules = substrateTagRules
        self.channel = channel
        self.deviceRules = deviceRules
        self.rotationHintRules = rotationHintRules
        self.conditions = conditions
        self.registry = registry
        self.importRules = importRules
        self.sharedSubstrate = sharedSubstrate
        compiled = CompiledRules()
        loadWarnings = []
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)

        if let shared = try container.decodeIfPresent(SharedRules.self, forKey: .shared) {
            tokenization = shared.tokenization
            sampleId = shared.sampleId
            substrateTagRules = shared.substrateTagRules
            sharedSubstrate = shared.substrate
        } else {
            tokenization = try container.decode(Tokenization.self, forKey: .tokenization)
            sampleId = try container.decode(SampleIdRules.self, forKey: .sampleId)
            substrateTagRules = try container.decode([MapRule].self, forKey: .substrateTagRules)
            sharedSubstrate = nil
        }

        if let inbox = try container.decodeIfPresent(InboxRules.self, forKey: .inbox) {
            sources = inbox.sources
            batch = inbox.batch
            measurementNameRules = inbox.measurementNameRules
            measurementTagRules = inbox.measurementTagRules
            channel = inbox.channel
            deviceRules = inbox.deviceRules
            rotationHintRules = inbox.rotationHintRules
            conditions = inbox.conditions
        } else {
            sources = try container.decode([Source].self, forKey: .sources)
            batch = try container.decode(BatchRules.self, forKey: .batch)
            measurementNameRules = try container.decode([MapRule].self, forKey: .measurementNameRules)
            measurementTagRules = try container.decode([MapRule].self, forKey: .measurementTagRules)
            channel = try container.decode(ChannelRules.self, forKey: .channel)
            deviceRules = try container.decode([MapRule].self, forKey: .deviceRules)
            rotationHintRules = try container.decode([MapRule].self, forKey: .rotationHintRules)
            conditions = try container.decode(ConditionRules.self, forKey: .conditions)
        }

        if let library = try container.decodeIfPresent(LibraryRules.self, forKey: .library) {
            registry = library.registry
            importRules = library.importRules
        } else {
            registry = try container.decodeIfPresent(RegistryRules.self, forKey: .registry)
            importRules = try container.decodeIfPresent(ImportRules.self, forKey: .importRules)
        }

        compiled = CompiledRules()
        loadWarnings = []
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
            conditions: ConditionRules(temperaturePattern: "", currentPattern: "", fieldPattern: ""),
            registry: RegistryRules(
                sampleHeaderAliases: ["sampleid", "sample", "编号", "样品编号"],
                excludedSheetNames: ["实验大纲"],
                sampleCellSeparators: "/／,，;；|",
                batchHeaderAliases: ["编号", "Batch", "BatchID", "Batch Id"],
                substrateHeaderAliases: ["substrate", "Substrate", "衬底"],
                numericKeyAliases: [
                    "厚度": ["预打", "生长次数"],
                    "温度": ["温度", "temperature"],
                    "氧压": ["氧压", "pressure"],
                    "能量": ["能量", "energy"],
                    "电压": ["电压", "kv"],
                    "磁场": ["磁场", "field"],
                    "电阻": ["电阻", "current"]
                ],
                substrateMaterialTokens: ["STO", "NGO", "MAO", "MGO", "AL2O3", "SI", "POLY-SIO2 ON SI", "POLY-SIO2"],
                substrateProcessingKeywords: [
                    "HF": ["HF"],
                    "b": ["B", "BAKE", "BAKED"],
                    "o": ["ORIGINAL", "ORIGIN", " O "]
                ],
                metadataLookupAliases: [
                    "batch": ["Batch", "BatchID", "Batch Name", "编号"],
                    "sample": ["Sample", "SampleID", "Sample Name", "样品"],
                    "measurement": ["Measurement", "MeasurementName", "Measurement Name"],
                    "device": ["Device", "DeviceName", "Device Name"],
                    "temperature": ["Temperature", "Temp", "T"],
                    "project": ["Project", "ProjectName", "Project Name"]
                ]
            ),
            importRules: ImportRules(
                supportedFileExtensions: ["csv", "txt", "dat", "lvm"],
                ignoredFileExtensions: ["gph"]
            ),
            sharedSubstrate: SharedSubstrateRules(
                tokenSeparators: "_- ()",
                originStandaloneTokens: ["o"],
                originContainsTokens: ["origin", "original"],
                treatmentKeywords: [
                    "HF": ["hf"],
                    "b": ["b", "bake", "baked"],
                    "o": ["o", "origin", "original"]
                ],
                materialTokens: ["STO", "NGO", "MAO", "MGO", "AL2O3", "SI", "POLY-SIO2 ON SI", "POLY-SIO2"],
                materialAliases: [
                    "ONSI": "SI"
                ],
                materialDisplayNames: [
                    "POLY-SIO2 ON SI": "poly-SiO2 on Si",
                    "POLY-SIO2": "poly-SiO2 on Si",
                    "MGO": "MgO",
                    "AL2O3": "Al2O3",
                    "SI": "Si"
                ],
                orientationTokens: ["111", "110", "001", "100", "0001"],
                orientationAliases: [
                    "100": "001"
                ],
                orientationPattern: "\\d{3}"
            )
        )
    }
}
