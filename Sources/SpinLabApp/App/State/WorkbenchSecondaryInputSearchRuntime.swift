import Foundation

/// Runtime that owns session state for secondary-input search slots.
///
/// Each slot represents an independent search channel (query, results, running flag,
/// message, popover visibility) that is orthogonal to WorkbenchMainSearchRuntime
/// and must never appear in WorkbenchSearchSnapshot or WorkbenchSelectionRuntime.
///
/// Gate 7.3 Step 2 registers one slot:
///   - id: "rt"  |  display label: "RT / Rxx(T)"  (3ω room-temperature input)
///
/// selectedRTHit remains workflow-owned (ThreeOmegaWorkspaceStore) for this step.
@MainActor
@Observable
final class WorkbenchSecondaryInputSearchRuntime {

    // MARK: - Slot declaration

    struct Slot {
        let id: String
        let displayLabel: String
    }

    static let rtSlotID = "rt"
    static let rtSlot   = Slot(id: rtSlotID, displayLabel: "RT / Rxx(T)")

    // MARK: - Dependencies

    private unowned let store: WorkbenchFeatureStore
    private let dataActor: any SpinLabDataActing

    // MARK: - Per-slot state

    private var queries:       [String: String]                              = [:]
    private var resultSets:    [String: [WorkflowMeasurementSearchHit]]      = [:]
    private var running:       [String: Bool]                                = [:]
    private var messages:      [String: String]                              = [:]
    private var popoverVisible:[String: Bool]                                = [:]

    @ObservationIgnored private var searchTask: Task<Void, Never>?

    // MARK: - Init

    init(store: WorkbenchFeatureStore, dataActor: any SpinLabDataActing) {
        self.store = store
        self.dataActor = dataActor
        // Restore persisted RT query so the slot is warm on first use.
        let saved = UserDefaults.standard.string(
            forKey: ThreeOmegaWorkspaceStore.rtQueryDefaultsKey
        ) ?? ""
        queries[Self.rtSlotID] = saved
    }

    // MARK: - Accessors

    func query(forSlot id: String) -> String {
        queries[id] ?? ""
    }

    func setQuery(_ text: String, forSlot id: String) {
        queries[id] = text
    }

    func results(forSlot id: String) -> [WorkflowMeasurementSearchHit] {
        resultSets[id] ?? []
    }

    func setResults(_ newResults: [WorkflowMeasurementSearchHit], forSlot id: String) {
        resultSets[id] = newResults
    }

    func isSearching(forSlot id: String) -> Bool {
        running[id] ?? false
    }

    func message(forSlot id: String) -> String? {
        messages[id]
    }

    func isPopoverVisible(forSlot id: String) -> Bool {
        popoverVisible[id] ?? false
    }

    func setPopoverVisible(_ visible: Bool, forSlot id: String) {
        popoverVisible[id] = visible
    }

    func setIsSearching(_ value: Bool, forSlot id: String) {
        running[id] = value
    }

    func setMessage(_ msg: String?, forSlot id: String) {
        if let msg { messages[id] = msg } else { messages.removeValue(forKey: id) }
    }

    // MARK: - Search

    /// Runs a search for the given slot. All state mutations are contained within this runtime.
    func runSearch(
        forSlot id: String,
        libraryRootPath: String?,
        librarySettings: LibrarySettings? = nil
    ) {
        let query = self.query(forSlot: id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            setResults([], forSlot: id)
            messages[id] = "Enter RT search query."
            running[id] = false
            return
        }
        guard let rootPath = libraryRootPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rootPath.isEmpty else {
            setResults([], forSlot: id)
            messages[id] = "Set Library Root before searching."
            running[id] = false
            return
        }

        running[id] = true
        messages.removeValue(forKey: id)
        setResults([], forSlot: id)
        setPopoverVisible(true, forSlot: id)

        searchTask?.cancel()
        let workflowDefinitions = store.workflowDefinitions
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let settings = librarySettings ?? LibrarySettings(
                    rootPath: rootPath,
                    rootBookmarkData: nil,
                    registryInternalPath: nil,
                    registrySourcePath: nil,
                    backupPath: nil,
                    backupLastSyncedAt: nil,
                    allowedBatchPrefixes: [],
                    lastRefreshAt: nil
                )
                let result = try await dataActor.searchWorkflowMeasurements(
                    settings: settings,
                    query: WorkflowSearchQuery(rawText: query),
                    workflowDefinitions: workflowDefinitions
                )
                guard !Task.isCancelled else { return }
                setResults(result, forSlot: id)
                messages[id] = result.isEmpty
                    ? "No files matched: \(query)"
                    : "Found \(result.count) file(s)."
                running[id] = false
            } catch is CancellationError {
                running[id] = false
            } catch {
                setResults([], forSlot: id)
                messages[id] = "Search failed."
                running[id] = false
            }
        }
    }

    // MARK: - Clear

    /// Clears all session state for the slot.
    /// Does NOT touch selectedRTHit (workflow-owned), main search, or SelectionRuntime.
    func clearSlot(_ id: String) {
        searchTask?.cancel()
        searchTask = nil
        queries[id] = ""
        setResults([], forSlot: id)
        running[id] = false
        messages.removeValue(forKey: id)
        setPopoverVisible(false, forSlot: id)
    }
}
