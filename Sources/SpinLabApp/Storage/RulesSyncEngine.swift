import CryptoKit
import Foundation

// MARK: - Outcomes

enum DualWriteOutcome: Sendable, Equatable {
    case runtimeOnly
    case mirrored
    case mirrorFailedRuntimeOk(reason: String)
}

enum StartupOutcome: Sendable, Equatable {
    case healthy
    case skipped
    case degraded(failedFiles: Set<String>, reason: String)
}

// MARK: - Engine

struct RulesSyncEngine {
    let pointer: RepositoryPointer?
    let atomicWriter: AtomicFileWritingCapability
    let logger: AppLogger
    let testOverrideMirrorURL: URL?

    init(
        pointer: RepositoryPointer?,
        atomicWriter: AtomicFileWritingCapability = AtomicFileWriter(),
        logger: AppLogger = .shared,
        testOverrideMirrorURL: URL? = nil
    ) {
        self.pointer = pointer
        self.atomicWriter = atomicWriter
        self.logger = logger
        self.testOverrideMirrorURL = testOverrideMirrorURL
    }

    // MARK: - Dual write

    func dualWrite(runtimeURL: URL, data: Data, sectionLabel: String) throws -> DualWriteOutcome {
        // Step 1: backup runtime — error level on failure, non-blocking (H4)
        backupFile(at: runtimeURL, logLevel: .error)

        // Step 2: runtime write — throws on failure
        try atomicWriter.write(data, to: runtimeURL)

        // Step 3: resolve mirror directory — nil means skip
        guard let mirrorDir = resolvedMirrorDirectory() else {
            return .runtimeOnly
        }
        let mirrorURL = mirrorDir.appendingPathComponent(runtimeURL.lastPathComponent)

        // Step 4: create mirror parent directory — failure → .mirrorFailedRuntimeOk (M5)
        do {
            try FileManager.default.createDirectory(at: mirrorDir, withIntermediateDirectories: true)
        } catch {
            logger.error(.system, "sync engine: mirror parent creation failed for \(sectionLabel)",
                         metadata: ["reason": error.localizedDescription])
            return .mirrorFailedRuntimeOk(reason: "create parent failed: \(error.localizedDescription)")
        }

        // Step 5: backup mirror — warning level on failure, non-blocking
        backupFile(at: mirrorURL, logLevel: .warning)

        // Step 6: mirror write — failure → .mirrorFailedRuntimeOk
        do {
            try atomicWriter.write(data, to: mirrorURL)
        } catch {
            logger.error(.system, "sync engine: mirror write failed for \(sectionLabel)",
                         metadata: ["reason": error.localizedDescription])
            return .mirrorFailedRuntimeOk(reason: error.localizedDescription)
        }

        return .mirrored
    }

    // MARK: - Startup reverse sync

