import Foundation

final class InteractionMemoryStore {
    private let persistence: SpinLabPersistence
    private let saveDebounceInterval: TimeInterval
    private var pendingSaveWorkItem: DispatchWorkItem?

    private(set) var snapshot: SpinLabInteractionSnapshot = SpinLabInteractionSnapshot()
    private(set) var isRestoring = false
    private(set) var isReady = false

    /// Set for the duration of `InteractionSnapshotCoordinator.restoreAll` (and any caller-defined
    /// extension of that window). While true, every save request is skipped and merged into a
    /// single deferred flush performed by `endSuppressingFlush`.
    private(set) var isSuppressingFlush = false
    private var hasPendingSuppressedSave = false

    /// The snapshot as last written to disk. Used to skip no-op saves (state re-captured
    /// unchanged after restore, or after a render that didn't actually change anything).
    private var lastPersistedSnapshot: SpinLabInteractionSnapshot?

    init(persistence: SpinLabPersistence, saveDebounceInterval: TimeInterval = 0.35) {
        self.persistence = persistence
        self.saveDebounceInterval = saveDebounceInterval
    }

    deinit {
        flushNow(source: "deinit")
    }

    func restore(_ apply: (inout SpinLabInteractionSnapshot) -> Void) {
        isRestoring = true
        snapshot = persistence.loadInteractionSnapshot()
        lastPersistedSnapshot = snapshot
        apply(&snapshot)
        isRestoring = false
    }

    func markReady() {
        isReady = true
    }

    func beginSuppressingFlush() {
        isSuppressingFlush = true
    }

    func endSuppressingFlush(source: String) {
        isSuppressingFlush = false
        guard hasPendingSuppressedSave else { return }
        hasPendingSuppressedSave = false
        flushNow(source: source)
    }

    func captureIfReady(source: String, _ capture: (inout SpinLabInteractionSnapshot) -> Void) {
        guard isReady, !isRestoring else {
            print("[PERF][snapshot] skipped restore source=\(source)")
            return
        }
        capture(&snapshot)
        scheduleSave(source: source)
    }

    func value<Value>(_ keyPath: KeyPath<SpinLabInteractionSnapshot, Value>) -> Value {
        snapshot[keyPath: keyPath]
    }

    func updateValue<Value>(_ keyPath: WritableKeyPath<SpinLabInteractionSnapshot, Value>, to value: Value, source: String) {
        snapshot[keyPath: keyPath] = value
        scheduleSaveIfReady(source: source)
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
        value: Value?,
        source: String
    ) {
        if let value {
            snapshot[keyPath: keyPath][key] = value
        } else {
            snapshot[keyPath: keyPath].removeValue(forKey: key)
        }
        scheduleSaveIfReady(source: source)
    }

    func mutateSnapshot(source: String, _ mutate: (inout SpinLabInteractionSnapshot) -> Void) {
        mutate(&snapshot)
        scheduleSaveIfReady(source: source)
    }

    private func scheduleSaveIfReady(source: String) {
        guard isReady, !isRestoring else {
            print("[PERF][snapshot] skipped restore source=\(source)")
            return
        }
        scheduleSave(source: source)
    }

    private func scheduleSave(source: String) {
        print("[PERF][snapshot] request source=\(source)")

        if isSuppressingFlush {
            print("[PERF][snapshot] skipped restore source=\(source)")
            hasPendingSuppressedSave = true
            return
        }

        if snapshot == lastPersistedSnapshot {
            print("[PERF][snapshot] skipped no-op source=\(source)")
            return
        }

        pendingSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushNow(source: source)
        }
        pendingSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounceInterval, execute: workItem)
    }

    func flushNow(source: String) {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        guard isReady, !isRestoring else {
            print("[PERF][snapshot] skipped restore source=\(source)")
            return
        }
        if isSuppressingFlush {
            print("[PERF][snapshot] skipped restore source=\(source)")
            hasPendingSuppressedSave = true
            return
        }
        guard snapshot != lastPersistedSnapshot else {
            print("[PERF][snapshot] skipped no-op source=\(source)")
            return
        }
        persistence.saveInteractionSnapshot(snapshot)
        lastPersistedSnapshot = snapshot
        print("[PERF][snapshot] committed source=\(source)")
    }
}
