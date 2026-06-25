import Foundation

@MainActor
@Observable
final class WorkbenchMainSearchRuntime {
    private unowned let store: WorkbenchFeatureStore
    private let dataActor: any SpinLabDataActing
    private var workflowSearchTask: Task<Void, Never>?
    /// Per-workflow search state, keyed by workflow ID string.
    private var searchQueryTexts: [String: String] = [:]
    private(set) var searchResults: [String: [WorkflowMeasurementSearchHit]] = [:]
    private var searchMessages: [String: String] = [:]
    private(set) var searchRunning: [String: Bool] = [:]

    init(store: WorkbenchFeatureStore, dataActor: any SpinLabDataActing) {
        self.store = store
        self.dataActor = dataActor
    }

    private static let searchQueryDefaultsPrefix = "workbench.searchQuery."

    private static func loadSearchQueryText(for wf: String) -> String? {
        UserDefaults.standard.string(forKey: searchQueryDefaultsPrefix + wf)
    }

    private static func persistSearchQueryText(_ text: String, for wf: String) {
        UserDefaults.standard.set(text, forKey: searchQueryDefaultsPrefix + wf)
    }

    func searchQueryText(for wf: String) -> String {
        if let cached = searchQueryTexts[wf] { return cached }
        if let saved = Self.loadSearchQueryText(for: wf) {
            searchQueryTexts[wf] = saved
            return saved
        }
        return ""
    }

    func setSearchQueryText(_ text: String, for wf: String) {
        searchQueryTexts[wf] = text
        Self.persistSearchQueryText(text, for: wf)
    }

    func searchResultsList(for wf: String) -> [WorkflowMeasurementSearchHit] {
        searchResults[wf] ?? []
    }

    func searchMessage(for wf: String) -> String? {
        searchMessages[wf] ?? store.searchMessages[wf]
    }

    func isSearchRunning(for wf: String) -> Bool {
        searchRunning[wf] ?? false
    }

    func searchSnapshot(for wf: String) -> WorkbenchSearchSnapshot {
        WorkbenchSearchSnapshot(
            workflowID: wf,
            queryText: searchQueryText(for: wf),
            results: searchResultsList(for: wf),
            isRunning: isSearchRunning(for: wf),
            message: searchMessage(for: wf)
        )
    }

    /// Builds a run-scoped selected-hit read surface.
    /// Hit cache is the canonical source for selected hits; current search results supplement for seeds
    /// (pack-restored IDs that have no cached hit object yet). Current results remain authoritative
    /// for sourceHitCount and the select-all denominator.
    func selectedHitsSnapshot(
        for wf: String,
        selectedIDs: Set<String>,
        hitCache: [String: WorkflowMeasurementSearchHit]
    ) -> WorkbenchSelectedHitsSnapshot {
        let canonical = searchSnapshot(for: wf)
        let sourceHits = canonical.results

        // Source-ordered hits that are selected and present in current results.
        var seen = Set<String>()
        var selectedHits: [WorkflowMeasurementSearchHit] = []
        for hit in sourceHits where selectedIDs.contains(hit.id) {
            selectedHits.append(hit)
            seen.insert(hit.id)
        }
        // Cached hits from previous searches, stable-sorted for determinism.
        for id in selectedIDs.subtracting(seen).sorted() {
            if let hit = hitCache[id] {
                selectedHits.append(hit)
            }
        }

        return WorkbenchSelectedHitsSnapshot(
            workflowID: wf,
            queryText: canonical.queryText,
            selectedIDs: selectedIDs,
            selectedHits: selectedHits,
            sourceHitCount: sourceHits.count,
            selectionSource: .canonicalSnapshot
        )
    }

    func restoreSearchState(results: [WorkflowMeasurementSearchHit], queryText: String, for wf: String) {
        searchResults[wf] = results
        setSearchQueryText(queryText, for: wf)
        setSearchMessage("Restored from analysis pack (\(results.count) hit(s)).", for: wf)
        searchRunning[wf] = false
        projectSearchResults(results, for: wf)
    }

