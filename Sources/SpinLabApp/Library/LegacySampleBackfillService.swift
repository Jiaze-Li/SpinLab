import Foundation

/// One-time, in-place issue of permanent `smp_` identities to samples created before the unified rule.
/// Only `sampleUID` and `legacySampleKey` are added to each `sample.json`; ids, folders, measurements
/// and plots are never moved.
struct LegacySampleBackfillService {
    struct Plan: Equatable {
        struct Item: Equatable {
            let sampleId: String
            let batchId: String
            let legacySampleKey: String
        }
        var pending: [Item]
        var alreadyIssued: Int
    }

    struct Report: Equatable {
        var dryRun: Bool
        var pending: [Plan.Item]
        var issued: Int
        var skippedAlreadyIssued: Int
        var failures: [String]
        var backupDirectory: URL?
        var indexRebuilds: Int
        var missingAfterwards: [String]
        var succeeded: Bool { failures.isEmpty && missingAfterwards.isEmpty }
    }

    enum BackfillError: LocalizedError, Equatable {
        case unreadableLibrary(String)
        case backupFailed(String)
        case alreadyRunning

        var errorDescription: String? {
            switch self {
            case let .unreadableLibrary(reason): return "Library could not be read completely: \(reason). Nothing was changed."
            case let .backupFailed(reason): return "Backup failed: \(reason). Nothing was changed."
            case .alreadyRunning: return "Another ID backfill is already running on this library. Nothing was changed."
            }
        }
    }

    /// Failure-injection / observation points for tests. Production leaves them at their defaults.
    struct Hooks {
        var beforeBackup: () throws -> Void = {}
        var beforeSampleWrite: (LibrarySample) throws -> Void = { _ in }
        var onIndexRebuild: () -> Void = {}
    }

    var hooks = Hooks()
    var now: () -> Date = Date.init

    func plan(libraryStore: LibraryStore, rootURL: URL) throws -> Plan {
        let index: LibraryIndex
        do { index = try libraryStore.readOnlyCompleteIndex(rootURL: rootURL) } catch {
            throw BackfillError.unreadableLibrary(error.localizedDescription)
        }
        return Self.plan(for: index)
    }

    static func plan(for index: LibraryIndex) -> Plan {
        var pending: [Plan.Item] = []
        var issued = 0
        for sample in index.samples {
            if case .alreadyIssued = SampleIDIssuer.issueForLegacyBackfill(sample: sample) {
                issued += 1
            } else {
                pending.append(.init(sampleId: sample.id, batchId: sample.batchId, legacySampleKey: SampleLegacyKeyMapping.legacyKey(of: sample)))
            }
        }
        return Plan(pending: pending, alreadyIssued: issued)
    }

