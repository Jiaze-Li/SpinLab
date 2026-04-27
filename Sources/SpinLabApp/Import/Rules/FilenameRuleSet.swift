import Foundation

struct FilenameRuleSet: Decodable {
    struct ExtraConditionEvaluation {
        var values: [String: String]
        var warnings: [String]
    }

    private enum UnitValueNormalizationMode {
        case trimNoise
        case halfStep
    }

    // MARK: - Operation enum (4-op closed set)

    enum Operation: String, Codable, Hashable, Sendable, CaseIterable {
        case equals
        case contains
        case startsWith = "starts-with"
        case unitSuffix = "unit-suffix"
    }

    // MARK: - Flat MatchSpec (type + single value)

    struct MatchSpec: Codable, Hashable, Sendable {
        var type: Operation
        var value: String
    }

    // MARK: - MapRule (match + output value)

    struct MapRule: Codable, Hashable, Sendable {
        var match: MatchSpec
        var value: String
    }

    // MARK: - ConditionMatches (kind-discriminated)

    enum ConditionMatches: Sendable {
        case unitSuffix([MatchSpec])
        case tokenMap([MapRule])
    }

    enum ConditionDefinitionKind: String, Decodable {
        case unitSuffix = "unit_suffix"
        case tokenMap = "token_map"
    }

    struct ConditionDefinition: Decodable {
        var id: String
        var displayName: String?
        var kind: ConditionDefinitionKind
        var matches: ConditionMatches

        @available(*, deprecated, renamed: "displayName")
        var label: String? { displayName }

        private enum CodingKeys: String, CodingKey {
            case id, kind, displayName, label, matches
        }

        init(id: String, displayName: String?, kind: ConditionDefinitionKind, matches: ConditionMatches) {
            self.id = id
            self.displayName = displayName
            self.kind = kind
            self.matches = matches
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            kind = try c.decode(ConditionDefinitionKind.self, forKey: .kind)
            displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
                ?? c.decodeIfPresent(String.self, forKey: .label)

            switch kind {
            case .unitSuffix:
                let specs = try c.decodeIfPresent([MatchSpec].self, forKey: .matches) ?? []
                matches = .unitSuffix(specs)
            case .tokenMap:
                let rules = try c.decodeIfPresent([MapRule].self, forKey: .matches) ?? []
                matches = .tokenMap(rules)
            }
        }
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
        var matches: [MatchSpec]

        init(matches: [MatchSpec] = []) {
            self.matches = matches
        }

        private enum CodingKeys: String, CodingKey {
            case matches
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            matches = try container.decodeIfPresent([MatchSpec].self, forKey: .matches) ?? []
        }
    }

    struct ChannelRules: Decodable {
        var aliases: [String: String]
    }

    struct ConditionRules: Decodable {
        var extraConditions: [String: String]
        var tokenMapRules: [String: [MapRule]]
        var displayLabels: [String: String]

        init(
            extraConditions: [String: String] = [:],
            tokenMapRules: [String: [MapRule]] = [:],
            displayLabels: [String: String] = [:]
        ) {
            self.extraConditions = extraConditions
            self.tokenMapRules = tokenMapRules
            self.displayLabels = displayLabels
        }

        private enum CodingKeys: String, CodingKey {
            case extraConditions, tokenMapRules, displayLabels
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            extraConditions = try container.decodeIfPresent([String: String].self, forKey: .extraConditions) ?? [:]
            tokenMapRules = try container.decodeIfPresent([String: [MapRule]].self, forKey: .tokenMapRules) ?? [:]
            displayLabels = try container.decodeIfPresent([String: String].self, forKey: .displayLabels) ?? [:]
        }

        func patternMap() -> [String: String] {
            extraConditions
        }
    }

    struct RegistryRules: Decodable {
        var sampleHeaderAliases: [String]
        var excludedSheetNames: [String]
        var sampleCellSeparators: String
        var batchHeaderAliases: [String]
        var substrateHeaderAliases: [String]
        var numericKeyAliases: [String: [String]]
        var metadataLookupAliases: [String: [String]]
    }

    struct ImportRules: Decodable {
        var supportedFileExtensions: [String]
        var ignoredFileExtensions: [String]
    }

