import Foundation

struct FilenameRuleSet: Decodable {
    struct ExtraConditionEvaluation {
        var values: [String: String]
        var warnings: [String]
    }

    struct SourcedConditionValue {
        var value: String
        var ruleRef: String
    }

    struct ExtraConditionEvaluationWithSources {
        var sourcedValues: [String: SourcedConditionValue]
        var warnings: [String]
        var values: [String: String] { sourcedValues.mapValues(\.value) }
    }

    // MARK: - Operation enum (5-op closed set)

    enum Operation: String, Codable, Hashable, Sendable, CaseIterable {
        case equals
        case contains
        case startsWith = "starts-with"
        case unitSuffix = "unit-suffix"
        case regex
    }

    // MARK: - Flat MatchSpec (type + single value)

    struct MatchSpec: Codable, Hashable, Sendable {
        var type: Operation
        var value: String
    }

    // MARK: - ConditionStandardization

    struct ConditionStandardization: Codable, Hashable, Sendable {
        var standardUnit: String?
        var precision: String?

        var parsedPrecision: Decimal? {
            guard let p = precision,
                  let v = Decimal(string: p.trimmingCharacters(in: .whitespacesAndNewlines),
                                  locale: Locale(identifier: "en_US_POSIX")),
                  v > 0 else { return nil }
            return v
        }
    }

    // MARK: - MapRule (match + output value + optional transform)

    struct MapRule: Codable, Hashable, Sendable {
        var match: MatchSpec
        var value: String
        var transform: String?

        private enum CodingKeys: String, CodingKey { case match, value, transform }

        init(match: MatchSpec, value: String, transform: String? = nil) {
            self.match = match
            self.value = value
            self.transform = transform
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            match = try c.decode(MatchSpec.self, forKey: .match)
            value = try c.decode(String.self, forKey: .value)
            transform = try c.decodeIfPresent(String.self, forKey: .transform)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(match, forKey: .match)
            try c.encode(value, forKey: .value)
            try c.encodeIfPresent(transform, forKey: .transform)
        }
    }

    struct ConditionDefinition: Decodable {
        var id: String
        var displayName: String?
        var standardization: ConditionStandardization?
        var matches: [MapRule]

        private enum CodingKeys: String, CodingKey {
            case id, displayName, label, standardization, matches
        }

