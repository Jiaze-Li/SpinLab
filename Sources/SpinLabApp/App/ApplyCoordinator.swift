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
    func applySelected(
        pendingID: UUID?,
        pendingImports: [SpinLabDomain.PendingImport],
        routingSnapshots: [UUID: SpinLabDomain.PendingRoutingSnapshot],
        libraryIndex: LibraryIndex,
        libraryStore: LibraryStore,
        libraryRootURL: URL,
        applyService: InboxArchiveApplyService,
        draftFor: (UUID) -> PendingImportConfirmationDraft? = { _ in nil },
        workflowDefinitions: [WorkflowDefinition] = []
    ) -> InboxApplyOutcome {
        guard let pendingID,
              let pending = pendingImports.first(where: { $0.id == pendingID }),
              let snapshot = routingSnapshots[pendingID],
              snapshot.verdict == .libraryMatched,
              !snapshot.routePlan.targets.isEmpty else {
            return .nothingToApply
        }

        do {
            let applyResult = try applyService.apply(
                pending: pending,
                targets: snapshot.routePlan.targets,
                libraryIndex: libraryIndex,
                libraryStore: libraryStore,
                libraryRootURL: libraryRootURL,
                draft: draftFor(pending.id),
                workflowDefinitions: workflowDefinitions
            )
            if applyResult.allTargetsSkipped {
                return .success(appliedIDs: [], skippedIDs: [pending.id])
            }
            return .success(appliedIDs: [pending.id], skippedIDs: [])
        } catch {
            return .failure(message: AppError.from(error, fallback: "Apply failed.").localizedDescription)
        }
    }

    func applyAll(
        pendingImports: [SpinLabDomain.PendingImport],
        routingSnapshots: [UUID: SpinLabDomain.PendingRoutingSnapshot],
        libraryIndex: LibraryIndex,
        libraryStore: LibraryStore,
        libraryRootURL: URL,
        applyService: InboxArchiveApplyService,
        draftFor: (UUID) -> PendingImportConfirmationDraft? = { _ in nil },
        workflowDefinitions: [WorkflowDefinition] = []
    ) -> InboxApplyOutcome {
        let matched = pendingImports.filter { pending in
            guard let snapshot = routingSnapshots[pending.id] else {
                return false
            }
            return snapshot.verdict == .libraryMatched && !snapshot.routePlan.targets.isEmpty
        }
        guard !matched.isEmpty else {
            return .nothingToApply
        }

        var appliedIDs: [UUID] = []
        var skippedIDs: [UUID] = []
        var failedIDs: [UUID] = []
        appliedIDs.reserveCapacity(matched.count)
        skippedIDs.reserveCapacity(matched.count)
        failedIDs.reserveCapacity(matched.count)

        for pending in matched {
            guard let snapshot = routingSnapshots[pending.id] else {
                failedIDs.append(pending.id)
                continue
            }
            do {
                let applyResult = try applyService.apply(
                    pending: pending,
                    targets: snapshot.routePlan.targets,
                    libraryIndex: libraryIndex,
                    libraryStore: libraryStore,
                    libraryRootURL: libraryRootURL,
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
            }
        }

        if (!appliedIDs.isEmpty || !skippedIDs.isEmpty) && failedIDs.isEmpty {
            return .success(appliedIDs: appliedIDs, skippedIDs: skippedIDs)
        }
        if (!appliedIDs.isEmpty || !skippedIDs.isEmpty) && !failedIDs.isEmpty {
            return .partialSuccess(appliedIDs: appliedIDs, skippedIDs: skippedIDs, failedIDs: failedIDs)
        }
        return .failure(message: "No matched pending imports could be applied.")
    }
}
