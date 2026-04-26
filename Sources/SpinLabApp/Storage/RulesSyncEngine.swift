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

    // MARK: - Startup reverse sync (s6b implements the body)

    func reverseSyncOnStartup(runtimePaths: RulesConfigPaths) -> StartupOutcome {
        guard pointer != nil else {
            logger.info(.system, "sync engine: no repo pointer, skipping reverse sync")
            return .skipped
        }
        // s6b implements full reverse sync logic
        return .healthy
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
