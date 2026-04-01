import Foundation

struct InboxArchiveApplyResult: Equatable {
    var copiedTargetCount: Int
    var skippedExistingTargetCount: Int

    var allTargetsSkipped: Bool {
        copiedTargetCount == 0 && skippedExistingTargetCount > 0
    }
}

struct InboxArchiveApplyService {
    enum InboxArchiveApplyError: LocalizedError {
        case sourceFileNotFound
        case drawerNotFound(sampleId: String, candidates: Int)
        case commitFailed(sampleId: String, underlying: AppError)

        var errorDescription: String? {
            switch self {
            case .sourceFileNotFound:
                return "Pending source file does not exist."
            case let .drawerNotFound(sampleId, candidates):
                return "Drawer not found — key: \(sampleId), matched \(candidates) candidate(s)."
            case let .commitFailed(sampleId, underlying):
                return "Failed to copy file for sample \(sampleId): \(underlying.localizedDescription)"
            }
        }
    }

    func apply(
        pending: SpinLabDomain.PendingImport,
        targets: [SpinLabDomain.RouteTarget],
        libraryIndex: LibraryIndex,
        libraryStore: LibraryStore,
        libraryRootURL: URL
    ) throws -> InboxArchiveApplyResult {
        let sourceURL = URL(fileURLWithPath: pending.sourceFilePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw InboxArchiveApplyError.sourceFileNotFound
        }

        let samplesByID = Dictionary(uniqueKeysWithValues: libraryIndex.samples.map { ($0.id, $0) })
        var transaction = LibraryWriteTransaction()
        var copiedTargetCount = 0
        var skippedExistingTargetCount = 0

        do {
            for target in targets {
                guard let sample = samplesByID[target.sampleId] else {
                    throw InboxArchiveApplyError.drawerNotFound(sampleId: target.sampleId, candidates: 0)
                }

                let drawerRoot = libraryStore.drawerRootURL(for: sample, rootURL: libraryRootURL)
                guard FileManager.default.fileExists(atPath: drawerRoot.path) else {
                    throw InboxArchiveApplyError.drawerNotFound(sampleId: target.sampleId, candidates: 0)
                }
                let destinationDirectory = drawerRoot.appending(
                    path: destinationSubpath(workflowName: pending.parsedHints.workflowName),
                    directoryHint: .isDirectory
                )
                let destinationURL = destinationDirectory.appending(
                    path: sourceURL.lastPathComponent,
                    directoryHint: .notDirectory
                )
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    skippedExistingTargetCount += 1
                    continue
                }
                try transaction.prepare(sourceURL: sourceURL, destinationURL: destinationURL)
                copiedTargetCount += 1
            }

            if copiedTargetCount > 0 {
                try transaction.commit()
            }

            return InboxArchiveApplyResult(
                copiedTargetCount: copiedTargetCount,
                skippedExistingTargetCount: skippedExistingTargetCount
            )
        } catch let error as InboxArchiveApplyError {
            try? transaction.rollback()
            throw error
        } catch {
            try? transaction.rollback()
            throw InboxArchiveApplyError.commitFailed(
                sampleId: targets.first?.sampleId ?? "unknown",
                underlying: AppError.from(error, fallback: "Failed to commit file writes.")
            )
        }
    }

    private func destinationSubpath(workflowName: String?) -> String {
        let sanitized = workflowName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "_")
        if let workflow = sanitized, !workflow.isEmpty {
            return "measurements/\(workflow)"
        }
        return "measurements/General"
    }
}