    // MARK: - Substrate types (v4+: SubstrateEntry uses shared MatchSpec)

    struct SubstrateEntry: Decodable {
        var displayName: String
        var matches: [MatchSpec]
    }

    struct SubstrateConfig: Decodable {
        var materials: [SubstrateEntry]
        var treatments: [SubstrateEntry]
        var orientations: [SubstrateEntry]
    }

    // MARK: - Compiled substrate entry

    struct CompiledSubstrateEntry {
        var displayName: String
        var equalsKeysNormalized: Set<String>
        var containsNeedlesNormalized: [String]
    }

    // MARK: - Legacy match types (retained for Commit 4 cleanup; not used in production paths)

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

    // MARK: - Compiled rule types

    struct CompiledMapRule {
        var match: MatchSpec
        var value: String
    }

    struct CompiledRules {
        var sampleIdRegexes: [NSRegularExpression] = []
        var measurementNameRules: [CompiledMapRule] = []
        var measurementTagRules: [CompiledMapRule] = []
        var channelAliases: [String: String] = [:]
        var conditionUnitSuffixRegexes: [String: NSRegularExpression] = [:]
        var conditionTokenMapRules: [String: [CompiledMapRule]] = [:]
        var substrateMaterialEntries: [CompiledSubstrateEntry] = []
        var substrateTreatmentEntries: [CompiledSubstrateEntry] = []
        var substrateOrientationEntries: [CompiledSubstrateEntry] = []
        var originTreatmentDisplayNames: Set<String> = []
    }

    var version: Int
    var tokenization: Tokenization
    var sources: [Source]
    var sampleId: SampleIdRules
    var measurementNameRules: [MapRule]
    var measurementTagRules: [MapRule]
    var channel: ChannelRules
    var conditions: ConditionRules
    var conditionDefinitions: [ConditionDefinition]
    var registry: RegistryRules?
    var importRules: ImportRules?
    var substrateConfig: SubstrateConfig?

    var compiled: CompiledRules = CompiledRules()
    var loadWarnings: [String] = []

    private enum CodingKeys: String, CodingKey {
        case version
        case tokenization
        case sources
        case sampleId
        case measurementNameRules
        case measurementTagRules
        case channel
        case conditions
        case conditionDefinitions
        case registry
        case importRules
        case substrateConfig
    }

    init(
        version: Int,
        tokenization: Tokenization,
        sources: [Source],
        sampleId: SampleIdRules,
        measurementNameRules: [MapRule],
        measurementTagRules: [MapRule],
        channel: ChannelRules,
        conditions: ConditionRules,
        conditionDefinitions: [ConditionDefinition] = [],
        registry: RegistryRules?,
        importRules: ImportRules?,
        substrateConfig: SubstrateConfig?
    ) {
        self.version = version
        self.tokenization = tokenization
        self.sources = sources
        self.sampleId = sampleId
        self.measurementNameRules = measurementNameRules
        self.measurementTagRules = measurementTagRules
        self.channel = channel
        self.conditions = conditions
        self.conditionDefinitions = conditionDefinitions
        self.registry = registry
        self.importRules = importRules
        self.substrateConfig = substrateConfig
        compiled = CompiledRules()
        loadWarnings = []
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        tokenization = try container.decode(Tokenization.self, forKey: .tokenization)
        sources = try container.decode([Source].self, forKey: .sources)
        sampleId = try container.decodeIfPresent(SampleIdRules.self, forKey: .sampleId) ?? SampleIdRules()
        measurementNameRules = try container.decodeIfPresent([MapRule].self, forKey: .measurementNameRules) ?? []
        measurementTagRules = try container.decodeIfPresent([MapRule].self, forKey: .measurementTagRules) ?? []
        channel = try container.decode(ChannelRules.self, forKey: .channel)
        conditions = try container.decodeIfPresent(ConditionRules.self, forKey: .conditions) ?? ConditionRules()
        conditionDefinitions = try container.decodeIfPresent([ConditionDefinition].self, forKey: .conditionDefinitions) ?? []
        registry = try container.decodeIfPresent(RegistryRules.self, forKey: .registry)
        importRules = try container.decodeIfPresent(ImportRules.self, forKey: .importRules)
        substrateConfig = try container.decodeIfPresent(SubstrateConfig.self, forKey: .substrateConfig)
        compiled = CompiledRules()
        loadWarnings = []
    }

