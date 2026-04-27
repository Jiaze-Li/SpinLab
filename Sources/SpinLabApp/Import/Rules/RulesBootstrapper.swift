import Foundation
import CryptoKit

struct RulesBootstrapper {
    static func migrateRuntimeRulesIfNeeded() {
        let paths = RulesConfigPaths()
        let fm = FileManager.default
        let decoder = JSONDecoder()
        let stateURL = paths.configDirectoryURL.appendingPathComponent(".migration_state.json")
        let failedURL = paths.configDirectoryURL.appendingPathComponent(".migration_failed.json")

        do {
            try fm.createDirectory(at: paths.configDirectoryURL, withIntermediateDirectories: true)
        } catch {
            AppLogger.shared.error(.import, "RulesBootstrapper migration skipped: cannot create config directory", metadata: [
                "reason": error.localizedDescription
            ])
            return
        }

        do {
            if fm.fileExists(atPath: stateURL.path) {
                let stateData = try Data(contentsOf: stateURL)
                let stateObj = try JSONSerialization.jsonObject(with: stateData)
                if let state = stateObj as? [String: Any],
                   let version = state["rules_schema_version"] as? Int,
                   version >= 5 {
                    AppLogger.shared.info(.import, "RulesBootstrapper migration skipped: already migrated", metadata: [
                        "rules_schema_version": String(version)
                    ])
                    return
                }
            }
        } catch {
            AppLogger.shared.warning(.import, "RulesBootstrapper migration state unreadable; continuing (\(error.localizedDescription))")
        }

        let measuringURL = paths.measuringConditionURL
        let sampleURL = paths.sampleIdentificationURL
        let workflowURL = paths.workflowURL
        let tokenizationURL = paths.filenameTokenizationURL

        guard fm.fileExists(atPath: measuringURL.path), fm.fileExists(atPath: sampleURL.path) else {
            AppLogger.shared.info(.import, "RulesBootstrapper migration skipped: runtime files incomplete", metadata: [
                "measuring_condition_exists": fm.fileExists(atPath: measuringURL.path) ? "true" : "false",
                "sample_identification_exists": fm.fileExists(atPath: sampleURL.path) ? "true" : "false"
            ])
            return
        }

        let sourceMeasuringData: Data
        let sourceSampleData: Data
        let sourceMeasuringJSON: [String: Any]
        let sourceSampleJSON: [String: Any]
        let tokenizationJSON: [String: Any]?
        let sourceWorkflowData: Data?
        let sourceWorkflowJSON: [String: Any]?
        do {
            sourceMeasuringData = try Data(contentsOf: measuringURL)
            sourceSampleData = try Data(contentsOf: sampleURL)

            let measuringObj = try JSONSerialization.jsonObject(with: sourceMeasuringData)
            let sampleObj = try JSONSerialization.jsonObject(with: sourceSampleData)
            guard let measuringDict = measuringObj as? [String: Any],
                  let sampleDict = sampleObj as? [String: Any] else {
                AppLogger.shared.error(.import, "RulesBootstrapper migration skipped: root JSON is not object", metadata: [:])
                return
            }
            sourceMeasuringJSON = measuringDict
            sourceSampleJSON = sampleDict

            if fm.fileExists(atPath: tokenizationURL.path) {
                let tokenData = try Data(contentsOf: tokenizationURL)
                tokenizationJSON = try JSONSerialization.jsonObject(with: tokenData) as? [String: Any]
            } else {
                tokenizationJSON = nil
            }

            if fm.fileExists(atPath: workflowURL.path) {
                let wfData = try Data(contentsOf: workflowURL)
                sourceWorkflowData = wfData
                sourceWorkflowJSON = try JSONSerialization.jsonObject(with: wfData) as? [String: Any]
            } else {
                sourceWorkflowData = nil
                sourceWorkflowJSON = nil
            }
        } catch {
            AppLogger.shared.error(.import, "RulesBootstrapper migration skipped: failed to read runtime json", metadata: [
                "reason": error.localizedDescription
            ])
            return
        }

        let measuringVersion = (sourceMeasuringJSON["version"] as? Int) ?? 0
        let sampleVersion = (sourceSampleJSON["version"] as? Int) ?? 0
        let workflowVersion = (sourceWorkflowJSON?["version"] as? Int) ?? (sourceWorkflowJSON != nil ? 0 : Int.max)
        if measuringVersion >= 3, sampleVersion >= 4, workflowVersion >= 2 {
            var sourceHash: [String: String] = [
                "measuring_condition.json": sha256Hex(sourceMeasuringData),
                "sample_identification.json": sha256Hex(sourceSampleData)
            ]
            if let wfd = sourceWorkflowData {
                sourceHash["workflow.json"] = sha256Hex(wfd)
            }
            writeMigrationState(
                to: stateURL,
                sourceSHA: sourceHash,
                targetSHA: sourceHash,
                warnings: []
            )
            return
        }

        let timestamp = migrationTimestamp()
        let tmpDir = paths.configDirectoryURL.appendingPathComponent(".migration-tmp-\(timestamp)", isDirectory: true)
        let backupDir = paths.configDirectoryURL.appendingPathComponent(".backup-\(timestamp)", isDirectory: true)

        var warnings: [String] = []
        let migratedMeasuringJSON: [String: Any]
        let migratedSampleJSON: [String: Any]
        let migratedWorkflowJSON: [String: Any]?
        do {
            let v2MeasuringJSON = try migrateMeasuringConditionIfNeeded(json: sourceMeasuringJSON, warnings: &warnings)
            migratedMeasuringJSON = try migrateMeasuringConditionV2ToV3IfNeeded(json: v2MeasuringJSON, warnings: &warnings)
            let v2SampleJSON = try migrateSampleIdentificationIfNeeded(json: sourceSampleJSON, warnings: &warnings)
            let v3SampleJSON = try migrateSampleIdentificationV2ToV3IfNeeded(
                json: v2SampleJSON,
                tokenizationJSON: tokenizationJSON,
                warnings: &warnings
            )
            migratedSampleJSON = try migrateSampleIdentificationV3ToV4IfNeeded(
                json: v3SampleJSON,
                warnings: &warnings
            )
            if let wfJSON = sourceWorkflowJSON {
                migratedWorkflowJSON = try migrateWorkflowV1ToV2IfNeeded(json: wfJSON, warnings: &warnings)
            } else {
                migratedWorkflowJSON = nil
            }
        } catch {
            AppLogger.shared.error(.import, "RulesBootstrapper migration skipped: transform failed", metadata: [
                "reason": error.localizedDescription
            ])
            return
        }

        let migratedMeasuringData: Data
        let migratedSampleData: Data
        let migratedWorkflowData: Data?
        do {
            migratedMeasuringData = try JSONSerialization.data(withJSONObject: migratedMeasuringJSON, options: [.prettyPrinted, .sortedKeys])
            migratedSampleData = try JSONSerialization.data(withJSONObject: migratedSampleJSON, options: [.prettyPrinted, .sortedKeys])
            if let wfJSON = migratedWorkflowJSON {
                migratedWorkflowData = try JSONSerialization.data(withJSONObject: wfJSON, options: [.prettyPrinted, .sortedKeys])
            } else {
                migratedWorkflowData = nil
            }
        } catch {
            AppLogger.shared.error(.import, "RulesBootstrapper migration skipped: failed to encode migrated json", metadata: [
                "reason": error.localizedDescription
            ])
            return
        }

        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            try migratedMeasuringData.write(to: tmpDir.appendingPathComponent("measuring_condition.json"), options: .atomic)
            try migratedSampleData.write(to: tmpDir.appendingPathComponent("sample_identification.json"), options: .atomic)
            if let wfd = migratedWorkflowData {
                try wfd.write(to: tmpDir.appendingPathComponent("workflow.json"), options: .atomic)
            }
        } catch {
            AppLogger.shared.error(.import, "RulesBootstrapper migration skipped: failed to write tmp files", metadata: [
                "reason": error.localizedDescription
            ])
            return
        }

