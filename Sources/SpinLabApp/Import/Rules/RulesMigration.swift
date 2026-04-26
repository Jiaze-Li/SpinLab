import Foundation
import CryptoKit

struct RulesMigration {
    static let targetSchemaVersion = 3

    static func runIfNeeded() {
        let paths = RulesConfigPaths()
        guard !isMigrationComplete(paths: paths) else { return }
        do {
            try migrate(paths: paths)
        } catch {
            AppLogger.shared.error(.import, "Rules migration failed — app will use bundle fallback this session", metadata: [
                "reason": error.localizedDescription
            ])
        }
    }

    // MARK: - Completion check

    private static func isMigrationComplete(paths: RulesConfigPaths) -> Bool {
        let migrationFailedURL = paths.configDirectoryURL.appendingPathComponent("migration_failed.json")
        if FileManager.default.fileExists(atPath: migrationFailedURL.path) {
            return true
        }

        guard let stateData = try? Data(contentsOf: paths.migrationStateURL),
              let state = try? JSONDecoder().decode(RulesMigrationState.self, from: stateData),
              state.rules_schema_version >= targetSchemaVersion else {
            return false
        }

        let fm = FileManager.default
        return paths.allSchemaFileURLs.allSatisfy { fm.fileExists(atPath: $0.path) }
    }

    // MARK: - Migration

    private static func migrate(paths: RulesConfigPaths) throws {
        let fm = FileManager.default
        let configDir = paths.configDirectoryURL
        try fm.createDirectory(at: configDir, withIntermediateDirectories: true)

        let tmpDir = configDir.appendingPathComponent(".migration-tmp", isDirectory: true)
        try? fm.removeItem(at: tmpDir)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        var sourceHashes: [String: String] = [:]

        let oldFilenames = [
            "filename_rules.json",
            "substrate_rules.json",
            "conditions_rules.json",
            "filename_parse_rules.json",
            "sample_id_rules.json",
            "workflow_match_rules.json",
            "substrate_normalization_rules.json",
            "measurement_tag_rules.json",
            "workflow_id_policy.json",
            "library_import_rules.json"
        ]

        for name in oldFilenames {
            let url = configDir.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                let backupURL = configDir.appendingPathComponent("\(name).backup-\(ts)")
                try fm.copyItem(at: url, to: backupURL)
                if let data = try? Data(contentsOf: url) {
                    sourceHashes[name] = sha256Hex(data)
                }
            }
        }

        let assembled = try assembleNewSchema(paths: paths)

        let targetFiles: [(URL, Data)] = [
            (paths.importFiltersURL, assembled.importFilters),
            (paths.filenameTokenizationURL, assembled.filenameTokenization),
            (paths.sampleIdentificationURL, assembled.sampleIdentification),
            (paths.workflowURL, assembled.workflow),
            (paths.measuringConditionURL, assembled.measuringCondition)
        ]

        var tmpURLs: [(URL, URL)] = []
        let migrationFailedURL = configDir.appendingPathComponent("migration_failed.json")

        for (destURL, data) in targetFiles {
            let tmpURL = tmpDir.appendingPathComponent(destURL.lastPathComponent)
            try data.write(to: tmpURL)
            do {
                try verifyDecodable(at: tmpURL, name: destURL.lastPathComponent)
            } catch {
                let failedInfo: [String: String] = [
                    "reason": error.localizedDescription,
                    "failedAt": ISO8601DateFormatter().string(from: Date())
                ]
                if let failedData = try? JSONSerialization.data(withJSONObject: failedInfo, options: .prettyPrinted) {
                    try? failedData.write(to: migrationFailedURL)
                }
                try? fm.removeItem(at: tmpDir)
                throw error
            }
            tmpURLs.append((tmpURL, destURL))
        }

        for (tmpURL, destURL) in tmpURLs {
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.moveItem(at: tmpURL, to: destURL)
        }

        let state = RulesMigrationState(
            rules_schema_version: targetSchemaVersion,
            migratedAt: ISO8601DateFormatter().string(from: Date()),
            sourceFileSHA256: sourceHashes
        )
        let stateData = try JSONEncoder().encode(state)
        try stateData.write(to: paths.migrationStateURL)

        stripParentIDFromRegistry(configDir: configDir)

        let obsoleteFilenames = [
            "filename_parse_rules.json",
            "sample_id_rules.json",
            "workflow_match_rules.json",
            "substrate_normalization_rules.json",
            "measurement_tag_rules.json",
            "workflow_id_policy.json",
            "filename_rules.json",
            "substrate_rules.json",
            "conditions_rules.json"
        ]