    func reverseSyncOnStartup(runtimePaths: RulesConfigPaths) -> StartupOutcome {
        guard let pointer else {
            logger.info(.system, "sync engine: no repo pointer, skipping reverse sync")
            return .skipped
        }

        let fileMappings: [(runtimeURL: URL, filename: String, kind: SchemaKind)] = [
            (runtimePaths.importFiltersURL, "import_filters.json", .importFilters),
            (runtimePaths.filenameTokenizationURL, "filename_tokenization.json", .filenameTokenization),
            (runtimePaths.sampleIdentificationURL, "sample_identification.json", .sampleIdentification),
            (runtimePaths.workflowURL, "workflow.json", .workflow),
            (runtimePaths.measuringConditionURL, "measuring_condition.json", .measuringCondition)
        ]

        var degradedFiles: Set<String> = []

        for mapping in fileMappings {
            let mirrorURL = pointer.repositoryConfigDir.appendingPathComponent(mapping.filename)

            guard let mirrorData = try? Data(contentsOf: mirrorURL) else {
                logger.error(.system, "sync engine: cannot read mirror file",
                             metadata: ["errorTaxonomy": "read_failed", "file": mapping.filename])
                degradedFiles.insert(mapping.filename)
                continue
            }

            // H5: decode check before accepting mirror as authority
            guard mapping.kind.canDecode(mirrorData) else {
                logger.error(.system, "sync engine: mirror schema decode failed",
                             metadata: ["errorTaxonomy": "decode_failed", "file": mapping.filename])
                degradedFiles.insert(mapping.filename)
                continue
            }

            let mirrorHash = sha256Hex(of: mirrorData)
            let runtimeData = try? Data(contentsOf: mapping.runtimeURL)
            if let runtimeData, sha256Hex(of: runtimeData) == mirrorHash {
                continue  // already consistent
            }

            // Backup existing runtime before overwriting
            backupFile(at: mapping.runtimeURL, logLevel: .warning)

            do {
                try atomicWriter.write(mirrorData, to: mapping.runtimeURL)
                logger.info(.system, "sync engine: reverse sync updated \(mapping.filename) from repository mirror")
            } catch {
                logger.error(.system, "sync engine: runtime write failed during reverse sync",
                             metadata: ["errorTaxonomy": "write_failed", "file": mapping.filename,
                                        "reason": error.localizedDescription])
                degradedFiles.insert(mapping.filename)
            }
        }

        // Full validation via RuleLoader (C1/C5/Fix-5)
        let loadResult = RuleLoader.shared.load()
        let isFallback = loadResult.metadata.sourceLabel == "Fallback"
        let hasWarnings = !loadResult.warnings.isEmpty

        if !degradedFiles.isEmpty || isFallback || hasWarnings {
            let reason: String
            if isFallback {
                reason = "RuleLoader fell back to builtin"
            } else if hasWarnings {
                reason = loadResult.warnings.first ?? "validation warnings"
            } else {
                reason = "sync write errors"
            }
            logger.error(.system, "sync engine: startup degraded after reverse sync",
                         metadata: ["failedFiles": degradedFiles.sorted().joined(separator: ","),
                                    "reason": reason])
            return .degraded(failedFiles: degradedFiles, reason: reason)
        }

        return .healthy
    }

    // MARK: - Private: schema decode check

    private enum SchemaKind {
        case importFilters, filenameTokenization, sampleIdentification, workflow, measuringCondition

        func canDecode(_ data: Data) -> Bool {
            let decoder = JSONDecoder()
            switch self {
            case .importFilters:
                return (try? decoder.decode(ImportFiltersFileDraft.self, from: data)) != nil
            case .filenameTokenization:
                return (try? decoder.decode(FilenameTokenizationFileDraft.self, from: data)) != nil
            case .sampleIdentification:
                return (try? decoder.decode(SampleIdentificationFileDraft.self, from: data)) != nil
            case .workflow:
                return (try? decoder.decode(WorkflowFileDraft.self, from: data)) != nil
            case .measuringCondition:
                return (try? decoder.decode(MeasuringConditionFileDraft.self, from: data)) != nil
            }
        }
    }

    private func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private helpers

    private func resolvedMirrorDirectory() -> URL? {
        // Test override bypasses both isRunningTests() guard and pointer lookup
        if let override = testOverrideMirrorURL {
            return override
        }
        // Tests without an explicit override always skip mirror (M3)
        if RulesConfigPaths.isRunningTests() {
            return nil
        }
        return pointer?.repositoryConfigDir
    }

    private enum BackupLogLevel { case error, warning }

    private func backupFile(at url: URL, logLevel: BackupLogLevel) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let backupURL = url.appendingPathExtension("backup")
        do {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.copyItem(at: url, to: backupURL)
        } catch {
            switch logLevel {
            case .error:
                logger.error(.system, "sync engine: backup failed", metadata: ["reason": error.localizedDescription])
            case .warning:
                logger.warning(.system, "sync engine: backup failed", metadata: ["reason": error.localizedDescription])
            }
        }
    }
}
