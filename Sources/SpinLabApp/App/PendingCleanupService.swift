import Foundation

struct PendingCleanupService {
    @MainActor
    func clearImports(
        inboxStore: InboxFeatureStore,
        writeInboxWorkspace: ([String: InboxPendingWorkspaceState]) -> Void,
        persistInteractionSnapshotIfReady: () -> Void
    ) {
        // Keep queue/state cleanup atomic at feature boundary:
        // 1) pending imports + routing cache in store
        // 2) interaction workspace snapshots in app state
        inboxStore.clearPendingImports()
        writeInboxWorkspace([:])
        persistInteractionSnapshotIfReady()
    }
}