        do {
            _ = try decoder.decode(MigrationMeasuringConditionFile.self, from: migratedMeasuringData)
            _ = try decoder.decode(MigrationSampleIdentificationFile.self, from: migratedSampleData)
            if let wfd = migratedWorkflowData {
                _ = try decoder.decode(MigrationWorkflowFile.self, from: wfd)
            }
        } catch {
            writeMigrationFailed(
                to: failedURL,
                reason: "verify decode failed: \(error.localizedDescription)",
                warnings: warnings
            )
            cleanupTmpDirectory(tmpDir, fileManager: fm)
            return
        }

        let shouldWriteBackup = measuringVersion < 3 || sampleVersion < 3
            || (sourceWorkflowData != nil && workflowVersion < 2)
        if shouldWriteBackup {
            do {
                try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
                try sourceMeasuringData.write(to: backupDir.appendingPathComponent("measuring_condition.json"), options: .atomic)
                try sourceSampleData.write(to: backupDir.appendingPathComponent("sample_identification.json"), options: .atomic)
                if let wfd = sourceWorkflowData {
                    try wfd.write(to: backupDir.appendingPathComponent("workflow.json"), options: .atomic)
                }
            } catch {
                AppLogger.shared.error(.import, "RulesBootstrapper migration skipped: failed to write backup files", metadata: [
                    "reason": error.localizedDescription
                ])
                cleanupTmpDirectory(tmpDir, fileManager: fm)
                return
            }
        }