    mutating func compile() -> [String] {
        var warnings: [String] = []

        compiled.sampleIdRegexes = compileSampleIdRegexes(warnings: &warnings)
        compiled.measurementNameRules = compileMapRules(measurementNameRules, warnings: &warnings, label: "measurementNameRules")
        compiled.measurementTagRules = compileMapRules(measurementTagRules, warnings: &warnings, label: "measurementTagRules")
        compileConditionDefinitions(warnings: &warnings)
        compileSubstrateConfigNeedles()

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

    func measurementName(from tokens: [String], joined: String) -> String? {
        firstMatchValue(from: compiled.measurementNameRules, tokens: tokens)
    }

    func measurementTags(from tokens: [String]) -> [String] {
        collectMatchValues(from: compiled.measurementTagRules, tokens: tokens)
    }

    func substrateTags(from tokens: [String]) -> [String] {
        let normalizedTokens = tokens.map(Self.normalizeForSubstrate)
        var result: [String] = []
        for entry in compiled.substrateMaterialEntries
            + compiled.substrateTreatmentEntries
            + compiled.substrateOrientationEntries
        {
            if anyTokenHits(entry, normalizedTokens: normalizedTokens) {
                result.append(entry.displayName)
            }
        }
        return result
    }

    func deviceName(from tokens: [String]) -> String? {
        firstMatchValue(
            from: compiled.conditionTokenMapRules[ConditionFieldCatalog.deviceID] ?? [],
            tokens: tokens
        )
    }

    func temperature(from tokens: [String]) -> String? {
        firstRegexMatch(
            in: tokens,
            regex: compiled.conditionUnitSuffixRegexes[ConditionFieldCatalog.temperatureID],
            ruleID: ConditionFieldCatalog.temperatureID
        )
    }

    func current(from tokens: [String]) -> String? {
        firstRegexMatch(
            in: tokens,
            regex: compiled.conditionUnitSuffixRegexes[ConditionFieldCatalog.currentID],
            ruleID: ConditionFieldCatalog.currentID
        )
    }

    func field(from tokens: [String]) -> String? {
        firstRegexMatch(
            in: tokens,
            regex: compiled.conditionUnitSuffixRegexes[ConditionFieldCatalog.fieldID],
            ruleID: ConditionFieldCatalog.fieldID
        )
    }

    func extraConditionValues(from tokens: [String]) -> [String: String] {
        extraConditionEvaluation(from: tokens).values
    }

    func conditionEvaluation(from tokens: [String]) -> ExtraConditionEvaluation {
        let allRuleIDs = Set(compiled.conditionUnitSuffixRegexes.keys)
            .union(compiled.conditionTokenMapRules.keys)
            .sorted()
        var values: [String: String] = [:]
        var warnings: [String] = []

        for ruleID in allRuleIDs {
            let regexMatch = compiled.conditionUnitSuffixRegexes[ruleID]
                .flatMap { firstRegexMatch(in: tokens, regex: $0, ruleID: ruleID) }
            let tokenMapMatch = compiled.conditionTokenMapRules[ruleID]
                .flatMap { firstMatchValue(from: $0, tokens: tokens) }

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

    func extraConditionEvaluation(from tokens: [String]) -> ExtraConditionEvaluation {
        let evaluated = conditionEvaluation(from: tokens)
        var filtered = evaluated.values
        filtered.removeValue(forKey: ConditionFieldCatalog.deviceID)
        for id in ConditionFieldCatalog.builtInConditionIDs {
            filtered.removeValue(forKey: id)
        }
        return ExtraConditionEvaluation(values: filtered, warnings: evaluated.warnings)
    }

    func normalizeChannel(_ token: String) -> String? {
        compiled.channelAliases[token.lowercased()]
    }

    // MARK: - Normalization (shared for substrate matching and FileRoutingSemanticRules)

    static func normalizeForSubstrate(_ token: String) -> String {
        token.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")
    }

    // MARK: - Private compile helpers

    private func compileSampleIdRegexes(warnings: inout [String]) -> [NSRegularExpression] {
        sampleId.matches.compactMap { spec in
            guard spec.type == .startsWith else {
                warnings.append("sampleId: op '\(spec.type.rawValue)' is not valid for batch ID; rule skipped")
                return nil
            }
            let trimmed = spec.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
                warnings.append("Invalid starts-with value '\(spec.value)'; skipped")
                return nil
            }
            let pattern = "^\(NSRegularExpression.escapedPattern(for: trimmed))\\d+$"
            return compileRegex(pattern, warnings: &warnings, label: "sampleId")
        }
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
        rules.compactMap { rule in
            let trimmed = rule.match.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                warnings.append("\(label): rule with empty value; rule never matches")
                return nil
            }
            return CompiledMapRule(match: rule.match, value: rule.value)
        }
    }

    private mutating func compileConditionDefinitions(warnings: inout [String]) {
        compiled.conditionUnitSuffixRegexes = [:]
        compiled.conditionTokenMapRules = [:]

        for definition in conditionDefinitions {
            let id = definition.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }

            switch definition.matches {
            case .unitSuffix(let specs):
                let units = specs.compactMap { s -> String? in
                    let v = s.value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return v.isEmpty ? nil : v
                }
                guard !units.isEmpty else { continue }
                let alternation = units
                    .map { NSRegularExpression.escapedPattern(for: $0) }
                    .joined(separator: "|")
                let pattern = "^-?\\d+(?:\\.\\d+)?(?:\(alternation))$"
                if let compiledRegex = compileRegex(pattern, warnings: &warnings, label: id) {
                    compiled.conditionUnitSuffixRegexes[id] = compiledRegex
                }
            case .tokenMap(let rules):
                compiled.conditionTokenMapRules[id] = compileMapRules(rules, warnings: &warnings, label: id)
            }
        }
    }

