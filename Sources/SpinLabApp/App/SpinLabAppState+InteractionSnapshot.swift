import Foundation

extension SpinLabAppState {

    func interactionValue<Value>(_ keyPath: KeyPath<SpinLabInteractionSnapshot, Value>) -> Value {
        interactionSnapshotCoordinator.value(keyPath)
    }

    func updateInteractionValue<Value>(
        _ keyPath: WritableKeyPath<SpinLabInteractionSnapshot, Value>,
        to value: Value,
        source: String = "unspecified"
    ) {
        interactionSnapshotCoordinator.updateValue(keyPath, to: value, source: source)
    }

    func interactionEntryValue<Value>(
        for id: UUID,
        in keyPath: KeyPath<SpinLabInteractionSnapshot, [String: Value]>
    ) -> Value? {
        interactionSnapshotCoordinator.entryValue(for: id, in: keyPath)
    }

    func updateInteractionEntryValue<Value>(
        for id: UUID,
        in keyPath: WritableKeyPath<SpinLabInteractionSnapshot, [String: Value]>,
        value: Value?,
        source: String = "unspecified"
    ) {
        interactionSnapshotCoordinator.updateEntryValue(for: id, in: keyPath, value: value, source: source)
    }

    /// Requests a snapshot flush. Multiple requests within the same run-loop tick collapse into
    /// a single write (the pending flag below). During `restoreInteractionSnapshot()` the request
    /// is instead skipped/merged by the coordinator's suppress guard — see `InteractionMemoryStore`.
    func flushInteractionSnapshotNow(source: String = "unspecified") {
        print("[PERF][snapshot] request source=\(source)")
        guard !isInteractionSnapshotFlushPending else {
            print("[PERF][snapshot] skipped no-op source=\(source)")
            return
        }
        isInteractionSnapshotFlushPending = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.isInteractionSnapshotFlushPending = false
            self.persistInteractionSnapshotIfReady(source: source)
            self.interactionSnapshotCoordinator.flushNow(source: source)
        }
    }

    func restoreInteractionSnapshot() {
        interactionSnapshotCoordinator.beginSuppressingFlush()
        interactionSnapshotCoordinator.restoreAll(
            selectedAreaSetter: { [weak self] in self?.selectedArea = $0 },
            inboxStore: inboxFeatureStore,
            libraryStore: libraryFeatureStore,
            workbenchStore: workbenchFeatureStore
        )
        libraryFeatureStore.normalizeLibrarySelection()
        hasRestoredInteractionSnapshot = true
        interactionSnapshotCoordinator.endSuppressingFlush(source: "restoreInteractionSnapshot")
    }

    func notifyIfRoutingRulesChanged() {
        let currentFingerprint = inboxFeatureStore.routingRuleFingerprint
        let trimmedCurrent = currentFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCurrent.isEmpty, trimmedCurrent != "unknown" else {
            return
        }

        let previousFingerprint = interactionValue(\.lastSeenRoutingRuleFingerprint)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let previousFingerprint,
           !previousFingerprint.isEmpty,
           previousFingerprint != trimmedCurrent {
            presentAlert(
                title: "Rules Updated",
                message: "Routing rules changed since last run. Please run Library Sync Registry and Apply All to rebuild existing drawer samples."
            )
        }

        updateInteractionValue(\.lastSeenRoutingRuleFingerprint, to: trimmedCurrent, source: "routingRuleFingerprint")
    }

    func persistInteractionSnapshotIfReady(source: String = "unspecified") {
        interactionSnapshotCoordinator.captureAll(
            selectedArea: selectedArea,
            inboxStore: inboxFeatureStore,
            libraryStore: libraryFeatureStore,
            workbenchStore: workbenchFeatureStore,
            source: source
        )
    }
}