        for name in obsoleteFilenames {
            let url = configDir.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }

        try? fm.removeItem(at: tmpDir)

        AppLogger.shared.info(.import, "Rules migration complete", metadata: [
            "schemaVersion": "\(targetSchemaVersion)",
            "sourceFiles": sourceHashes.keys.sorted().joined(separator: ", ")
        ])
    }

    // MARK: - Schema assembly

    private struct AssembledSchema {
        let importFilters: Data
        let filenameTokenization: Data
        let sampleIdentification: Data
        let workflow: Data
        let measuringCondition: Data
    }

    private static func assembleNewSchema(paths: RulesConfigPaths) throws -> AssembledSchema {
        let bundleFiles = BundleFileLocator()

        let importFilters = try requireBundle(bundleFiles, name: "import_filters")
        let filenameTokenization = try requireBundle(bundleFiles, name: "filename_tokenization")
        let sampleIdentification = try requireBundle(bundleFiles, name: "sample_identification")
        let rawWorkflow = try requireBundle(bundleFiles, name: "workflow")
        let measuringCondition = try requireBundle(bundleFiles, name: "measuring_condition")

        let workflow = enrichedWorkflowData(rawWorkflow, configDir: paths.configDirectoryURL)

        return AssembledSchema(
            importFilters: importFilters,
            filenameTokenization: filenameTokenization,
            sampleIdentification: sampleIdentification,
            workflow: workflow,
            measuringCondition: measuringCondition
        )
    }

    private static func requireBundle(_ locator: BundleFileLocator, name: String) throws -> Data {
        guard let data = try? locator.data(for: name) else {
            throw MigrationError.bundleFileMissing("\(name).json")
        }
        return data
    }

    private static func enrichedWorkflowData(_ rawWorkflowData: Data, configDir: URL) -> Data {
        let registryURL = configDir
            .deletingLastPathComponent()
            .appendingPathComponent("workflow_registry.json")

        guard FileManager.default.fileExists(atPath: registryURL.path),
              let registryData = try? Data(contentsOf: registryURL),
              let registryEntries = try? JSONSerialization.jsonObject(with: registryData) as? [[String: Any]] else {
            return rawWorkflowData
        }

        var conditionFieldIDsByID: [String: [String]] = [:]
        for entry in registryEntries {
            guard let id = entry["id"] as? String,
                  let fields = entry["conditionFields"] as? [[String: Any]] else {
                continue
            }
            conditionFieldIDsByID[id] = fields.compactMap { $0["definitionID"] as? String }
        }

        guard var workflowJSON = try? JSONSerialization.jsonObject(with: rawWorkflowData) as? [String: Any],
              var workflows = workflowJSON["workflows"] as? [[String: Any]] else {
            return rawWorkflowData
        }

        for i in workflows.indices {
            guard let id = workflows[i]["id"] as? String,
                  let fieldIDs = conditionFieldIDsByID[id] else {
                continue
            }
            workflows[i]["conditionFieldIDs"] = fieldIDs
        }

        workflowJSON["workflows"] = workflows
        guard let enriched = try? JSONSerialization.data(withJSONObject: workflowJSON, options: .prettyPrinted) else {
            return rawWorkflowData
        }
        return enriched
    }

    private static func stripParentIDFromRegistry(configDir: URL) {
        let registryURL = configDir
            .deletingLastPathComponent()
            .appendingPathComponent("workflow_registry.json")

        guard FileManager.default.fileExists(atPath: registryURL.path),
              let data = try? Data(contentsOf: registryURL),
              var entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return
        }

        for index in entries.indices {
            entries[index].removeValue(forKey: "parentID")
        }

        guard let stripped = try? JSONSerialization.data(withJSONObject: entries, options: .prettyPrinted) else {
            return
        }
        try? stripped.write(to: registryURL)
    }

    // MARK: - Verify

    private static func verifyDecodable(at url: URL, name: String) throws {
        let data = try Data(contentsOf: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["version"] != nil else {
            throw MigrationError.verificationFailed(name, "missing version field or invalid JSON")
        }
    }

    // MARK: - Helpers

    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    enum MigrationError: Error, LocalizedError {
        case bundleFileMissing(String)
        case verificationFailed(String, String)

        var errorDescription: String? {
            switch self {
            case .bundleFileMissing(let name):
                return "Bundle file missing: \(name)"
            case .verificationFailed(let name, let reason):
                return "Verification failed for \(name): \(reason)"
            }
        }
    }
}