    private mutating func compileSubstrateConfigNeedles() {
        compiled.substrateMaterialEntries = []
        compiled.substrateTreatmentEntries = []
        compiled.substrateOrientationEntries = []
        compiled.originTreatmentDisplayNames = []

        guard let substrateConfig else { return }

        compiled.substrateMaterialEntries = substrateConfig.materials.map(compileSubstrateEntry)
        compiled.substrateTreatmentEntries = substrateConfig.treatments.map(compileSubstrateEntry)
        compiled.substrateOrientationEntries = substrateConfig.orientations.map(compileSubstrateEntry)

        // Detect origin treatment: displayName or any match value normalizes to "O"
        for entry in substrateConfig.treatments {
            let isOrigin = Self.normalizeForSubstrate(entry.displayName) == "O"
                || entry.matches.contains { Self.normalizeForSubstrate($0.value) == "O" }
            if isOrigin {
                compiled.originTreatmentDisplayNames.insert(entry.displayName)
            }
        }
    }

    private func compileSubstrateEntry(_ entry: SubstrateEntry) -> CompiledSubstrateEntry {
        var equalsKeys: Set<String> = []
        var containsNeedles: [String] = []

        let normalizedDisplayName = Self.normalizeForSubstrate(entry.displayName)
        if !normalizedDisplayName.isEmpty {
            equalsKeys.insert(normalizedDisplayName)
        }

        for match in entry.matches {
            let normalized = Self.normalizeForSubstrate(match.value)
            guard !normalized.isEmpty else { continue }
            switch match.type {
            case .equals:
                equalsKeys.insert(normalized)
            case .contains:
                containsNeedles.append(normalized)
            default:
                break
            }
        }

        return CompiledSubstrateEntry(
            displayName: entry.displayName,
            equalsKeysNormalized: equalsKeys,
            containsNeedlesNormalized: containsNeedles
        )
    }

