import Foundation

struct FilenameRuleSet: Decodable {
    struct ExtraConditionEvaluation {
        var values: [String: String]
        var warnings: [String]
    }

    enum ConditionDefinitionKind: String, Decodable {
        case unitSuffix = "unit_suffix"
        case tokenMap = "token_map"
    }

    struct ConditionDefinition: Decodable {
        var id: String
        var label: String?
        var kind: ConditionDefinitionKind
        var binding: String
    }

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
        var extraConditions: [String: String]
        var tokenMapRules: [String: [MapRule]]
        var displayLabels: [String: String]

        init(
            temperaturePattern: String,
            currentPattern: String,
            fieldPattern: String,
            extraConditions: [String: String] = [:],
            tokenMapRules: [String: [MapRule]] = [:],
            displayLabels: [String: String] = [:]
        ) {
            self.temperaturePattern = temperaturePattern
            self.currentPattern = currentPattern
            self.fieldPattern = fieldPattern
            self.extraConditions = extraConditions
            self.tokenMapRules = tokenMapRules
            self.displayLabels = displayLabels
        }

        private enum CodingKeys: String, CodingKey {
            case temperaturePattern
            case currentPattern
            case fieldPattern
            case extraConditions
            case tokenMapRules
            case displayLabels
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            temperaturePattern = try container.decode(String.self, forKey: .temperaturePattern)
            currentPattern = try container.decode(String.self, forKey: .currentPattern)
            fieldPattern = try container.decode(String.self, forKey: .fieldPattern)
            extraConditions = try container.decodeIfPresent([String: String].self, forKey: .extraConditions) ?? [:]
            tokenMapRules = try container.decodeIfPresent([String: [MapRule]].self, forKey: .tokenMapRules) ?? [:]
            displayLabels = try container.decodeIfPresent([String: String].self, forKey: .displayLabels) ?? [:]
        }

