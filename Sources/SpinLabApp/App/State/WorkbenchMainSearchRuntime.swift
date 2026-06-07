import Foundation

@MainActor
@Observable
final class WorkbenchMainSearchRuntime {
    private unowned let store: WorkbenchFeatureStore
    private let dataActor: any SpinLabDataActing
    private var workflowSearchTask: Task<Void, Never>?
    /// Per-workflow search state, keyed by WorkbenchWorkflowID.
    private var searchQueryTexts: [WorkbenchWorkflowID: String]
    private(set) var searchResults: [WorkbenchWorkflowID: [WorkflowMeasurementSearchHit]] = [:]
    private var searchMessages: [WorkbenchWorkflowID: String] = [:]
    private(set) var searchRunning: [WorkbenchWorkflowID: Bool] = [:]

    init(store: WorkbenchFeatureStore, dataActor: any SpinLabDataActing) {
        self.store = store
        self.dataActor = dataActor
        self.searchQueryTexts = Self.restoreSearchQueryTexts()
    }

    private static let searchQueryDefaultsPrefix = "workbench.searchQuery."

    private static func restoreSearchQueryTexts() -> [WorkbenchWorkflowID: String] {
        var result: [WorkbenchWorkflowID: String] = [:]
        for wf in WorkbenchWorkflowID.allCases {
            if let saved = UserDefaults.standard.string(forKey: searchQueryDefaultsPrefix + wf.rawValue) {
                result[wf] = saved
            }
        }
        return result
    }

    private static func persistSearchQueryText(_ text: String, for wf: WorkbenchWorkflowID) {
        UserDefaults.standard.set(text, forKey: searchQueryDefaultsPrefix + wf.rawValue)
    }

    func searchQueryText(for wf: WorkbenchWorkflowID) -> String {
        searchQueryTexts[wf] ?? wf.searchPrefix
    }

    func setSearchQueryText(_ text: String, for wf: WorkbenchWorkflowID) {
        searchQueryTexts[wf] = text
        Self.persistSearchQueryText(text, for: wf)
    }

    func searchResultsList(for wf: WorkbenchWorkflowID) -> [WorkflowMeasurementSearchHit] {
        searchResults[wf] ?? []
    }

    func searchMessage(for wf: WorkbenchWorkflowID) -> String? {
        searchMessages[wf] ?? store.searchMessages[wf]
    }

    func isSearchRunning(for wf: WorkbenchWorkflowID) -> Bool {
        searchRunning[wf] ?? false
    }

    func searchSnapshot(for wf: WorkbenchWorkflowID) -> WorkbenchSearchSnapshot {
        WorkbenchSearchSnapshot(
            workflowID: wf,
            queryText: searchQueryText(for: wf),
            results: searchResultsList(for: wf),
            isRunning: isSearchRunning(for: wf),
            message: searchMessage(for: wf)
        )
    }

    /// Builds a run-scoped selected-hit read surface.
    /// Canonical search results win when non-empty; legacy hits are fallback only when canonical is empty.
    func selectedHitsSnapshot(
        for wf: WorkbenchWorkflowID,
        selectedIDs: Set<String>,
        legacyHits: [WorkflowMeasurementSearchHit]
    ) -> WorkbenchSelectedHitsSnapshot {
        let canonical = searchSnapshot(for: wf)
        let useLegacy = canonical.results.isEmpty && !legacyHits.isEmpty
        let sourceHits = useLegacy ? legacyHits : canonical.results
        let selectedHits = sourceHits.filter { selectedIDs.contains($0.id) }

        return WorkbenchSelectedHitsSnapshot(
            workflowID: wf,
            queryText: canonical.queryText,
            selectedIDs: selectedIDs,
            selectedHits: selectedHits,
            sourceHitCount: sourceHits.count,
            selectionSource: useLegacy ? .legacyMirror : .canonicalSnapshot
        )
    }

    func restoreSearchState(results: [WorkflowMeasurementSearchHit], queryText: String, for wf: WorkbenchWorkflowID) {
        searchResults[wf] = results
        setSearchQueryText(queryText, for: wf)
        setSearchMessage("Restored from analysis pack (\(results.count) hit(s)).", for: wf)
        searchRunning[wf] = false
        projectSearchResults(results, for: wf)
    }