        do {
            try migratedMeasuringData.write(to: measuringURL, options: .atomic)
            try migratedSampleData.write(to: sampleURL, options: .atomic)
            if let wfd = migratedWorkflowData {
                try wfd.write(to: workflowURL, options: .atomic)
            }
        } catch {
            AppLogger.shared.error(.import, "RulesBootstrapper migration failed: atomic replace failed", metadata: [
                "reason": error.localizedDescription
            ])
            cleanupTmpDirectory(tmpDir, fileManager: fm)
            return
        }

        var sourceSHA: [String: String] = [
            "measuring_condition.json": sha256Hex(sourceMeasuringData),
            "sample_identification.json": sha256Hex(sourceSampleData)
        ]
        var targetSHA: [String: String] = [
            "measuring_condition.json": sha256Hex(migratedMeasuringData),
            "sample_identification.json": sha256Hex(migratedSampleData)
        ]
        if let wfSrc = sourceWorkflowData, let wfTgt = migratedWorkflowData {
            sourceSHA["workflow.json"] = sha256Hex(wfSrc)
            targetSHA["workflow.json"] = sha256Hex(wfTgt)
        }
        writeMigrationState(
            to: stateURL,
            sourceSHA: sourceSHA,
            targetSHA: targetSHA,
            warnings: warnings
        )