        init(id: String, displayName: String?, standardization: ConditionStandardization? = nil, matches: [MapRule]) {
            self.id = id
            self.displayName = displayName
            self.standardization = standardization
            self.matches = matches
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
                ?? c.decodeIfPresent(String.self, forKey: .label)
            standardization = try c.decodeIfPresent(ConditionStandardization.self, forKey: .standardization)
            matches = try c.decodeIfPresent([MapRule].self, forKey: .matches) ?? []
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

    // MARK: - Compiled rule types

    struct CompiledMatchSpec {
        var spec: MatchSpec
        var generatedRegex: NSRegularExpression?
    }

    struct CompiledMapRule {
        var match: CompiledMatchSpec
        var value: String
        var transform: String?
    }

    struct CompiledConditionDefinition {
        var standardization: ConditionStandardization?
        var rules: [CompiledMapRule]
    }

    struct CompiledRules {
        var sampleIdSpecs: [CompiledMatchSpec] = []
        var measurementNameRules: [CompiledMapRule] = []
        var measurementTagRules: [CompiledMapRule] = []
        var channelAliases: [String: String] = [:]
        var conditionRules: [String: CompiledConditionDefinition] = [:]
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

        compiled.sampleIdSpecs = sampleId.matches.compactMap { spec -> CompiledMatchSpec? in
            guard spec.type == .startsWith else {
                warnings.append("sampleId: op '\(spec.type.rawValue)' is not valid for batch ID; rule skipped")
                return nil
            }
            let c = compileMatchSpec(spec, warnings: &warnings, label: "sampleId")
            return c.generatedRegex != nil ? c : nil
        }
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

    func sampleIDsWithSources(from tokens: [String]) -> [(value: String, ruleRef: String)] {
        var seen: Set<String> = []
        return tokens.compactMap { token in
            guard let result = normalizeSampleIDTokenWithSource(token) else {
                return nil
            }
            guard seen.insert(result.value).inserted else {
                return nil
            }
            return result
        }
    }

    func measurementName(from tokens: [String]) -> String? {
        firstMatchWithIndex(from: compiled.measurementNameRules, tokens: tokens)?.value
    }

    func measurementNameWithSource(from tokens: [String]) -> (value: String, ruleRef: String)? {
        guard let result = firstMatchWithIndex(from: compiled.measurementNameRules, tokens: tokens) else { return nil }
        return (result.value, RuleRef.measurementNameRule(index: result.ruleIndex))
    }

    func measurementTags(from tokens: [String]) -> [String] {
        collectMatchedRules(from: compiled.measurementTagRules, tokens: tokens).map(\.value)
    }

    func measurementTagsWithSources(from tokens: [String]) -> [(value: String, ruleRef: String)] {
        collectMatchedRules(from: compiled.measurementTagRules, tokens: tokens).map {
            ($0.value, RuleRef.measurementTagRule(index: $0.ruleIndex))
        }
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

    func substrateTagsWithSources(from tokens: [String]) -> [(value: String, ruleRef: String)] {
        let normalizedTokens = tokens.map(Self.normalizeForSubstrate)
        var result: [(value: String, ruleRef: String)] = []
        for (idx, entry) in compiled.substrateMaterialEntries.enumerated() {
            if anyTokenHits(entry, normalizedTokens: normalizedTokens) {
                result.append((entry.displayName, RuleRef.substrateMaterial(index: idx)))
            }
        }
        for (idx, entry) in compiled.substrateTreatmentEntries.enumerated() {
            if anyTokenHits(entry, normalizedTokens: normalizedTokens) {
                result.append((entry.displayName, RuleRef.substrateTreatment(index: idx)))
            }
        }
        for (idx, entry) in compiled.substrateOrientationEntries.enumerated() {
            if anyTokenHits(entry, normalizedTokens: normalizedTokens) {
                result.append((entry.displayName, RuleRef.substrateOrientation(index: idx)))
            }
        }
        return result
    }

    func deviceName(from tokens: [String]) -> String? {
        conditionValue(for: ConditionFieldCatalog.deviceID, from: tokens)
    }

    func temperature(from tokens: [String]) -> String? {
        conditionValue(for: ConditionFieldCatalog.temperatureID, from: tokens)
    }

    func current(from tokens: [String]) -> String? {
        conditionValue(for: ConditionFieldCatalog.currentID, from: tokens)
    }

    func field(from tokens: [String]) -> String? {
        conditionValue(for: ConditionFieldCatalog.fieldID, from: tokens)
    }

    func extraConditionValues(from tokens: [String]) -> [String: String] {
        extraConditionEvaluation(from: tokens).values
    }

    func conditionEvaluation(from tokens: [String]) -> ExtraConditionEvaluation {
        let sourced = conditionEvaluationWithSources(from: tokens)
        return ExtraConditionEvaluation(values: sourced.values, warnings: sourced.warnings)
    }

    func conditionEvaluationWithSources(from tokens: [String]) -> ExtraConditionEvaluationWithSources {
        let allRuleIDs = compiled.conditionRules.keys.sorted()
        var sourcedValues: [String: SourcedConditionValue] = [:]
        var warnings: [String] = []

        for ruleID in allRuleIDs {
            guard let condDef = compiled.conditionRules[ruleID] else { continue }
            for (ruleIndex, rule) in condDef.rules.enumerated() {
                guard let matched = tokens.first(where: { tokenMatches(text: $0, compiled: rule.match) }) else { continue }
                let value: String
                let op = rule.match.spec.type
                if rule.value != "$MATCH" {
                    value = rule.value
                } else if op == .regex {
                    value = applyStandardization(
                        matched: matched,
                        transform: rule.transform,
                        standardization: condDef.standardization,
                        ruleID: ruleID,
                        ruleIndex: ruleIndex,
                        warnings: &warnings
                    )
                } else {
                    value = matched
                }
                let ref = RuleRef.conditionRule(id: ruleID, ruleIndex: ruleIndex)
                sourcedValues[ruleID] = SourcedConditionValue(value: value, ruleRef: ref)
                break
            }
        }

        return ExtraConditionEvaluationWithSources(sourcedValues: sourcedValues, warnings: warnings)
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

    func normalizeChannelWithSource(_ token: String) -> (value: String, ruleRef: String)? {
        let key = token.lowercased()
        guard let value = compiled.channelAliases[key] else {
            return nil
        }
        return (value, RuleRef.channelAlias(normalizedKey: key))
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

    private func compileMatchSpec(_ spec: MatchSpec, warnings: inout [String], label: String) -> CompiledMatchSpec {
        var result = CompiledMatchSpec(spec: spec, generatedRegex: nil)
        let trimmed = spec.value.trimmingCharacters(in: .whitespacesAndNewlines)

        switch spec.type {
        case .equals, .contains:
            if trimmed.isEmpty { warnings.append("\(label): empty value; rule never matches") }

        case .startsWith:
            guard !trimmed.isEmpty,
                  trimmed.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
                warnings.append("\(label): invalid starts-with value '\(spec.value)'; rule never matches")
                return result
            }
            let pattern = "^\(NSRegularExpression.escapedPattern(for: trimmed))\\d+$"
            result.generatedRegex = compileRegex(pattern, warnings: &warnings, label: label)

        case .unitSuffix:
            guard !trimmed.isEmpty else {
                warnings.append("\(label): empty unit-suffix value; rule never matches")
                return result
            }
            let pattern = "^-?\\d+(?:\\.\\d+)?(?:\(NSRegularExpression.escapedPattern(for: trimmed)))$"
            result.generatedRegex = compileRegex(pattern, warnings: &warnings, label: label)

        case .regex:
            guard !trimmed.isEmpty else {
                warnings.append("\(label): empty regex pattern; rule never matches")
                return result
            }
            // Regex semantics: pattern represents the unit suffix. Token must be
            // <signed number><optional whitespace><pattern>, anchored end-to-end.
            // Pattern itself is a regex sub-expression (alternation/character class allowed),
            // wrapped in a non-capturing group so anchoring isn't broken.
            let pattern = "^-?\\d+(?:\\.\\d+)?\\s*(?:\(trimmed))$"
            result.generatedRegex = compileRegex(pattern, warnings: &warnings, label: label)
        }

        return result
    }

    private func compileRegex(_ pattern: String, warnings: inout [String], label: String) -> NSRegularExpression? {
        guard !pattern.isEmpty else { return nil }
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            warnings.append("Failed to compile regex for \(label): \(pattern)")
            return nil
        }
    }

    private func compileMapRules(_ rules: [MapRule], warnings: inout [String], label: String) -> [CompiledMapRule] {
        rules.map { rule in
            CompiledMapRule(
                match: compileMatchSpec(rule.match, warnings: &warnings, label: label),
                value: rule.value,
                transform: rule.transform
            )
        }
    }

    private mutating func compileConditionDefinitions(warnings: inout [String]) {
        compiled.conditionRules = [:]
        for definition in conditionDefinitions {
            let id = definition.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            compiled.conditionRules[id] = CompiledConditionDefinition(
                standardization: definition.standardization,
                rules: compileMapRules(definition.matches, warnings: &warnings, label: id)
            )
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
        for spec in compiled.sampleIdSpecs {
            if tokenMatches(text: uppercased, compiled: spec) {
                return uppercased
            }
        }
        return nil
    }

    private func normalizeSampleIDTokenWithSource(_ token: String) -> (value: String, ruleRef: String)? {
        let uppercased = token.uppercased()
        let usesBatchPrefixes = sampleId.matches.contains { $0.type == .startsWith }
        for (idx, spec) in compiled.sampleIdSpecs.enumerated() {
            if tokenMatches(text: uppercased, compiled: spec) {
                let ref = usesBatchPrefixes
                    ? RuleRef.sampleIdBatchPrefix(index: idx)
                    : RuleRef.sampleIdPattern(index: idx)
                return (uppercased, ref)
            }
        }
        return nil
    }

    private func firstMatchWithIndex(from rules: [CompiledMapRule], tokens: [String]) -> (value: String, ruleIndex: Int)? {
        for (idx, rule) in rules.enumerated() {
            for token in tokens where tokenMatches(token: token, rule: rule) {
                return (rule.value == "$MATCH" ? token : rule.value, idx)
            }
        }
        return nil
    }

    private func collectMatchedRules(from rules: [CompiledMapRule], tokens: [String]) -> [(value: String, ruleIndex: Int)] {
        rules.enumerated().compactMap { (idx, rule) in
            tokens.contains(where: { tokenMatches(token: $0, rule: rule) }) ? (rule.value, idx) : nil
        }
    }

    private func tokenMatches(token: String, rule: CompiledMapRule) -> Bool {
        tokenMatches(text: token, compiled: rule.match)
    }

    private func tokenMatches(text: String, compiled: CompiledMatchSpec) -> Bool {
        let value = compiled.spec.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }

        switch compiled.spec.type {
        case .equals:
            return text.lowercased() == value.lowercased()
        case .contains:
            return text.lowercased().contains(value.lowercased())
        case .startsWith, .unitSuffix, .regex:
            guard let regex = compiled.generatedRegex else { return false }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
    }

    private func conditionValue(for ruleID: String, from tokens: [String]) -> String? {
        conditionEvaluationWithSources(from: tokens).sourcedValues[ruleID]?.value
    }

    private func applyStandardization(
        matched: String,
        transform: String?,
        standardization: ConditionStandardization?,
        ruleID: String,
        ruleIndex: Int,
        warnings: inout [String]
    ) -> String {
        guard let standardization, let standardUnit = standardization.standardUnit else {
            return matched
        }
        let trimmedTransform = transform?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedTransform.isEmpty else {
            return matched
        }
        guard let split = splitNumericUnitToken(matched),
              let numericValue = Double(split.number) else {
            return matched
        }
        let evaluator = ConditionTransformExpressionEvaluator()
        let transformed: Double
        do {
            transformed = try evaluator.evaluate(trimmedTransform, value: numericValue)
        } catch {
            warnings.append("condition '\(ruleID)' rule \(ruleIndex): transform '\(trimmedTransform)' invalid: \(error)")
            return matched
        }
        var finalDecimal = Decimal(transformed)
        if let precision = standardization.parsedPrecision {
            finalDecimal = roundToPrecision(finalDecimal, precision: precision)
        }
        return "\(formatDecimal(finalDecimal))\(standardUnit)"
    }

    private func roundToPrecision(_ value: Decimal, precision: Decimal) -> Decimal {
        var v = value
        var p = precision
        var ratio = Decimal()
        NSDecimalDivide(&ratio, &v, &p, .plain)
        var rounded = Decimal()
        var ratioSource = ratio
        NSDecimalRound(&rounded, &ratioSource, 0, .plain)
        var result = Decimal()
        NSDecimalMultiply(&result, &rounded, &p, .plain)
        return result
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
                    matches: []
                ),
                ConditionDefinition(
                    id: ConditionFieldCatalog.currentID,
                    displayName: ConditionFieldCatalog.builtInConditionLabels[ConditionFieldCatalog.currentID],
                    matches: []
                ),
                ConditionDefinition(
                    id: ConditionFieldCatalog.fieldID,
                    displayName: ConditionFieldCatalog.builtInConditionLabels[ConditionFieldCatalog.fieldID],
                    matches: []
                ),
                ConditionDefinition(
                    id: ConditionFieldCatalog.deviceID,
                    displayName: ConditionFieldCatalog.builtInConditionLabels[ConditionFieldCatalog.deviceID],
                    matches: []
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
