import Foundation
import CryptoKit

struct RulesMigration {
    static let targetSchemaVersion = 2

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
        guard let stateData = try? Data(contentsOf: paths.migrationStateURL),
              let state = try? JSONDecoder().decode(RulesMigrationState.self, from: stateData),
              state.rules_schema_version == targetSchemaVersion else {
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

        // Backup any existing config files before overwriting
        let oldFilenames = [
            "filename_rules.json",
            "sample_id_rules.json",
            "workflow_match_rules.json",
            "substrate_rules.json",
            "measurement_tag_rules.json",
            "workflow_id_policy.json",
            "conditions_rules.json"
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

        // Assemble new 7-file content from old sources
        let assembled = try assembleNewSchema(paths: paths)

        // Write all 7 new files to tmp, decode-verify each
        let targetFiles: [(URL, Data)] = [
            (paths.filenameParsRulesURL, assembled.filenameParse),
            (paths.sampleIDRulesURL, assembled.sampleID),
            (paths.workflowMatchRulesURL, assembled.workflowMatch),
            (paths.substrateNormalizationRulesURL, assembled.substrateNorm),
            (paths.measurementTagRulesURL, assembled.measurementTag),
            (paths.workflowIDPolicyURL, assembled.workflowIDPolicy),
            (paths.libraryImportRulesURL, assembled.libraryImport)
        ]

        var tmpURLs: [(URL, URL)] = []
        for (destURL, data) in targetFiles {
            let tmpURL = tmpDir.appendingPathComponent(destURL.lastPathComponent)
            try data.write(to: tmpURL)
            try verifyDecodable(at: tmpURL, name: destURL.lastPathComponent)
            tmpURLs.append((tmpURL, destURL))
        }

        // Atomic rename all files from tmp to final locations
        for (tmpURL, destURL) in tmpURLs {
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.moveItem(at: tmpURL, to: destURL)
        }

        // Write migration state sentinel
        let state = RulesMigrationState(
            rules_schema_version: targetSchemaVersion,
            migratedAt: ISO8601DateFormatter().string(from: Date()),
            sourceFileSHA256: sourceHashes
        )
        let stateData = try JSONEncoder().encode(state)
        try stateData.write(to: paths.migrationStateURL)

        // Delete old files that have been superseded
        let obsoleteFilenames = [
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

        // Clean up tmp dir
        try? fm.removeItem(at: tmpDir)

        AppLogger.shared.info(.import, "Rules migration complete", metadata: [
            "schemaVersion": "\(targetSchemaVersion)",
            "sourceFiles": sourceHashes.keys.sorted().joined(separator: ", ")
        ])

        verifySharedSubstrateFields(paths: paths)
    }

    // MARK: - Schema assembly

    private struct AssembledSchema {
        let filenameParse: Data
        let sampleID: Data
        let workflowMatch: Data
        let substrateNorm: Data
        let measurementTag: Data
        let workflowIDPolicy: Data
        let libraryImport: Data
    }

    private static func assembleNewSchema(paths: RulesConfigPaths) throws -> AssembledSchema {
        let bundleFiles = BundleFileLocator()

        // filename_parse_rules: always use bundle (canonical source)
        let filenameParse = try bundleFiles.data(for: "filename_parse_rules")
            ?? { throw MigrationError.bundleFileMissing("filename_parse_rules.json") }()

        // sample_id_rules: runtime > bundle
        let sampleID = runtimeOrBundle(
            runtime: paths.sampleIDRulesURL,
            bundleProvider: { try? bundleFiles.data(for: "sample_id_rules") }
        ) ?? defaultSampleIDData()

        // workflow_match_rules: runtime > bundle
        let workflowMatch = runtimeOrBundle(
            runtime: paths.workflowMatchRulesURL,
            bundleProvider: { try? bundleFiles.data(for: "workflow_match_rules") }
        ) ?? defaultWorkflowMatchData()

        // substrate_normalization_rules: runtime substrate_rules.json > bundle
        let substrateNorm: Data
        let runtimeSubstrate = paths.configDirectoryURL.appendingPathComponent("substrate_rules.json")
        if FileManager.default.fileExists(atPath: runtimeSubstrate.path),
           let data = try? Data(contentsOf: runtimeSubstrate),
           isSubstrateRulesNewFormat(data) {
            substrateNorm = data
        } else {
            substrateNorm = try bundleFiles.data(for: "substrate_normalization_rules")
                ?? { throw MigrationError.bundleFileMissing("substrate_normalization_rules.json") }()
        }

        // measurement_tag_rules: runtime > bundle
        let measurementTag = runtimeOrBundle(
            runtime: paths.measurementTagRulesURL,
            bundleProvider: { try? bundleFiles.data(for: "measurement_tag_rules") }
        ) ?? defaultMeasurementTagData()

        // workflow_id_policy: runtime > bundle
        let workflowIDPolicy = runtimeOrBundle(
            runtime: paths.workflowIDPolicyURL,
            bundleProvider: { try? bundleFiles.data(for: "workflow_id_policy") }
        ) ?? defaultWorkflowIDPolicyData()

        // library_import_rules: always from bundle (new file, no runtime precedent)
        let libraryImport = try bundleFiles.data(for: "library_import_rules")
            ?? { throw MigrationError.bundleFileMissing("library_import_rules.json") }()

        return AssembledSchema(
            filenameParse: filenameParse,
            sampleID: sampleID,
            workflowMatch: workflowMatch,
            substrateNorm: substrateNorm,
            measurementTag: measurementTag,
            workflowIDPolicy: workflowIDPolicy,
            libraryImport: libraryImport
        )
    }

    private static func runtimeOrBundle(runtime: URL, bundleProvider: () -> Data?) -> Data? {
        if FileManager.default.fileExists(atPath: runtime.path),
           let data = try? Data(contentsOf: runtime) {
            return data
        }
        return bundleProvider()
    }

    // Checks if a substrate_rules.json has the new sharedSubstrate top-level format
    private static func isSubstrateRulesNewFormat(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["sharedSubstrate"] != nil
    }

    // MARK: - Verify

    private static func verifyDecodable(at url: URL, name: String) throws {
        let data = try Data(contentsOf: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["version"] != nil else {
            throw MigrationError.verificationFailed(name, "missing version field or invalid JSON")
        }
    }

    private static func verifySharedSubstrateFields(paths: RulesConfigPaths) {
        guard let data = try? Data(contentsOf: paths.substrateNormalizationRulesURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let shared = json["sharedSubstrate"] as? [String: Any] else {
            AppLogger.shared.error(.import, "sharedSubstrate verification: file missing or invalid", metadata: [:])
            return
        }
        let required = ["tokenSeparators", "originStandaloneTokens", "originContainsTokens",
                        "treatmentKeywords", "materialTokens", "materialAliases",
                        "materialDisplayNames", "orientationTokens", "orientationAliases", "orientationPattern"]
        for field in required {
            if shared[field] == nil {
                AppLogger.shared.error(.import, "sharedSubstrate verification: missing field", metadata: ["field": field])
            }
        }
        AppLogger.shared.info(.import, "sharedSubstrate verification: all 10 subfields present", metadata: [:])
    }

    // MARK: - Defaults (fallback if bundle file missing — should never happen in production)

    private static func defaultSampleIDData() -> Data {
        let json = #"{"version":1,"patterns":["^(PN|PT|SL)\\d+$"]}"#
        return Data(json.utf8)
    }

    private static func defaultWorkflowMatchData() -> Data {
        let json = #"{"version":1,"rules":[]}"#
        return Data(json.utf8)
    }

    private static func defaultMeasurementTagData() -> Data {
        let json = #"{"version":1,"rules":[]}"#
        return Data(json.utf8)
    }

    private static func defaultWorkflowIDPolicyData() -> Data {
        let json = #"{"version":1,"preferredAlphabet":"ABCDEFGHIJKLMNOPQRSTUVWXYZ","fallbackPrefix":"WF"}"#
        return Data(json.utf8)
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
            case .bundleFileMissing(let name): return "Bundle file missing: \(name)"
            case .verificationFailed(let name, let reason): return "Verification failed for \(name): \(reason)"
            }
        }
    }
}