        do {
            if fm.fileExists(atPath: tmpDir.path) {
                try fm.removeItem(at: tmpDir)
            }
        } catch {
            AppLogger.shared.warning(.import, "RulesBootstrapper migration tmp cleanup failed (\(error.localizedDescription))")
        }
    }

    static func seedMissingRuntimeFilesFromBundleIfNeeded() {
        migrateRuntimeRulesIfNeeded()
        let paths = RulesConfigPaths()
        let fm = FileManager.default
        let locator = BundleFileLocator()

        let files: [(url: URL, name: String)] = [
            (paths.importFiltersURL, "import_filters"),
            (paths.filenameTokenizationURL, "filename_tokenization"),
            (paths.sampleIdentificationURL, "sample_identification"),
            (paths.workflowURL, "workflow"),
            (paths.measuringConditionURL, "measuring_condition")
        ]

        for (url, name) in files {
            guard !fm.fileExists(atPath: url.path) else { continue }
            let data: Data?
            do {
                data = try locator.data(for: name)
            } catch {
                AppLogger.shared.warning(.import, "RulesBootstrapper: bundle file read failed — \(name).json (\(error.localizedDescription))")
                continue
            }
            guard let data else {
                AppLogger.shared.warning(.import, "RulesBootstrapper: bundle file missing — \(name).json")
                continue
            }
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                AppLogger.shared.error(.import, "RulesBootstrapper: failed to seed \(name).json", metadata: [
                    "reason": error.localizedDescription
                ])
            }
        }
    }

    private static func migrateMeasuringConditionIfNeeded(json: [String: Any], warnings: inout [String]) throws -> [String: Any] {
        let isV1 = (json["conditions"] as? [String: Any]) != nil
        guard isV1 else { return json }

        let conditions = (json["conditions"] as? [String: Any]) ?? [:]
        let extraConditions = (conditions["extraConditions"] as? [String: String]) ?? [:]
        let tokenMapRules = (conditions["tokenMapRules"] as? [String: [[String: Any]]]) ?? [:]
        let definitions = (json["conditionDefinitions"] as? [[String: Any]]) ?? []

        var migratedDefinitions: [[String: Any]] = []
        for definition in definitions {
            guard let id = definition["id"] as? String,
                  let kind = definition["kind"] as? String else {
                warnings.append("measuring_condition: conditionDefinitions entry missing id/kind, skipped")
                continue
            }

            var migrated: [String: Any] = [
                "id": id,
                "kind": kind
            ]
            if let label = definition["label"] as? String {
                migrated["label"] = label
            }

            let binding = definition["binding"] as? String
            switch kind {
            case "unit_suffix":
                let bindingKey = bindingKeyFrom(binding, prefix: "conditions.extraConditions.")
                if let binding,
                   binding.hasPrefix("conditions.tokenMapRules.") {
                    warnings.append("measuring_condition: kind/binding mismatch for \(id), kind unit_suffix takes precedence")
                }
                let key = bindingKey ?? id
                if let pattern = extraConditions[key] {
                    migrated["unitPattern"] = pattern
                } else {
                    warnings.append("measuring_condition: missing unitPattern for \(id)")
                }
            case "token_map":
                let bindingKey = bindingKeyFrom(binding, prefix: "conditions.tokenMapRules.")
                if let binding,
                   binding.hasPrefix("conditions.extraConditions.") {
                    warnings.append("measuring_condition: kind/binding mismatch for \(id), kind token_map takes precedence")
                }
                let key = bindingKey ?? id
                if let rules = tokenMapRules[key] {
                    migrated["tokenMap"] = rules
                } else {
                    warnings.append("measuring_condition: missing tokenMap for \(id)")
                    migrated["tokenMap"] = []
                }
            default:
                warnings.append("measuring_condition: unsupported kind \(kind) for \(id), skipped")
                continue
            }

            migratedDefinitions.append(migrated)
        }

        return [
            "version": 2,
            "conditionDefinitions": migratedDefinitions
        ]
    }

    private static func migrateSampleIdentificationIfNeeded(json: [String: Any], warnings: inout [String]) throws -> [String: Any] {
        guard let substrate = json["substrate"] as? [String: Any] else {
            throw NSError(domain: "RulesBootstrapper", code: 1, userInfo: [NSLocalizedDescriptionKey: "sample_identification missing substrate"])
        }
        let hasShared = substrate["shared"] != nil
        let isV1 = hasShared
        guard isV1 else { return json }

        guard let shared = substrate["shared"] as? [String: Any] else {
            throw NSError(domain: "RulesBootstrapper", code: 2, userInfo: [NSLocalizedDescriptionKey: "sample_identification v1 missing substrate.shared"])
        }

        let sampleId = (json["sampleId"] as? [String: Any]) ?? [:]
        let substrateTagRules = (substrate["substrateTagRules"] as? [[String: Any]]) ?? []
        let tokenSeparators = (shared["tokenSeparators"] as? String) ?? ""
        let materialTokens = stringArray(shared["materialTokens"])
        let materialAliases = stringDictionary(shared["materialAliases"])
        let materialDisplayNames = stringDictionary(shared["materialDisplayNames"])
        let treatmentKeywords = stringArrayDictionary(shared["treatmentKeywords"])
        let originStandaloneTokens = stringArray(shared["originStandaloneTokens"])
        let originContainsTokens = stringArray(shared["originContainsTokens"])
        let orientationTokens = stringArray(shared["orientationTokens"])
        let orientationAliases = stringDictionary(shared["orientationAliases"])
        let orientationPattern = (shared["orientationPattern"] as? String) ?? ""

        var materialRowsByID: [String: (tokens: [String], aliases: [String], displayName: String)] = [:]
        var materialOrder: [String] = []
        for token in materialTokens {
            if materialRowsByID[token] == nil {
                materialOrder.append(token)
            }
            materialRowsByID[token] = (
                tokens: [token],
                aliases: [],
                displayName: materialDisplayNames[token] ?? token
            )
        }
        for (alias, canonicalID) in materialAliases {
            if materialRowsByID[canonicalID] == nil {
                materialRowsByID[canonicalID] = (
                    tokens: [canonicalID],
                    aliases: [],
                    displayName: materialDisplayNames[canonicalID] ?? canonicalID
                )
                materialOrder.append(canonicalID)
            }
            if materialRowsByID[canonicalID]?.aliases.contains(alias) == false {
                materialRowsByID[canonicalID]?.aliases.append(alias)
            }
        }
        let materials: [[String: Any]] = materialOrder.compactMap { id in
            guard let row = materialRowsByID[id] else { return nil }
            return [
                "id": id,
                "tokens": row.tokens,
                "aliases": row.aliases.sorted(),
                "displayName": row.displayName
            ]
        }

        var treatments: [[String: Any]] = []
        for id in treatmentKeywords.keys.sorted() {
            let keywords = treatmentKeywords[id] ?? []
            let standalone = id == "o" ? originStandaloneTokens : []
            let contains = id == "o" ? originContainsTokens : []
            treatments.append([
                "id": id,
                "displayName": id,
                "keywords": keywords,
                "standaloneTokens": standalone,
                "containsTokens": contains
            ])
        }

        var orientationRowsByID: [String: (tokens: [String], aliases: [String])] = [:]
        var orientationOrder: [String] = []
        for token in orientationTokens {
            if orientationRowsByID[token] == nil {
                orientationOrder.append(token)
            }
            orientationRowsByID[token] = (tokens: [token], aliases: [])
        }
        for (alias, canonicalID) in orientationAliases {
            if orientationRowsByID[canonicalID] == nil {
                orientationRowsByID[canonicalID] = (tokens: [canonicalID], aliases: [])
                orientationOrder.append(canonicalID)
            }
            if orientationRowsByID[canonicalID]?.aliases.contains(alias) == false {
                orientationRowsByID[canonicalID]?.aliases.append(alias)
            }
        }
        let orientationRows: [[String: Any]] = orientationOrder.compactMap { id in
            guard let row = orientationRowsByID[id] else { return nil }
            return [
                "id": id,
                "tokens": row.tokens,
                "aliases": row.aliases.sorted()
            ]
        }
        if orientationRows.isEmpty {
            warnings.append("sample_identification: orientation rows empty after migration")
        }

        return [
            "version": 2,
            "sampleId": sampleId,
            "substrate": [
                "tokenSeparators": tokenSeparators,
                "substrateTagRules": substrateTagRules,
                "materials": materials,
                "treatments": treatments,
                "orientations": [
                    "pattern": orientationPattern,
                    "rows": orientationRows
                ]
            ]
        ]
    }

    private static func migrateSampleIdentificationV2ToV3IfNeeded(
        json: [String: Any],
        tokenizationJSON: [String: Any]?,
        warnings: inout [String]
    ) throws -> [String: Any] {
        let version = (json["version"] as? Int) ?? 0
        guard version < 3 else { return json }

        var migrated = json
        migrated["version"] = 3

        guard var substrate = migrated["substrate"] as? [String: Any] else {
            return migrated
        }

        if let substrateSeparators = substrate["tokenSeparators"] as? String {
            let tokenizationSeparators: String?
            if let tokenizationJSON,
               let tokenization = tokenizationJSON["tokenization"] as? [String: Any] {
                tokenizationSeparators = tokenization["separators"] as? String
            } else {
                tokenizationSeparators = nil
            }

            if let tokenizationSeparators, tokenizationSeparators != substrateSeparators {
                warnings.append(
                    "sample_identification: substrate.tokenSeparators=\"\(substrateSeparators)\" differs from filename_tokenization.separators=\"\(tokenizationSeparators)\"; substrate detection will follow filename_tokenization after migration"
                )
            } else if tokenizationSeparators == nil {
                warnings.append(
                    "sample_identification: substrate.tokenSeparators=\"\(substrateSeparators)\" dropped; filename_tokenization not found, substrate detection will use loaded tokenization at runtime"
                )
            }
        }

        substrate.removeValue(forKey: "tokenSeparators")
        migrated["substrate"] = substrate
        return migrated
    }

    private static func migrateSampleIdentificationV3ToV4IfNeeded(
        json: [String: Any],
        warnings: inout [String]
    ) throws -> [String: Any] {
        let version = (json["version"] as? Int) ?? 0
        guard version < 4 else { return json }

        let sampleId = (json["sampleId"] as? [String: Any]) ?? [:]
        let patterns = sampleId["patterns"] as? [String] ?? []
        let patternRegex = try NSRegularExpression(pattern: #"^\^(.+)\\d\+\$$"#)
        let prefixRegex = try NSRegularExpression(pattern: #"^[A-Za-z0-9_-]+$"#)
        var batchPrefixes: [String] = []
        var seenBatchPrefixes = Set<String>()

        for pattern in patterns {
            let range = NSRange(pattern.startIndex..<pattern.endIndex, in: pattern)
            guard let match = patternRegex.firstMatch(in: pattern, options: [], range: range),
                  let bodyRange = Range(match.range(at: 1), in: pattern) else {
                warnings.append("sample_identification: sampleId.patterns '\(pattern)' could not be converted to batchPrefixes and was discarded")
                continue
            }

            var body = String(pattern[bodyRange])
            if body.hasPrefix("(?:"), body.hasSuffix(")") {
                body.removeFirst(3)
                body.removeLast()
            }
            let candidates = body.split(separator: "|").map(String.init)

            var hasValidPrefix = false
            for candidate in candidates {
                let candidateRange = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
                guard prefixRegex.firstMatch(in: candidate, options: [], range: candidateRange) != nil else {
                    warnings.append("sample_identification: sampleId.patterns '\(pattern)' could not be converted to batchPrefixes and was discarded")
                    continue
                }
                if seenBatchPrefixes.insert(candidate).inserted {
                    batchPrefixes.append(candidate)
                }
                hasValidPrefix = true
            }

            if !hasValidPrefix {
                warnings.append("sample_identification: sampleId.patterns '\(pattern)' could not be converted to batchPrefixes and was discarded")
            }
        }

        let substrate = (json["substrate"] as? [String: Any]) ?? [:]
        let materials = substrate["materials"] as? [[String: Any]] ?? []
        let treatments = substrate["treatments"] as? [[String: Any]] ?? []
        let orientationsDict = substrate["orientations"] as? [String: Any] ?? [:]
        let orientationRows = orientationsDict["rows"] as? [[String: Any]] ?? []
        let substrateTagRules = substrate["substrateTagRules"] as? [[String: Any]] ?? []

        var newMaterials: [[String: Any]] = []
        for entry in materials {
            let id = entry["id"] as? String ?? ""
            let displayName: String
            if let explicit = entry["displayName"] as? String, !explicit.isEmpty {
                displayName = explicit
            } else {
                displayName = id
            }
            guard !displayName.isEmpty else {
                warnings.append("sample_identification: substrate.materials entry missing displayName/id and was skipped")
                continue
            }

            let tokens = entry["tokens"] as? [String] ?? []
            let aliases = entry["aliases"] as? [String] ?? []
            var matches: [[String: String]] = []
            var seen = Set<String>()
            for value in (tokens + aliases) where !value.isEmpty {
                let key = value.lowercased()
                if seen.insert(key).inserted {
                    matches.append(["type": "equals", "value": value])
                }
            }
            newMaterials.append([
                "displayName": displayName,
                "matches": matches
            ])
        }

        var newTreatments: [[String: Any]] = []
        for entry in treatments {
            let id = entry["id"] as? String ?? ""
            let displayName: String
            if let explicit = entry["displayName"] as? String, !explicit.isEmpty {
                displayName = explicit
            } else {
                displayName = id
            }
            guard !displayName.isEmpty else {
                warnings.append("sample_identification: substrate.treatments entry missing displayName/id and was skipped")
                continue
            }

            var matches: [[String: String]] = []
            var seenEquals = Set<String>()
            var seenContains = Set<String>()

            let standaloneTokens = entry["standaloneTokens"] as? [String] ?? []
            for value in standaloneTokens where !value.isEmpty {
                let key = value.lowercased()
                if seenEquals.insert(key).inserted {
                    matches.append(["type": "equals", "value": value])
                }
            }

            let containsTokens = entry["containsTokens"] as? [String] ?? []
            for value in containsTokens where !value.isEmpty {
                let key = value.lowercased()
                if seenContains.insert(key).inserted {
                    matches.append(["type": "contains", "value": value])
                }
            }

            let keywords = entry["keywords"] as? [String] ?? []
            for value in keywords where !value.isEmpty {
                let key = value.lowercased()
                if seenContains.insert(key).inserted {
                    matches.append(["type": "contains", "value": value])
                }
            }

            newTreatments.append([
                "displayName": displayName,
                "matches": matches
            ])
        }

        if orientationsDict["pattern"] != nil {
            warnings.append("sample_identification: orientations.pattern dropped during v3→v4 migration; individual row tokens/aliases are preserved as equals matches")
        }

        var newOrientations: [[String: Any]] = []
        for row in orientationRows {
            let id = row["id"] as? String ?? ""
            guard !id.isEmpty else {
                warnings.append("sample_identification: substrate.orientations row missing id and was skipped")
                continue
            }
            let displayName = id
            let tokens = row["tokens"] as? [String] ?? []
            let aliases = row["aliases"] as? [String] ?? []
            var matches: [[String: String]] = []
            var seen = Set<String>()
            for value in (tokens + aliases) where !value.isEmpty {
                let key = value.lowercased()
                if key == displayName.lowercased() {
                    continue
                }
                if seen.insert(key).inserted {
                    matches.append(["type": "equals", "value": value])
                }
            }
            newOrientations.append([
                "displayName": displayName,
                "matches": matches
            ])
        }

        for rule in substrateTagRules {
            let ruleDescription = (rule["tag"] as? String) ?? "\(rule)"
            warnings.append("sample_identification: substrateTagRule '\(ruleDescription)' removed; equivalent behavior now comes from treatments/materials/orientations matches")
        }
        if !substrateTagRules.isEmpty {
            warnings.append("sample_identification: \(substrateTagRules.count) substrateTagRule(s) removed in v3→v4 migration")
        }

        var newSampleId: [String: Any] = [:]
        for (key, value) in sampleId where key != "patterns" {
            newSampleId[key] = value
        }
        newSampleId["batchPrefixes"] = batchPrefixes

        let newSubstrate: [String: Any] = [
            "materials": newMaterials,
            "treatments": newTreatments,
            "orientations": newOrientations
        ]

        return [
            "version": 4,
            "sampleId": newSampleId,
            "substrate": newSubstrate
        ]
    }

    private static func bindingKeyFrom(_ binding: String?, prefix: String) -> String? {
        guard let binding else { return nil }
        guard binding.hasPrefix(prefix) else { return nil }
        return String(binding.dropFirst(prefix.count))
    }

    private static func stringArray(_ any: Any?) -> [String] {
        guard let values = any as? [String] else { return [] }
        return values
    }

    private static func stringDictionary(_ any: Any?) -> [String: String] {
        guard let values = any as? [String: String] else { return [:] }
        return values
    }

    private static func stringArrayDictionary(_ any: Any?) -> [String: [String]] {
        guard let values = any as? [String: [String]] else { return [:] }
        return values
    }

    private static func migrateMeasuringConditionV2ToV3IfNeeded(json: [String: Any], warnings: inout [String]) throws -> [String: Any] {
        let version = (json["version"] as? Int) ?? 0
        guard version < 3 else { return json }

        let definitions = (json["conditionDefinitions"] as? [[String: Any]]) ?? []
        var migratedDefinitions: [[String: Any]] = []
        for var def in definitions {
            if let label = def["label"] as? String {
                def["displayName"] = label
                def.removeValue(forKey: "label")
            }
            if let tokenMap = def["tokenMap"] as? [[String: Any]] {
                let cleaned: [[String: Any]] = tokenMap.map { rule in
                    guard var match = rule["match"] as? [String: Any] else { return rule }
                    match.removeValue(forKey: "scope")
                    var cleaned = rule
                    cleaned["match"] = match
                    return cleaned
                }
                def["tokenMap"] = cleaned
            }
            migratedDefinitions.append(def)
        }
        return ["version": 3, "conditionDefinitions": migratedDefinitions]
    }

    private static func migrateWorkflowV1ToV2IfNeeded(json: [String: Any], warnings: inout [String]) throws -> [String: Any] {
        let version = (json["version"] as? Int) ?? 0
        guard version < 2 else { return json }

        func stripScope(_ spec: [String: Any]) -> [String: Any] {
            var s = spec
            s.removeValue(forKey: "scope")
            return s
        }

        let rawWorkflows = (json["workflows"] as? [[String: Any]]) ?? []
        let migratedWorkflows: [[String: Any]] = rawWorkflows.map { wf in
            var w = wf
            if let matchRules = wf["matchRules"] as? [[String: Any]] {
                w["matchRules"] = matchRules.map(stripScope)
            }
            return w
        }

        let rawTagRules = (json["measurementTagRules"] as? [[String: Any]]) ?? []
        let migratedTagRules: [[String: Any]] = rawTagRules.map { rule in
            guard var match = rule["match"] as? [String: Any] else { return rule }
            match.removeValue(forKey: "scope")
            var r = rule
            r["match"] = match
            return r
        }

        var migrated = json
        migrated["version"] = 2
        migrated["workflows"] = migratedWorkflows
        migrated["measurementTagRules"] = migratedTagRules
        return migrated
    }

    private static func writeMigrationState(
        to url: URL,
        sourceSHA: [String: String],
        targetSHA: [String: String],
        warnings: [String]
    ) {
        let body: [String: Any] = [
            "rules_schema_version": 5,
            "migrated_at": migrationDateString(),
            "source_sha256": sourceSHA,
            "target_sha256": targetSHA,
            "warnings": warnings
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.warning(.import, "RulesBootstrapper: failed to write migration_state (\(error.localizedDescription))")
        }
    }

    private static func writeMigrationFailed(to url: URL, reason: String, warnings: [String]) {
        let body: [String: Any] = [
            "failed_at": migrationDateString(),
            "reason": reason,
            "warnings": warnings
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            AppLogger.shared.error(.import, "RulesBootstrapper migration verify failed", metadata: [
                "reason": reason
            ])
        } catch {
            AppLogger.shared.error(.import, "RulesBootstrapper migration verify failed; cannot persist failure file", metadata: [
                "reason": error.localizedDescription
            ])
        }
    }

    private static func migrationTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func migrationDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.string(from: Date())
    }

    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func cleanupTmpDirectory(_ tmpDir: URL, fileManager: FileManager) {
        guard fileManager.fileExists(atPath: tmpDir.path) else { return }
        do {
            try fileManager.removeItem(at: tmpDir)
        } catch {
            AppLogger.shared.warning(.import, "RulesBootstrapper migration tmp cleanup failed (\(error.localizedDescription))")
        }
    }
}

private struct MigrationMeasuringConditionFile: Decodable {
    let version: Int
    let conditionDefinitions: [FilenameRuleSet.ConditionDefinition]
}

private struct MigrationWorkflowFile: Decodable {
    let version: Int
    struct WorkflowEntry: Decodable {
        let id: String
        let displayName: String
        let matchRules: [MatchSpec]
        let conditionFieldIDs: [String]
        struct MatchSpec: Decodable {
            let type: String
            let matchValues: [String]
        }
    }
    let workflows: [WorkflowEntry]
}

private struct MigrationSampleIdentificationFile: Decodable {
    let version: Int
    let sampleId: FilenameRuleSet.SampleIdRules
    // Flexible substrate verify: accepts v3 (materials as objects with id/tokens)
    // and v4 (materials as SubstrateEntry with displayName/matches).
    // Only checks that the substrate section is a valid decodable JSON object.
    let substrate: SubstrateVerify

    struct SubstrateVerify: Decodable {
        init(from decoder: Decoder) throws {
            _ = try decoder.container(keyedBy: AnyKey.self)
        }
        private struct AnyKey: CodingKey {
            var stringValue: String
            var intValue: Int?
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { self.intValue = intValue; self.stringValue = "\(intValue)" }
        }
    }
}
