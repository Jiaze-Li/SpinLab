import Foundation
import Testing
@testable import SpinLabApp
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@MainActor
@Suite("V2.2.5 Rules Config Contract")
struct V225RulesConfigContractTests {
    @Test("rules config decodes and compiles without warnings")
    func rulesConfigDecodesAndCompilesWithoutWarnings() throws {
        var ruleSet = try loadRuleSet()
        let compileWarnings = ruleSet.compile()

        #expect(compileWarnings.isEmpty)
    }

    @Test("rules config contains required aliases and extension lists")
    func rulesConfigContainsRequiredAliasesAndExtensions() throws {
        let ruleSet = try loadRuleSet()
        let registry = try #require(ruleSet.registry)
        let importRules = try #require(ruleSet.importRules)
        let sharedSubstrate = try #require(ruleSet.sharedSubstrate)

        #expect(!registry.sampleHeaderAliases.isEmpty)
        #expect(!registry.batchHeaderAliases.isEmpty)
        #expect(!registry.substrateHeaderAliases.isEmpty)
        #expect(!registry.metadataLookupAliases.isEmpty)
        #expect(!importRules.supportedFileExtensions.isEmpty)
        #expect(!sharedSubstrate.treatmentKeywords.isEmpty)
        #expect(!sharedSubstrate.materialTokens.isEmpty)
        #expect(!(sharedSubstrate.orientationTokens ?? []).isEmpty)
        #expect(!(sharedSubstrate.materialDisplayNames ?? [:]).isEmpty)
    }

    @Test("rules schema version stays on supported runtime version")
    func rulesSchemaVersionMatchesRuntime() throws {
        let ruleSet = try loadRuleSet()
        #expect(ruleSet.version == RuleLoader.currentSchemaVersion)
    }

    @Test("single-letter treatment token follows configured canonical mapping")
    func singleLetterTreatmentTokenFollowsConfiguredCanonicalMapping() throws {
        let rules = try loadRuleSet()
        let substrate = try #require(rules.sharedSubstrate)
        let canonical = substrate.treatmentKeywords.first { _, keywords in
            keywords.contains(where: { $0.lowercased() == "b" })
        }?.key
        let expected = try #require(canonical)

        #expect(SampleSemanticDescriptor.normalizedProcessingTokenForRules("B") == expected)
    }