    func run(libraryStore: LibraryStore, rootURL: URL, dryRun: Bool, settings: LibrarySettings? = nil) throws -> Report {
        // A real run is exclusive per library: two runs would each pick a different random ID and could
        // overwrite one another between the re-read and the write. The lock is released when the run ends
        // (or the process dies), so it can never stay stuck.
        guard !dryRun else { return try runLocked(libraryStore: libraryStore, rootURL: rootURL, dryRun: true) }
        try LibraryWriteLease.shared.ensureWritable(rootURL)
        let lockPath = rootURL.appending(path: "_smp_backfill.lock").path
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            throw BackfillError.backupFailed("could not create the backfill lock file: \(String(cString: strerror(errno)))")
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(fd)
            if code == EWOULDBLOCK || code == EAGAIN { throw BackfillError.alreadyRunning }
            throw BackfillError.backupFailed("could not lock the library for backfill: \(String(cString: strerror(code)))")
        }
        defer { flock(fd, LOCK_UN); close(fd) }
        return try runLocked(libraryStore: libraryStore, rootURL: rootURL, dryRun: false)
    }

    private func runLocked(libraryStore: LibraryStore, rootURL: URL, dryRun: Bool) throws -> Report {
        let index: LibraryIndex
        do { index = try libraryStore.readOnlyCompleteIndex(rootURL: rootURL) } catch {
            throw BackfillError.unreadableLibrary(error.localizedDescription)
        }
        let plan = Self.plan(for: index)
        var report = Report(dryRun: dryRun, pending: plan.pending, issued: 0, skippedAlreadyIssued: plan.alreadyIssued,
                            failures: [], backupDirectory: nil, indexRebuilds: 0, missingAfterwards: [])
        if dryRun || plan.pending.isEmpty { return report }

        // 1. Backup first; any failure aborts before a single sample is touched.
        let backupDir: URL
        do {
            try hooks.beforeBackup()
            backupDir = try makeBackup(libraryStore: libraryStore, rootURL: rootURL, index: index, items: plan.pending)
        } catch {
            throw BackfillError.backupFailed(error.localizedDescription)
        }
        report.backupDirectory = backupDir

        // 2. Issue per sample, replacing sample.json atomically. A UID counts as issued only after its write succeeded.
        let pendingIDs = Set(plan.pending.map(\.sampleId))
        for sample in index.samples where pendingIDs.contains(sample.id) {
            guard case let .issued(uid) = SampleIDIssuer.issueForLegacyBackfill(sample: sample) else { continue }
            let sampleURL = libraryStore.sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
            do {
                try hooks.beforeSampleWrite(sample)
                // Re-read the file itself so nothing else in sample.json is lost.
                guard var onDisk = libraryStore.decodeSample(from: sampleURL.appending(path: "sample.json")) else {
                    throw NSError(domain: "SpinLab.Backfill", code: 1, userInfo: [NSLocalizedDescriptionKey: "sample.json unreadable"])
                }
                // Another run may have issued an ID since the plan was read: never overwrite a valid one.
                if SampleIdentityRule.isValidUID(onDisk.sampleUID ?? "") {
                    report.skippedAlreadyIssued += 1
                    continue
                }
                onDisk.legacySampleKey = SampleLegacyKeyMapping.legacyKey(of: onDisk)
                onDisk.sampleUID = uid
                try libraryStore.writeSampleChecked(onDisk, to: sampleURL)
                report.issued += 1
            } catch {
                report.failures.append("\(sample.id): \(error.localizedDescription)")
            }
        }

        // 3. One index rebuild for the whole run.
        hooks.onIndexRebuild()
        report.indexRebuilds += 1
        let rebuilt: LibraryIndex
        do {
            rebuilt = try libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        } catch {
            report.failures.append("index rebuild: \(error.localizedDescription)")
            return report
        }

        // 4. Completeness check over the whole library.
        report.missingAfterwards = rebuilt.samples
            .filter { !SampleIdentityRule.isValidUID($0.sampleUID ?? "") }
            .map(\.id)
        return report
    }

    private func makeBackup(libraryStore: LibraryStore, rootURL: URL, index: LibraryIndex, items: [Plan.Item]) throws -> URL {
        let fm = libraryStore.fileManager
        let stamp = ISO8601DateFormatter().string(from: now()).replacingOccurrences(of: ":", with: "-")
        let dir = rootURL.appending(path: "_smp_backfill_backups", directoryHint: .isDirectory)
            .appending(path: "\(stamp)-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let indexURL = libraryStore.indexFileURL(rootURL)
        if fm.fileExists(atPath: indexURL.path) {
            try fm.copyItem(at: indexURL, to: dir.appending(path: "library_index.json"))
        }
        for item in items {
            let src = libraryStore.sampleDirectoryURL(rootURL, batchID: item.batchId, sampleKey: item.sampleId)
                .appending(path: "sample.json")
            let dst = dir.appending(path: "samples", directoryHint: .isDirectory)
                .appending(path: libraryStore.sanitizedPathComponent(item.batchId), directoryHint: .isDirectory)
                .appending(path: item.sampleId, directoryHint: .isDirectory)
            try fm.createDirectory(at: dst, withIntermediateDirectories: true)
            try fm.copyItem(at: src, to: dst.appending(path: "sample.json"))
            guard fm.contentsEqual(atPath: src.path, andPath: dst.appending(path: "sample.json").path) else {
                throw NSError(domain: "SpinLab.Backfill", code: 2, userInfo: [NSLocalizedDescriptionKey: "backup copy of \(item.sampleId) does not match"])
            }
        }
        return dir
    }
}