    func runWorkflowMeasurementSearch(
        workflowID wf: String,
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

    func clearWorkflowMeasurementSearch(workflowID wf: String) {
        workflowSearchTask?.cancel()
        workflowSearchTask = nil
        searchResults[wf] = []
        clearSearchMirrors(for: wf)
        clearSelectedSearchResults(for: wf)
        setSearchMessage(nil, for: wf)
        searchRunning[wf] = false
        setSearchQueryText("", for: wf)
    }

    private func applySearchSuccess(
        _ result: [WorkflowMeasurementSearchHit],
        workflowID wf: String,
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

        if wf == store.threeOmegaWorkspace.workflowID,
           let rtPath = store.threeOmegaWorkspace.pendingRTSidecarPath {
            let capturedWorkflowID = store.threeOmegaWorkspace.workflowID
            let capturedRelatedRTWorkflowID = store.threeOmegaWorkspace.relatedRTWorkflowID
            let hit = await Task.detached {
                ThreeOmegaWorkspaceStore.rebuildRTHit(
                    fromSidecarPath: rtPath,
                    workflowID: capturedWorkflowID,
                    relatedRTWorkflowID: capturedRelatedRTWorkflowID
                )
            }.value
            if let hit {
                store.threeOmegaWorkspace.applyRestoredRTHit(hit)
            } else {
                store.threeOmegaWorkspace.clearPendingRTRestore()
            }
        }
    }

    private func applySearchCancellation(workflowID wf: String) {
        searchRunning[wf] = false
    }

    private func applySearchFailure(_ message: String, workflowID wf: String) {
        searchResults[wf] = []
        clearSearchMirrors(for: wf)
        clearSelectedSearchResults(for: wf)
        setSearchMessage(message, for: wf)
        searchRunning[wf] = false
    }

    private func clearInvalidSearchState(message: String, workflowID wf: String) {
        workflowSearchTask?.cancel()
        workflowSearchTask = nil
        searchResults[wf] = []
        clearSearchMirrors(for: wf)
        clearSelectedSearchResults(for: wf)
        setSearchMessage(message, for: wf)
        searchRunning[wf] = false
    }

    private func setSearchMessage(_ message: String?, for wf: String) {
        searchMessages[wf] = message
        store.searchMessages[wf] = message
    }

    private func projectSearchResults(
        _ result: [WorkflowMeasurementSearchHit],
        for wf: String
    ) {
        if wf == store.aheWorkspace.workflowID {
            store.aheWorkspace.cachedSearchResults = result
        } else if wf == store.threeOmegaWorkspace.workflowID {
            store.threeOmegaWorkspace.cachedSearchResults = result
        } else if wf == store.xyRotationWorkspace.workflowID {
            store.xyRotationWorkspace.cachedSearchResults = result
        } else if wf == store.ivWorkspace.workflowID {
            store.ivWorkspace.cachedSearchResults = result
        } else if wf == store.rsmWorkspace.workflowID {
            store.rsmWorkspace.cachedSearchResults = result
        }
    }

    private func clearSearchMirrors(for wf: String) {
        if wf == store.aheWorkspace.workflowID {
            store.aheWorkspace.cachedSearchResults = []
            store.aheWorkspace.cachedSampleNumericDisplay = [:]
        } else if wf == store.threeOmegaWorkspace.workflowID {
            store.threeOmegaWorkspace.cachedSearchResults = []
            store.threeOmegaWorkspace.cachedSampleNumericDisplay = [:]
        } else if wf == store.xyRotationWorkspace.workflowID {
            store.xyRotationWorkspace.cachedSearchResults = []
            store.xyRotationWorkspace.cachedSampleNumericDisplay = [:]
        } else if wf == store.ivWorkspace.workflowID {
            store.ivWorkspace.cachedSearchResults = []
            store.ivWorkspace.cachedSampleNumericDisplay = [:]
        } else if wf == store.rsmWorkspace.workflowID {
            store.rsmWorkspace.cachedSearchResults = []
            store.rsmWorkspace.cachedSampleNumericDisplay = [:]
        }
    }

    private func clearSelectedSearchResults(for wf: String) {
        store.deselectAll(for: wf)
    }

    private func projectSearchMirrors(
        _ result: [WorkflowMeasurementSearchHit],
        for wf: String,
        libraryRootPath: String?,
        dataActor: (any SpinLabDataActing)?
    ) async {
        projectSearchResults(result, for: wf)
        if wf == store.aheWorkspace.workflowID {
            store.aheWorkspace.cachedSampleNumericDisplay = await buildNumericDisplayCache(
                from: result,
                libraryRootPath: libraryRootPath,
                dataActor: dataActor
            )
        } else if wf == store.threeOmegaWorkspace.workflowID {
            store.threeOmegaWorkspace.cachedSampleNumericDisplay = await buildNumericDisplayCache(
                from: result,
                libraryRootPath: libraryRootPath,
                dataActor: dataActor
            )
        } else if wf == store.xyRotationWorkspace.workflowID {
            store.xyRotationWorkspace.lastLibraryRootPath = libraryRootPath ?? ""
            store.xyRotationWorkspace.cachedSampleNumericDisplay = await buildNumericDisplayCache(
                from: result,
                libraryRootPath: libraryRootPath,
                dataActor: dataActor
            )
        } else if wf == store.ivWorkspace.workflowID {
            store.ivWorkspace.lastLibraryRootPath = libraryRootPath ?? ""
            store.ivWorkspace.cachedSampleNumericDisplay = await buildNumericDisplayCache(
                from: result,
                libraryRootPath: libraryRootPath,
                dataActor: dataActor
            )
        } else if wf == store.rsmWorkspace.workflowID {
            store.rsmWorkspace.lastLibraryRootPath = libraryRootPath ?? ""
            store.rsmWorkspace.cachedSampleNumericDisplay = await buildNumericDisplayCache(
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
