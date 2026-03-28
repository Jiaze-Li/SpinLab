import Foundation

final class InteractionMemoryStore {
    private let persistence: SpinLabPersistence
    private let saveDebounceInterval: TimeInterval
    private var pendingSaveWorkItem: DispatchWorkItem?

    private(set) var snapshot: SpinLabInteractionSnapshot = SpinLabInteractionSnapshot()
    private(set) var isRestoring = false
    private(set) var isReady = false

    init(persistence: SpinLabPersistence, saveDebounceInterval: TimeInterval = 0.35) {
        self.persistence = persistence
        self.saveDebounceInterval = saveDebounceInterval
    }

    deinit {
        flushNow()
    }

    func restore(_ apply: (inout SpinLabInteractionSnapshot) -> Void) {
        isRestoring = true
        snapshot = persistence.loadInteractionSnapshot()
        apply(&snapshot)
        isRestoring = false
    }

    func markReady() {
        isReady = true
    }

    func captureIfReady(_ capture: (inout SpinLabInteractionSnapshot) -> Void) {
        guard isReady, !isRestoring else {
            return
        }
        capture(&snapshot)
        scheduleSave()
    }

    func value<Value>(_ keyPath: KeyPath<SpinLabInteractionSnapshot, Value>) -> Value {
        snapshot[keyPath: keyPath]
    }

    func updateValue<Value>(_ keyPath: WritableKeyPath<SpinLabInteractionSnapshot, Value>, to value: Value) {
        snapshot[keyPath: keyPath] = value
        scheduleSaveIfReady()
    }

    func entryValue<Value>(
        for key: String,
        in keyPath: KeyPath<SpinLabInteractionSnapshot, [String: Value]>
    ) -> Value? {
        snapshot[keyPath: keyPath][key]
    }

    func updateEntryValue<Value>(
        for key: String,
        in keyPath: WritableKeyPath<SpinLabInteractionSnapshot, [String: Value]>,
        value: Value?
    ) {
        if let value {
            snapshot[keyPath: keyPath][key] = value
        } else {
            snapshot[keyPath: keyPath].removeValue(forKey: key)
        }
        scheduleSaveIfReady()
    }

    func mutateSnapshot(_ mutate: (inout SpinLabInteractionSnapshot) -> Void) {
        mutate(&snapshot)
        scheduleSaveIfReady()
    }

    private func scheduleSaveIfReady() {
        guard isReady, !isRestoring else {
            return
        }
        scheduleSave()
    }

    private func scheduleSave() {
        pendingSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushNow()
        }
        pendingSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounceInterval, execute: workItem)
    }

    func flushNow() {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        guard isReady, !isRestoring else {
            return
        }
        persistence.saveInteractionSnapshot(snapshot)
    }
}