        func patternMap() -> [String: String] {
            var patterns: [String: String] = [
                ConditionFieldCatalog.temperatureID: temperaturePattern,
                ConditionFieldCatalog.currentID: currentPattern,
                ConditionFieldCatalog.fieldID: fieldPattern
            ]
            for (key, value) in extraConditions {
                patterns[key] = value
            }
            return patterns
        }
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
        var conditionDefinitions: [ConditionDefinition]?
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
        var measurementNameRules: [CompiledMapRule] = []
        var measurementTagRules: [CompiledMapRule] = []
        var substrateTagRules: [CompiledMapRule] = []
        var rotationHintRules: [CompiledMapRule] = []
        var channelAliases: [String: String] = [:]
        var conditionUnitSuffixRegexes: [String: NSRegularExpression] = [:]
        var conditionTokenMapRules: [String: [CompiledMapRule]] = [:]
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
    var conditionDefinitions: [ConditionDefinition]
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
        case conditionDefinitions
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
        conditionDefinitions: [ConditionDefinition] = [],
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
        self.conditionDefinitions = conditionDefinitions
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
            conditionDefinitions = inbox.conditionDefinitions ?? []
        } else {
            sources = try container.decode([Source].self, forKey: .sources)
            batch = try container.decode(BatchRules.self, forKey: .batch)
            measurementNameRules = try container.decode([MapRule].self, forKey: .measurementNameRules)
            measurementTagRules = try container.decode([MapRule].self, forKey: .measurementTagRules)
            channel = try container.decode(ChannelRules.self, forKey: .channel)
            deviceRules = try container.decode([MapRule].self, forKey: .deviceRules)
            rotationHintRules = try container.decode([MapRule].self, forKey: .rotationHintRules)
            conditions = try container.decode(ConditionRules.self, forKey: .conditions)
            conditionDefinitions = try container.decodeIfPresent([ConditionDefinition].self, forKey: .conditionDefinitions) ?? []
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

        compiled.measurementNameRules = compileMapRules(measurementNameRules, warnings: &warnings, label: "measurementNameRules")
        compiled.measurementTagRules = compileMapRules(measurementTagRules, warnings: &warnings, label: "measurementTagRules")
        compiled.substrateTagRules = compileMapRules(substrateTagRules, warnings: &warnings, label: "substrateTagRules")
        compiled.rotationHintRules = compileMapRules(rotationHintRules, warnings: &warnings, label: "rotationHintRules")
        compileConditionDefinitions(warnings: &warnings)

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
        firstMatchValue(
            from: compiled.conditionTokenMapRules[ConditionFieldCatalog.deviceID] ?? [],
            tokens: tokens,
            joined: nil
        )
    }

    func rotationHint(from tokens: [String]) -> String? {
        firstMatchValue(from: compiled.rotationHintRules, tokens: tokens, joined: nil)
    }

    func temperature(from tokens: [String]) -> String? {
        firstRegexMatch(
            in: tokens,
            regex: compiled.conditionUnitSuffixRegexes[ConditionFieldCatalog.temperatureID]
        )
    }

    func current(from tokens: [String]) -> String? {
        firstRegexMatch(
            in: tokens,
            regex: compiled.conditionUnitSuffixRegexes[ConditionFieldCatalog.currentID]
        )
    }

    func field(from tokens: [String]) -> String? {
        firstRegexMatch(
            in: tokens,
            regex: compiled.conditionUnitSuffixRegexes[ConditionFieldCatalog.fieldID]
        )
    }

    func extraConditionValues(from tokens: [String]) -> [String: String] {
        extraConditionEvaluation(from: tokens).values
    }

    func extraConditionEvaluation(from tokens: [String]) -> ExtraConditionEvaluation {
        var reservedRuleIDs = ConditionFieldCatalog.builtInConditionIDs
        reservedRuleIDs.insert(ConditionFieldCatalog.deviceID)
        let allRuleIDs = Set(compiled.conditionUnitSuffixRegexes.keys)
            .union(compiled.conditionTokenMapRules.keys)
            .subtracting(reservedRuleIDs)
            .sorted()
        var values: [String: String] = [:]
        var warnings: [String] = []

        for ruleID in allRuleIDs {
            let regexMatch = compiled.conditionUnitSuffixRegexes[ruleID]
                .flatMap { firstRegexMatch(in: tokens, regex: $0) }
            let tokenMapMatch = compiled.conditionTokenMapRules[ruleID]
                .flatMap { firstMatchValue(from: $0, tokens: tokens, joined: nil) }

            if let tokenMapMatch {
                values[ruleID] = tokenMapMatch
                if regexMatch != nil {
                    warnings.append("Condition '\(ruleID)' matched both token-map and unit-suffix; token-map result applied.")
                }
                continue
            }

            if let regexMatch {
                values[ruleID] = regexMatch
            }
        }

        return ExtraConditionEvaluation(values: values, warnings: warnings)
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

    private mutating func compileConditionDefinitions(warnings: inout [String]) {
        compiled.conditionUnitSuffixRegexes = [:]
        compiled.conditionTokenMapRules = [:]

        for definition in conditionDefinitions {
            let id = definition.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            let binding = definition.binding.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !binding.isEmpty else { continue }

            switch definition.kind {
            case .unitSuffix:
                guard let pattern = unitSuffixPattern(for: binding), !pattern.isEmpty else { continue }
                if let compiledRegex = compileRegex(pattern, warnings: &warnings, label: binding) {
                    compiled.conditionUnitSuffixRegexes[id] = compiledRegex
                }
            case .tokenMap:
                guard let rawRules = tokenMapRules(for: binding) else { continue }
                compiled.conditionTokenMapRules[id] = compileMapRules(rawRules, warnings: &warnings, label: binding)
            }
        }
    }

    private func unitSuffixPattern(for binding: String) -> String? {
        guard binding.hasPrefix("conditions.extraConditions.") else {
            return nil
        }
        let key = String(binding.dropFirst("conditions.extraConditions.".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return conditions.extraConditions[key]
    }

    private func tokenMapRules(for binding: String) -> [MapRule]? {
        guard binding.hasPrefix("conditions.tokenMapRules.") else {
            return nil
        }
        let key = String(binding.dropFirst("conditions.tokenMapRules.".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return conditions.tokenMapRules[key] ?? []
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
            switch rule.match.scope {
            case .tokens:
                for token in tokens where tokenMatches(token: token, rule: rule) {
                    if rule.value == "$MATCH" {
                        return token
                    }
                    return rule.value
                }
            case .joined:
                guard let joined else { continue }
                if stringMatches(text: joined, rule: rule) {
                    if rule.value == "$MATCH" {
                        return joined
                    }
                    return rule.value
                }
            }
        }
        return nil
    }

    private func collectMatchValues(from rules: [CompiledMapRule], tokens: [String], joined: String?) -> [String] {
        var collected: [String] = []
        for rule in rules {
            if matches(rule: rule, tokens: tokens, joined: joined) {
                // Tag collection intentionally appends literal rule values only.
                // "$MATCH" token substitution is supported in firstMatchValue paths,
                // but is not expanded for multi-value tag collection.
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
            conditions: ConditionRules(
                temperaturePattern: "",
                currentPattern: "",
                fieldPattern: "",
                extraConditions: [
                    ConditionFieldCatalog.temperatureID: "",
                    ConditionFieldCatalog.currentID: "",
                    ConditionFieldCatalog.fieldID: ""
                ],
                tokenMapRules: [
                    ConditionFieldCatalog.deviceID: []
                ],
                displayLabels: ConditionFieldCatalog.builtInConditionLabels
            ),
            conditionDefinitions: [
                ConditionDefinition(
                    id: ConditionFieldCatalog.temperatureID,
                    label: ConditionFieldCatalog.builtInConditionLabels[ConditionFieldCatalog.temperatureID],
                    kind: .unitSuffix,
                    binding: "conditions.extraConditions.\(ConditionFieldCatalog.temperatureID)"
                ),
                ConditionDefinition(
                    id: ConditionFieldCatalog.currentID,
                    label: ConditionFieldCatalog.builtInConditionLabels[ConditionFieldCatalog.currentID],
                    kind: .unitSuffix,
                    binding: "conditions.extraConditions.\(ConditionFieldCatalog.currentID)"
                ),
                ConditionDefinition(
                    id: ConditionFieldCatalog.fieldID,
                    label: ConditionFieldCatalog.builtInConditionLabels[ConditionFieldCatalog.fieldID],
                    kind: .unitSuffix,
                    binding: "conditions.extraConditions.\(ConditionFieldCatalog.fieldID)"
                ),
                ConditionDefinition(
                    id: ConditionFieldCatalog.deviceID,
                    label: ConditionFieldCatalog.builtInConditionLabels[ConditionFieldCatalog.deviceID],
                    kind: .tokenMap,
                    binding: "conditions.tokenMapRules.\(ConditionFieldCatalog.deviceID)"
                )
            ],
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