    @Test("legacy rule set without conditionDefinitions is migrated correctly")
    func legacyRuleSetWithoutConditionDefinitionsIsMigrated() {
        var legacy = FilenameRuleSet.fallback()
        legacy.conditionDefinitions = []
        legacy.conditions.extraConditions = [:]
        legacy.conditions.tokenMapRules = [:]
        legacy.conditions.temperaturePattern = "^-?\\d+(?:\\.\\d+)?(?:K)$"
        legacy.conditions.currentPattern = ""
        legacy.conditions.fieldPattern = ""
        legacy.deviceRules = [
            .init(
                match: .init(scope: .tokens, type: .equals, value: "wafer", values: nil),
                value: "wafer"
            )
        ]

        let warnings = RuleLoader.normalizeConditionDefinitionBindings(
            ruleSet: &legacy,
            sourceLabel: "Test"
        )

        #expect(!warnings.isEmpty)
        #expect(
            legacy.conditionDefinitions.contains {
                $0.id == "temperature"
                    && $0.kind == .unitSuffix
                    && $0.binding == "conditions.extraConditions.temperature"
            }
        )
        #expect(
            legacy.conditionDefinitions.contains {
                $0.id == "device"
                    && $0.kind == .tokenMap
                    && $0.binding == "conditions.tokenMapRules.device"
            }
        )
        #expect(legacy.conditions.extraConditions["temperature"] == "^-?\\d+(?:\\.\\d+)?(?:K)$")
        #expect(legacy.conditions.tokenMapRules["device"]?.count == 1)

        legacy.loadWarnings = legacy.compile()
        let parser = FilenameRuleParser(ruleSet: legacy)
        let parsed = parser.parse(from: URL(fileURLWithPath: "/tmp/PN40/RT_run/RT_25K_wafer.dat"))
        #expect(parsed.temperature == "25K")
        #expect(parsed.deviceName == "wafer")
    }

    @Test("separated override files apply when explicitly enabled in tests")
    func separatedOverridesApplyWhenEnabledInTests() throws {
        let store = ConditionRulesHandbookStore()
        let configDir = store.userFileURL.deletingLastPathComponent()
        let conditionsURL = configDir.appendingPathComponent("conditions_rules.json")
        let substrateURL = configDir.appendingPathComponent("substrate_rules.json")
        let measurementURL = configDir.appendingPathComponent("measurement_tag_rules.json")

        try withFileBackups([conditionsURL, substrateURL, measurementURL]) {
            try withSeparatedOverridesEnabled {
                try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

                let conditionsDoc: [String: Any] = [
                    "version": 1,
                    "extraConditions": [
                        "temperature": NSNull(),
                        "custom_temp": "^CUST\\d+$"
                    ],
                    "tokenMapRules": [
                        "device": [
                            [
                                "matchType": "equals",
                                "pattern": "wafer",
                                "value": "WAFER"
                            ]
                        ]
                    ]
                ]
                try writeJSON(conditionsDoc, to: conditionsURL)

                let substrateDoc: [String: Any] = [
                    "version": 1,
                    "substrateTagRules": [
                        [
                            "match": [
                                "scope": "tokens",
                                "type": "equals",
                                "value": "sto111"
                            ],
                            "value": "STO(111)"
                        ]
                    ]
                ]
                try writeJSON(substrateDoc, to: substrateURL)

                let measurementDoc: [String: Any] = [
                    "version": 1,
                    "rules": [
                        [
                            "match": [
                                "scope": "tokens",
                                "type": "equals",
                                "value": "hall"
                            ],
                            "value": "HALL_TEST"
                        ]
                    ]
                ]
                try writeJSON(measurementDoc, to: measurementURL)

                var loaded = RuleLoader.shared.reloadCached()
                #expect(loaded.ruleSet.conditions.extraConditions["temperature"] == nil)
                #expect(loaded.ruleSet.conditions.extraConditions["custom_temp"] == "^CUST\\d+$")
                #expect(loaded.ruleSet.conditions.tokenMapRules["device"]?.first?.value == "WAFER")
                #expect(loaded.ruleSet.substrateTagRules.first?.value == "STO(111)")
                #expect(loaded.ruleSet.measurementTagRules.first?.value == "HALL_TEST")

                let firstHash = loaded.metadata.contentHash
                let changedMeasurementDoc: [String: Any] = [
                    "version": 1,
                    "rules": [
                        [
                            "match": [
                                "scope": "tokens",
                                "type": "equals",
                                "value": "hall"
                            ],
                            "value": "HALL_TEST_V2"
                        ]
                    ]
                ]
                try writeJSON(changedMeasurementDoc, to: measurementURL)
                loaded = RuleLoader.shared.reloadCached()
                #expect(loaded.metadata.contentHash != firstHash)
                #expect(loaded.ruleSet.measurementTagRules.first?.value == "HALL_TEST_V2")
            }
        }
    }

    @Test("store substrate and measurement separated files round-trip")
    func storeSubstrateAndMeasurementSeparatedFilesRoundTrip() throws {
        let store = ConditionRulesHandbookStore()
        let configDir = store.userFileURL.deletingLastPathComponent()
        let substrateURL = configDir.appendingPathComponent("substrate_rules.json")
        let measurementURL = configDir.appendingPathComponent("measurement_tag_rules.json")

        try withFileBackups([substrateURL, measurementURL]) {
            try withSeparatedOverridesEnabled {
                let substratePatch = SeparatedSubstratePatch(
                    substrateTagRules: [
                        MatchRuleEntry(
                            scope: .tokens,
                            type: .equals,
                            matchValues: ["STO001"],
                            value: "STO(001)"
                        )
                    ],
                    sharedSubstrate: nil
                )
                let substrateApproval = store.issueWriteApproval(
                    for: .substrateRules,
                    actor: "V225RulesConfigContractTests.storeSubstrateAndMeasurementSeparatedFilesRoundTrip"
                )
                try store.saveSubstrateRules(substratePatch, approvalToken: substrateApproval)
                let loadedSubstrate = try #require(store.loadSeparatedSubstrateRules())
                #expect(loadedSubstrate.substrateTagRules?.first?.value == "STO(001)")

                let measurementEntries = [
                    MatchRuleEntry(
                        scope: .tokens,
                        type: .contains,
                        matchValues: ["rotation"],
                        value: "ROT_TEST"
                    )
                ]
                let measurementApproval = store.issueWriteApproval(
                    for: .measurementTagRules,
                    actor: "V225RulesConfigContractTests.storeSubstrateAndMeasurementSeparatedFilesRoundTrip"
                )
                try store.saveMeasurementTagRules(measurementEntries, approvalToken: measurementApproval)
                let loadedMeasurement = try #require(store.loadSeparatedMeasurementTagRules())
                #expect(loadedMeasurement.count == 1)
                #expect(loadedMeasurement.first?.value == "ROT_TEST")
            }
        }
    }

    @Test("custom read-only handbook entries are warnings, not unsupported-id errors")
    func customReadOnlyEntryDoesNotRaiseUnsupportedRuleIDError() {
        let store = ConditionRulesHandbookStore()
        let issues = store.validate([
            RuleEntry(
                ruleID: "legacy_temp",
                label: "Temperature",
                kind: .customReadOnly,
                readOnlyMessage: "Pattern is non-canonical and cannot be edited as unit suffix list: ^\\d+K$"
            )
        ])

        #expect(issues.contains(where: { $0.severity == .error }) == false)
        #expect(issues.contains(where: { $0.severity == .warning }) == true)
    }

    @Test("handbook store and shared config paths resolve identical files")
    func handbookStoreUsesSharedRulesConfigPaths() {
        let fileManager = FileManager.default
        let store = ConditionRulesHandbookStore(fileManager: fileManager)
        let paths = RulesConfigPaths(fileManager: fileManager)

        #expect(store.userFileURL == paths.ruleURL)
    }

    @Test("legacy user handbook file migrates to canonical condition schema")
    func legacyUserRulesMigrateToCanonicalConditionSchema() throws {
        let store = ConditionRulesHandbookStore()
        let userFileURL = store.userFileURL

        try withFileBackups([userFileURL]) {
            let legacyDocument: [String: Any] = [
                "version": 1,
                "conditions": [
                    "temperaturePattern": "^\\d+K$",
                    "currentPattern": "",
                    "fieldPattern": "",
                    "extraConditions": [:],
                    "tokenMapRules": [:]
                ],
                "deviceRules": [
                    [
                        "match": [
                            "scope": "tokens",
                            "type": "equals",
                            "value": "wafer"
                        ],
                        "value": "wafer"
                    ]
                ]
            ]
            try writeJSON(legacyDocument, to: userFileURL)

            let migrated = store.migrateUserRuleFileToCanonicalIfNeeded()
            #expect(migrated)

            let migratedData = try Data(contentsOf: userFileURL)
            let migratedJSON = try #require(
                JSONSerialization.jsonObject(with: migratedData) as? [String: Any]
            )
            let conditionDefinitions = try #require(migratedJSON["conditionDefinitions"] as? [[String: Any]])
            let conditions = try #require(migratedJSON["conditions"] as? [String: Any])
            let extraConditions = try #require(conditions["extraConditions"] as? [String: String])
            let tokenMapRules = try #require(conditions["tokenMapRules"] as? [String: Any])
            let deviceRules = (migratedJSON["deviceRules"] as? [Any]) ?? []

            #expect(conditionDefinitions.contains(where: { ($0["id"] as? String) == "temperature" }))
            #expect(extraConditions["temperature"] == "^\\d+K$")
            #expect(tokenMapRules["device"] != nil)
            #expect(deviceRules.isEmpty)
        }
    }

    private func loadRuleSet() throws -> FilenameRuleSet {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent().deletingLastPathComponent()
        let ruleURL = projectRoot.appendingPathComponent("Sources/SpinLabApp/config/filename_rules.json")
        let data = try Data(contentsOf: ruleURL)
        return try JSONDecoder().decode(FilenameRuleSet.self, from: data)
    }

    private func withSeparatedOverridesEnabled<T>(_ body: () throws -> T) throws -> T {
        let key = "SPINLAB_ENABLE_SEPARATED_OVERRIDES_IN_TESTS"
        let previous = getenv(key).map { String(cString: $0) }
        setenv(key, "1", 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        return try body()
    }

    private func withFileBackups(
        _ urls: [URL],
        body: () throws -> Void
    ) throws {
        let fileManager = FileManager.default
        let backups: [(url: URL, data: Data?)] = urls.map { url in
            (url, try? Data(contentsOf: url))
        }
        defer {
            for backup in backups {
                if let data = backup.data {
                    try? fileManager.createDirectory(at: backup.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: backup.url, options: .atomic)
                } else {
                    try? fileManager.removeItem(at: backup.url)
                }
            }
            _ = RuleLoader.shared.reloadCached()
        }
        try body()
    }

    private func writeJSON(_ object: Any, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