    private func anyTokenHits(_ entry: CompiledSubstrateEntry, normalizedTokens: [String]) -> Bool {
        for token in normalizedTokens {
            if entry.equalsKeysNormalized.contains(token) { return true }
            if entry.containsNeedlesNormalized.contains(where: { token.contains($0) }) { return true }
        }
        return false
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

    private func firstMatchValue(from rules: [CompiledMapRule], tokens: [String]) -> String? {
        for rule in rules {
            for token in tokens where tokenMatches(token: token, rule: rule) {
                return rule.value == "$MATCH" ? token : rule.value
            }
        }
        return nil
    }

    private func collectMatchValues(from rules: [CompiledMapRule], tokens: [String]) -> [String] {
        var collected: [String] = []
        for rule in rules {
            if tokens.contains(where: { tokenMatches(token: $0, rule: rule) }) {
                collected.append(rule.value)
            }
        }
        return collected
    }

    private func tokenMatches(token: String, rule: CompiledMapRule) -> Bool {
        stringMatches(text: token, rule: rule)
    }

    private func stringMatches(text: String, rule: CompiledMapRule) -> Bool {
        let haystack = text.lowercased()
        let value = rule.match.value.lowercased()
        guard !value.isEmpty else { return false }

        switch rule.match.type {
        case .equals:
            return haystack == value
        case .contains:
            return haystack.contains(value)
        case .startsWith:
            // Compile 2 will add CompiledMatchSpec with regex; naive impl for now
            let rest = haystack.dropFirst(value.count)
            return haystack.hasPrefix(value) && !rest.isEmpty && rest.allSatisfy(\.isNumber)
        case .unitSuffix:
            // Compile 2 will add CompiledMatchSpec with regex; naive impl for now
            guard haystack.hasSuffix(value) else { return false }
            let prefix = haystack.dropLast(value.count)
            guard !prefix.isEmpty else { return false }
            return prefix.allSatisfy { $0.isNumber || $0 == "." || $0 == "-" }
        }
    }

    private func regexMatch(regex: NSRegularExpression, text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private func firstRegexMatch(in tokens: [String], regex: NSRegularExpression?, ruleID: String) -> String? {
        guard let regex else { return nil }
        for token in tokens {
            if regexMatch(regex: regex, text: token) {
                return normalizeUnitSuffixToken(token, ruleID: ruleID)
            }
        }
        return nil
    }

    private func normalizeUnitSuffixToken(_ token: String, ruleID: String) -> String {
        guard let split = splitNumericUnitToken(token) else {
            return token
        }
        guard let numericValue = Decimal(string: split.number, locale: Locale(identifier: "en_US_POSIX")) else {
            return token
        }

        let normalized = normalize(numericValue, mode: normalizationMode(for: ruleID))
        return "\(formatDecimal(normalized))\(split.unit)"
    }

    private func normalizationMode(for ruleID: String) -> UnitValueNormalizationMode {
        switch ruleID {
        case ConditionFieldCatalog.temperatureID, ConditionFieldCatalog.fieldID:
            return .halfStep
        default:
            return .trimNoise
        }
    }

    private func splitNumericUnitToken(_ token: String) -> (number: String, unit: String)? {
        let pattern = #"^(-?\d+(?:\.\d+)?)(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(token.startIndex..<token.endIndex, in: token)
        guard let match = regex.firstMatch(in: token, options: [], range: range),
              match.numberOfRanges == 3,
              let numberRange = Range(match.range(at: 1), in: token),
              let unitRange = Range(match.range(at: 2), in: token) else {
            return nil
        }
        let number = String(token[numberRange])
        let unit = String(token[unitRange])
        guard !number.isEmpty, !unit.isEmpty else {
            return nil
        }
        return (number: number, unit: unit)
    }

    private func normalize(_ value: Decimal, mode: UnitValueNormalizationMode) -> Decimal {
        switch mode {
        case .trimNoise:
            return rounded(value, scale: 6)
        case .halfStep:
            return roundedToHalfStep(value)
        }
    }

    private func rounded(_ value: Decimal, scale: Int) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }

    private func roundedToHalfStep(_ value: Decimal) -> Decimal {
        var source = value
        var two = Decimal(2)
        var scaled = Decimal()
        NSDecimalMultiply(&scaled, &source, &two, .plain)

        var roundedScaled = Decimal()
        var scaledSource = scaled
        NSDecimalRound(&roundedScaled, &scaledSource, 0, .plain)

        var result = Decimal()
        NSDecimalDivide(&result, &roundedScaled, &two, .plain)
        return result
    }

    private func formatDecimal(_ value: Decimal) -> String {
        var mutable = value
        let raw = NSDecimalString(&mutable, Locale(identifier: "en_US_POSIX"))
        guard raw.contains(".") else {
            return raw
        }
        var normalized = raw
        while normalized.hasSuffix("0") {
            normalized.removeLast()
        }
        if normalized.hasSuffix(".") {
            normalized.removeLast()
        }
        return normalized
    }

    static func fallback() -> FilenameRuleSet {
        FilenameRuleSet(
            version: 1,
            tokenization: Tokenization(separators: "_- ()", caseFold: "preserve"),
            sources: [.file, .parent, .grandparent],
            sampleId: SampleIdRules(matches: [
                MatchSpec(type: .startsWith, value: "PN"),
                MatchSpec(type: .startsWith, value: "PT"),
                MatchSpec(type: .startsWith, value: "SL")
            ]),
            measurementNameRules: [],
            measurementTagRules: [],
            channel: ChannelRules(aliases: [:]),
            conditions: ConditionRules(
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
                    displayName: ConditionFieldCatalog.builtInConditionLabels[ConditionFieldCatalog.temperatureID],
                    kind: .unitSuffix,
                    matches: .unitSuffix([])
                ),
                ConditionDefinition(
                    id: ConditionFieldCatalog.currentID,
                    displayName: ConditionFieldCatalog.builtInConditionLabels[ConditionFieldCatalog.currentID],
                    kind: .unitSuffix,
                    matches: .unitSuffix([])
                ),
                ConditionDefinition(
                    id: ConditionFieldCatalog.fieldID,
                    displayName: ConditionFieldCatalog.builtInConditionLabels[ConditionFieldCatalog.fieldID],
                    kind: .unitSuffix,
                    matches: .unitSuffix([])
                ),
                ConditionDefinition(
                    id: ConditionFieldCatalog.deviceID,
                    displayName: ConditionFieldCatalog.builtInConditionLabels[ConditionFieldCatalog.deviceID],
                    kind: .tokenMap,
                    matches: .tokenMap([])
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
            substrateConfig: SubstrateConfig(
                materials: [
                    SubstrateEntry(displayName: "STO", matches: [
                        MatchSpec(type: .contains, value: "STO111"),
                        MatchSpec(type: .contains, value: "STO001")
                    ]),
                    SubstrateEntry(displayName: "NGO", matches: []),
                    SubstrateEntry(displayName: "MAO", matches: []),
                    SubstrateEntry(displayName: "MgO", matches: [
                        MatchSpec(type: .equals, value: "MGO")
                    ]),
                    SubstrateEntry(displayName: "Al2O3", matches: [
                        MatchSpec(type: .equals, value: "AL2O3")
                    ]),
                    SubstrateEntry(displayName: "Si", matches: [
                        MatchSpec(type: .equals, value: "SI"),
                        MatchSpec(type: .equals, value: "ONSI")
                    ]),
                    SubstrateEntry(displayName: "poly-SiO2 on Si", matches: [
                        MatchSpec(type: .equals, value: "POLY-SIO2"),
                        MatchSpec(type: .equals, value: "POLY-SIO2 ON SI")
                    ])
                ],
                treatments: [
                    SubstrateEntry(displayName: "HF", matches: [
                        MatchSpec(type: .contains, value: "hf")
                    ]),
                    SubstrateEntry(displayName: "baked", matches: [
                        MatchSpec(type: .contains, value: "bake")
                    ]),
                    SubstrateEntry(displayName: "b", matches: [
                        MatchSpec(type: .equals, value: "b")
                    ]),
                    SubstrateEntry(displayName: "o", matches: [
                        MatchSpec(type: .contains, value: "origin"),
                        MatchSpec(type: .contains, value: "original")
                    ])
                ],
                orientations: [
                    SubstrateEntry(displayName: "001", matches: [
                        MatchSpec(type: .equals, value: "100"),
                        MatchSpec(type: .contains, value: "STO001")
                    ]),
                    SubstrateEntry(displayName: "111", matches: [
                        MatchSpec(type: .contains, value: "STO111")
                    ]),
                    SubstrateEntry(displayName: "110", matches: []),
                    SubstrateEntry(displayName: "0001", matches: [])
                ]
            )
        )
    }
}
