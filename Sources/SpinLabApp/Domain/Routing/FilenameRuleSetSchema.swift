import Foundation

// Tier 1 cross-region schema: pure Codable/Hashable/Sendable value contracts for filename rule sets.
// Evaluator logic and compiled runtime types stay in Import/Rules/FilenameRuleSet.swift.
enum FilenameRuleSetSchema {

    // MARK: - Operation

    enum Operation: String, Codable, Hashable, Sendable, CaseIterable {
        case equals
        case contains
        case startsWith = "starts-with"
        case unitSuffix = "unit-suffix"
        case regex
    }

    // MARK: - MatchSpec

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

    // MARK: - MapRule

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

    // MARK: - ConditionDefinition

    struct ConditionDefinition: Codable, Hashable, Sendable {
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

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encodeIfPresent(displayName, forKey: .displayName)
            try c.encodeIfPresent(standardization, forKey: .standardization)
            try c.encode(matches, forKey: .matches)
        }
    }

    // MARK: - Tokenization

    struct Tokenization: Codable, Hashable, Sendable {
        var separators: String
        var caseFold: String
    }

    // MARK: - Source

    enum Source: String, Codable, Hashable, Sendable {
        case file
        case parent
        case grandparent
    }

    // MARK: - SampleIdRules

    struct SampleIdRules: Codable, Hashable, Sendable {
        var matches: [MatchSpec]

        init(matches: [MatchSpec] = []) {
            self.matches = matches
        }

        private enum CodingKeys: String, CodingKey { case matches }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            matches = try c.decodeIfPresent([MatchSpec].self, forKey: .matches) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(matches, forKey: .matches)
        }
    }

    // MARK: - ChannelRules

    struct ChannelRules: Codable, Hashable, Sendable {
        var aliases: [String: String]
    }

    // MARK: - ConditionRules

    struct ConditionRules: Codable, Hashable, Sendable {
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

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            extraConditions = try c.decodeIfPresent([String: String].self, forKey: .extraConditions) ?? [:]
            tokenMapRules = try c.decodeIfPresent([String: [MapRule]].self, forKey: .tokenMapRules) ?? [:]
            displayLabels = try c.decodeIfPresent([String: String].self, forKey: .displayLabels) ?? [:]
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(extraConditions, forKey: .extraConditions)
            try c.encode(tokenMapRules, forKey: .tokenMapRules)
            try c.encode(displayLabels, forKey: .displayLabels)
        }

        func patternMap() -> [String: String] {
            extraConditions
        }
    }

    // MARK: - RegistryRules

    struct RegistryRules: Codable, Hashable, Sendable {
        var sampleHeaderAliases: [String]
        var excludedSheetNames: [String]
        var sampleCellSeparators: String
        var batchHeaderAliases: [String]
        var substrateHeaderAliases: [String]
        var numericKeyAliases: [String: [String]]
        var metadataLookupAliases: [String: [String]]
    }

    // MARK: - ImportRules

    struct ImportRules: Codable, Hashable, Sendable {
        var supportedFileExtensions: [String]
        var ignoredFileExtensions: [String]
    }

    // MARK: - Substrate schema types

    struct SubstrateEntry: Codable, Hashable, Sendable {
        var displayName: String
        var matches: [MatchSpec]
    }

    struct SubstrateConfig: Codable, Hashable, Sendable {
        var materials: [SubstrateEntry]
        var treatments: [SubstrateEntry]
        var orientations: [SubstrateEntry]
    }
}
