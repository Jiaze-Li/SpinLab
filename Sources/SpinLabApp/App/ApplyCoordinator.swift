import Foundation

enum InboxApplyOutcome: Equatable {
    case nothingToApply
    case success(appliedIDs: [UUID])
    case partialSuccess(appliedIDs: [UUID], failedIDs: [UUID])
    case failure(message: String)

    var appliedIDs: [UUID] {
        switch self {
        case .nothingToApply, .failure:
            return []
        case let .success(appliedIDs), let .partialSuccess(appliedIDs, _):
            return appliedIDs
        }
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
        applyService: InboxArchiveApplyService
    ) -> InboxApplyOutcome {
        guard let pendingID,
              let pending = pendingImports.first(where: { $0.id == pendingID }),
              let snapshot = routingSnapshots[pendingID],
              snapshot.verdict == .libraryMatched,
              !snapshot.routePlan.targets.isEmpty else {
            return .nothingToApply
        }

        do {
            try applyService.apply(
                pending: pending,
                targets: snapshot.routePlan.targets,
                libraryIndex: libraryIndex,
                libraryStore: libraryStore,
                libraryRootURL: libraryRootURL
            )
            return .success(appliedIDs: [pending.id])
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
        applyService: InboxArchiveApplyService
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
        var failedIDs: [UUID] = []

        for pending in matched {
            guard let snapshot = routingSnapshots[pending.id] else {
                failedIDs.append(pending.id)
                continue
            }
            do {
                try applyService.apply(
                    pending: pending,
                    targets: snapshot.routePlan.targets,
                    libraryIndex: libraryIndex,
                    libraryStore: libraryStore,
                    libraryRootURL: libraryRootURL
                )
                appliedIDs.append(pending.id)
            } catch {
                failedIDs.append(pending.id)
            }
        }

        if !appliedIDs.isEmpty && failedIDs.isEmpty {
            return .success(appliedIDs: appliedIDs)
        }
        if !appliedIDs.isEmpty && !failedIDs.isEmpty {
            return .partialSuccess(appliedIDs: appliedIDs, failedIDs: failedIDs)
        }
        return .failure(message: "No matched pending imports could be applied.")
    }
}
