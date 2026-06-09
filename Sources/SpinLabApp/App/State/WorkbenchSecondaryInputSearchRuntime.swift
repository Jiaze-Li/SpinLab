import Foundation

/// Runtime that owns session state for secondary-input search slots.
///
/// Each slot represents an independent search channel (query, results, running flag,
/// message, popover visibility, and selected hit) that is orthogonal to
/// WorkbenchMainSearchRuntime and must never appear in WorkbenchSearchSnapshot
/// or WorkbenchSelectionRuntime.
///
/// Gate 7.3 Step 2 registers one slot:
///   - id: "rt"  |  display label: "RT / Rxx(T)"  (3ω room-temperature input)
///
/// Gate 7.3 Step 3 moves selectedRTHit ownership here.
/// ThreeOmegaWorkspaceStore.selectedRTHit forwards reads/writes through this runtime
/// when injected, preserving the same interface for all callers.
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
    private var selectedHits:  [String: WorkflowMeasurementSearchHit]       = [:]

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    // Per-slot monotonic counter. Incremented on each new runSearch call so that a
    // cancelled task's completion handler can detect it is stale and skip state writes.
    @ObservationIgnored private var searchGenerations: [String: UInt] = [:]

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

    func selectedHit(forSlot id: String) -> WorkflowMeasurementSearchHit? {
        selectedHits[id]
    }

    func setSelectedHit(_ hit: WorkflowMeasurementSearchHit?, forSlot id: String) {
        if let hit { selectedHits[id] = hit } else { selectedHits.removeValue(forKey: id) }
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
            setMessage("Enter RT search query.", forSlot: id)
            setIsSearching(false, forSlot: id)
            return
        }
        guard let rootPath = libraryRootPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rootPath.isEmpty else {
            setResults([], forSlot: id)
            setMessage("Set Library Root before searching.", forSlot: id)
            setIsSearching(false, forSlot: id)
            return
        }

        searchTask?.cancel()
        let generation = (searchGenerations[id] ?? 0) &+ 1
        searchGenerations[id] = generation

        setIsSearching(true, forSlot: id)
        setMessage(nil, forSlot: id)
        setResults([], forSlot: id)
        setPopoverVisible(true, forSlot: id)

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
                guard searchGenerations[id] == generation else { return }
                setResults(result, forSlot: id)
                setMessage(
                    result.isEmpty ? "No files matched: \(query)" : "Found \(result.count) file(s).",
                    forSlot: id
                )
                setIsSearching(false, forSlot: id)
            } catch is CancellationError {
                // Only clear the running flag if this generation is still the active one.
                // A replacement search has already set running=true for the new generation.
                guard searchGenerations[id] == generation else { return }
                setIsSearching(false, forSlot: id)
            } catch {
                guard searchGenerations[id] == generation else { return }
                setResults([], forSlot: id)
                setMessage("Search failed.", forSlot: id)
                setIsSearching(false, forSlot: id)
            }
        }
    }

    // MARK: - Clear

    /// Clears search session state (query, results, running, message, popover) for the slot.
    /// Does NOT clear the selected hit, main search, or SelectionRuntime.
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
