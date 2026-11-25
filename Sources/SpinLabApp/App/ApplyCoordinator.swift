import Foundation

enum InboxApplyOutcome: Equatable {
    case nothingToApply
    case success(appliedIDs: [UUID], skippedIDs: [UUID])
    case partialSuccess(appliedIDs: [UUID], skippedIDs: [UUID], failedIDs: [UUID])
    case failure(message: String)

    var appliedIDs: [UUID] {
        switch self {
        case .nothingToApply, .failure:
            return []
        case let .success(appliedIDs, _), let .partialSuccess(appliedIDs, _, _):
            return appliedIDs
        }
    }

    var skippedIDs: [UUID] {
        switch self {
        case .nothingToApply, .failure:
            return []
        case let .success(_, skippedIDs), let .partialSuccess(_, skippedIDs, _):
            return skippedIDs
        }
    }

    var processedIDs: [UUID] {
        appliedIDs + skippedIDs
    }
}

struct ApplyCoordinator {
    struct ApplyContext {
        let pendingImports: [SpinLabDomain.PendingImport]
        let routingSnapshots: [UUID: SpinLabDomain.PendingRoutingSnapshot]
        let libraryIndex: LibraryIndex
        let libraryRootURL: URL
    }

    enum ApplyScope {
        case selected(UUID?)
        case all
    }

    struct ApplyProgressUpdate: Sendable {
        let totalCount: Int
        let processedCount: Int
        let appliedCount: Int
        let skippedCount: Int
        let failedCount: Int
        let currentFileName: String
    }

    func resolveContext(
        libraryRootURL: URL,
        pendingImports: [SpinLabDomain.PendingImport],
        routingSnapshotFor: (SpinLabDomain.PendingImport) -> SpinLabDomain.PendingRoutingSnapshot,
        libraryStore: LibraryStore
    ) -> ApplyContext {
        let routingSnapshots = Dictionary(uniqueKeysWithValues: pendingImports.map { pending in
            (pending.id, routingSnapshotFor(pending))
        })
        let libraryIndex =
            libraryStore.loadIndex(from: libraryRootURL)
            ?? libraryStore.snapshotIndexFromFilesystem(rootURL: libraryRootURL)
        return ApplyContext(
            pendingImports: pendingImports,
            routingSnapshots: routingSnapshots,
            libraryIndex: libraryIndex,
            libraryRootURL: libraryRootURL
        )
    }

    func apply(
        scope: ApplyScope,
        context: ApplyContext,
        libraryStore: LibraryStore,
        applyService: InboxArchiveApplyService,
        draftFor: (UUID) -> PendingImportConfirmationDraft? = { _ in nil },
        workflowDefinitions: [WorkflowDefinition] = [],
        onProgress: ((ApplyProgressUpdate) -> Void)? = nil
    ) async -> InboxApplyOutcome {
        let matched = matchedPending(scope: scope, context: context, draftFor: draftFor)
        guard !matched.isEmpty else {
            return .nothingToApply
        }

        var appliedIDs: [UUID] = []
        var skippedIDs: [UUID] = []
        var failedIDs: [UUID] = []
        var lastErrorMessage: String?
        appliedIDs.reserveCapacity(matched.count)
        skippedIDs.reserveCapacity(matched.count)
        failedIDs.reserveCapacity(matched.count)

        for pending in matched {
            let targets = context.routingSnapshots[pending.id]?.routePlan.targets ?? []

            do {
                let applyResult = try applyService.apply(
                    pending: pending,
                    targets: targets,
                    libraryIndex: context.libraryIndex,
                    libraryStore: libraryStore,
                    libraryRootURL: context.libraryRootURL,
                    draft: draftFor(pending.id),
                    workflowDefinitions: workflowDefinitions
                )
                if applyResult.allTargetsSkipped {
                    skippedIDs.append(pending.id)
                } else {
                    appliedIDs.append(pending.id)
                }
            } catch {
                failedIDs.append(pending.id)
                lastErrorMessage = error.localizedDescription
            }

            onProgress?(
                .init(
                    totalCount: matched.count,
                    processedCount: appliedIDs.count + skippedIDs.count + failedIDs.count,
                    appliedCount: appliedIDs.count,
                    skippedCount: skippedIDs.count,
                    failedCount: failedIDs.count,
                    currentFileName: pending.fileName
                )
            )
            await Task.yield()
        }

        if (!appliedIDs.isEmpty || !skippedIDs.isEmpty) && failedIDs.isEmpty {
            return .success(appliedIDs: appliedIDs, skippedIDs: skippedIDs)
        }
        if (!appliedIDs.isEmpty || !skippedIDs.isEmpty) && !failedIDs.isEmpty {
            return .partialSuccess(appliedIDs: appliedIDs, skippedIDs: skippedIDs, failedIDs: failedIDs)
        }
        return .failure(message: lastErrorMessage ?? "No matched pending imports could be applied.")
    }

    private func matchedPending(
        scope: ApplyScope,
        context: ApplyContext,
        draftFor: (UUID) -> PendingImportConfirmationDraft?
    ) -> [SpinLabDomain.PendingImport] {
        let isV2: Bool = {
            if case .v2 = LibraryLayoutRouter.resolve(rootURL: context.libraryRootURL) {
                return true
            }
            return false
        }()

        func isEligible(_ pending: SpinLabDomain.PendingImport) -> Bool {
            if isV2 {
                guard let draft = draftFor(pending.id),
                      let targetUID = draft.v2TargetSampleUID?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !targetUID.isEmpty else {
                    return false
                }
                return context.libraryIndex.samples.contains { sample in
                    !sample.isTrashed && (sample.sampleUID ?? sample.id) == targetUID
                }
            }
            guard let snapshot = context.routingSnapshots[pending.id] else {
                return false
            }
            return snapshot.verdict == .libraryMatched && !snapshot.routePlan.targets.isEmpty
        }

        switch scope {
        case let .selected(pendingID):
            guard let pendingID,
                  let pending = context.pendingImports.first(where: { $0.id == pendingID }),
                  isEligible(pending) else {
                return []
            }
            return [pending]
        case .all:
            return context.pendingImports.filter(isEligible)
        }
    }
}