    func runWorkflowMeasurementSearch(
        workflowID wf: WorkbenchWorkflowID,
        libraryRootPath: String?,
        librarySettings: LibrarySettings? = nil
    ) {
        let query = searchQueryText(for: wf).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearInvalidSearchState(
                message: "Enter workflow query, for example: AHE PN31 80K",
                workflowID: wf
            )
            return
        }

        guard let libraryRootPath = libraryRootPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !libraryRootPath.isEmpty else {
            clearInvalidSearchState(
                message: "Set Library Root before searching.",
                workflowID: wf
            )
            return
        }

        store.aheWorkspace.lastLibraryRootPath = libraryRootPath
        store.threeOmegaWorkspace.lastLibraryRootPath = libraryRootPath
        store.analysisVault.configurePersistence(libraryRootPath: libraryRootPath)

        workflowSearchTask?.cancel()
        searchRunning[wf] = true
        searchMessages[wf] = nil

        let workflowDefinitions = store.workflowDefinitions
        workflowSearchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await dataActor.searchWorkflowMeasurements(
                    settings: librarySettings ?? LibrarySettings(
                        rootPath: libraryRootPath,
                        rootBookmarkData: nil,
                        registryInternalPath: nil,
                        registrySourcePath: nil,
                        backupPath: nil,
                        backupLastSyncedAt: nil,
                        allowedBatchPrefixes: [],
                        lastRefreshAt: nil
                    ),
                    query: WorkflowSearchQuery(rawText: query),
                    workflowDefinitions: workflowDefinitions
                )
                guard !Task.isCancelled else { return }
                await self.applySearchSuccess(
                    result,
                    workflowID: wf,
                    query: query,
                    libraryRootPath: libraryRootPath,
                    dataActor: self.dataActor
                )
            } catch is CancellationError {
                self.applySearchCancellation(workflowID: wf)
            } catch let error as AppError {
                self.applySearchFailure(error.localizedDescription, workflowID: wf)
            } catch {
                self.applySearchFailure(
                    AppError.from(error, fallback: "Workflow search failed.").localizedDescription,
                    workflowID: wf
                )
            }
        }
    }

    func clearWorkflowMeasurementSearch(workflowID wf: WorkbenchWorkflowID) {
        workflowSearchTask?.cancel()
        workflowSearchTask = nil
        searchResults[wf] = []
        clearSearchMirrors(for: wf)
        clearSelectedSearchResults(for: wf)
        setSearchMessage(nil, for: wf)
        searchRunning[wf] = false
        setSearchQueryText(wf.searchPrefix, for: wf)
    }

    private func applySearchSuccess(
        _ result: [WorkflowMeasurementSearchHit],
        workflowID wf: WorkbenchWorkflowID,
        query: String,
        libraryRootPath: String,
        dataActor: any SpinLabDataActing
    ) async {
        searchResults[wf] = result
        await projectSearchMirrors(
            result,
            for: wf,
            libraryRootPath: libraryRootPath,
            dataActor: dataActor
        )

        setSearchMessage(
            result.isEmpty
                ? "No files matched query: \(query)"
                : "Found \(result.count) file(s).",
            for: wf
        )
        searchRunning[wf] = false

        if wf == .threeOmega, let rtPath = store.threeOmegaWorkspace.pendingRTSidecarPath {
            let hit = await Task.detached {
                ThreeOmegaWorkspaceStore.rebuildRTHit(fromSidecarPath: rtPath)
            }.value
            if let hit {
                store.threeOmegaWorkspace.applyRestoredRTHit(hit)
            } else {
                store.threeOmegaWorkspace.clearPendingRTRestore()
            }
        }
    }

    private func applySearchCancellation(workflowID wf: WorkbenchWorkflowID) {
        searchRunning[wf] = false
    }

    private func applySearchFailure(_ message: String, workflowID wf: WorkbenchWorkflowID) {
        searchResults[wf] = []
        clearSearchMirrors(for: wf)
        clearSelectedSearchResults(for: wf)
        setSearchMessage(message, for: wf)
        searchRunning[wf] = false
    }

    private func clearInvalidSearchState(message: String, workflowID wf: WorkbenchWorkflowID) {
        workflowSearchTask?.cancel()
        workflowSearchTask = nil
        searchResults[wf] = []
        clearSearchMirrors(for: wf)
        clearSelectedSearchResults(for: wf)
        setSearchMessage(message, for: wf)
        searchRunning[wf] = false
    }

    private func setSearchMessage(_ message: String?, for wf: WorkbenchWorkflowID) {
        searchMessages[wf] = message
        store.searchMessages[wf] = message
    }

    private func projectSearchResults(
        _ result: [WorkflowMeasurementSearchHit],
        for wf: WorkbenchWorkflowID
    ) {
        switch wf {
        case .ahe:
            store.aheWorkspace.cachedSearchResults = result
        case .threeOmega:
            store.threeOmegaWorkspace.cachedSearchResults = result
        case .xyRotation:
            store.xyRotationWorkspace.cachedSearchResults = result
        }
    }

    private func clearSearchMirrors(for wf: WorkbenchWorkflowID) {
        switch wf {
        case .ahe:
            store.aheWorkspace.cachedSearchResults = []
            store.aheWorkspace.cachedSampleNumericDisplay = [:]
        case .threeOmega:
            store.threeOmegaWorkspace.cachedSearchResults = []
            store.threeOmegaWorkspace.cachedSampleNumericDisplay = [:]
        case .xyRotation:
            store.xyRotationWorkspace.cachedSearchResults = []
            store.xyRotationWorkspace.cachedSampleNumericDisplay = [:]
        }
    }

    private func clearSelectedSearchResults(for wf: WorkbenchWorkflowID) {
        switch wf {
        case .ahe:
            store.aheWorkspace.selectedSearchResultIDs = []
        case .threeOmega:
            store.threeOmegaWorkspace.selectedSearchResultIDs = []
        case .xyRotation:
            store.xyRotationWorkspace.selectedSearchResultIDs = []
        }
    }

    private func projectSearchMirrors(
        _ result: [WorkflowMeasurementSearchHit],
        for wf: WorkbenchWorkflowID,
        libraryRootPath: String?,
        dataActor: (any SpinLabDataActing)?
    ) async {
        projectSearchResults(result, for: wf)
        switch wf {
        case .ahe:
            store.aheWorkspace.cachedSampleNumericDisplay = await buildNumericDisplayCache(
                from: result,
                libraryRootPath: libraryRootPath,
                dataActor: dataActor
            )
        case .threeOmega:
            store.threeOmegaWorkspace.cachedSampleNumericDisplay = await buildNumericDisplayCache(
                from: result,
                libraryRootPath: libraryRootPath,
                dataActor: dataActor
            )
        case .xyRotation:
            store.xyRotationWorkspace.lastLibraryRootPath = libraryRootPath ?? ""
            store.xyRotationWorkspace.cachedSampleNumericDisplay = await buildNumericDisplayCache(
                from: result,
                libraryRootPath: libraryRootPath,
                dataActor: dataActor
            )
        }
    }

    private func buildNumericDisplayCache(
        from results: [WorkflowMeasurementSearchHit],
        libraryRootPath: String?,
        dataActor: (any SpinLabDataActing)?
    ) async -> [String: [String: String]] {
        guard let libraryRootPath, let dataActor else {
            return [:]
        }
        let uniqueSampleKeys = Set(results.map { $0.sampleKey })
        var displayCache: [String: [String: String]] = [:]
        for sampleKey in uniqueSampleKeys {
            do {
                let numericDisplay = try await dataActor.lookupSampleNumericDisplay(
                    libraryRootPath: libraryRootPath,
                    sampleKey: sampleKey
                )
                if !numericDisplay.isEmpty {
                    displayCache[sampleKey] = numericDisplay
                }
            } catch {
                print("[SpinLab][Workbench] numericDisplay lookup failed for \(sampleKey): \(error)")
            }
        }
        return displayCache
    }
}
