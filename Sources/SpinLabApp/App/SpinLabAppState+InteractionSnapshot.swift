import Foundation

extension SpinLabAppState {

    func interactionValue<Value>(_ keyPath: KeyPath<SpinLabInteractionSnapshot, Value>) -> Value {
        interactionSnapshotCoordinator.value(keyPath)
    }

    func updateInteractionValue<Value>(_ keyPath: WritableKeyPath<SpinLabInteractionSnapshot, Value>, to value: Value) {
        interactionSnapshotCoordinator.updateValue(keyPath, to: value)
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
        value: Value?
    ) {
        interactionSnapshotCoordinator.updateEntryValue(for: id, in: keyPath, value: value)
    }

    func flushInteractionSnapshotNow() {
        persistInteractionSnapshotIfReady()
        interactionSnapshotCoordinator.flushNow()
    }

    func restoreInteractionSnapshot() {
        interactionSnapshotCoordinator.restoreAll(
            selectedAreaSetter: { [weak self] in self?.selectedArea = $0 },
            inboxStore: inboxFeatureStore,
            libraryStore: libraryFeatureStore,
            workbenchStore: workbenchFeatureStore
        )
        libraryFeatureStore.normalizeLibrarySelection()
        hasRestoredInteractionSnapshot = true
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

        updateInteractionValue(\.lastSeenRoutingRuleFingerprint, to: trimmedCurrent)
    }

    func persistInteractionSnapshotIfReady() {
        interactionSnapshotCoordinator.captureAll(
            selectedArea: selectedArea,
            inboxStore: inboxFeatureStore,
            libraryStore: libraryFeatureStore,
            workbenchStore: workbenchFeatureStore
        )
    }
}
