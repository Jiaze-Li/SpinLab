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
    /// Per-workflow monotonic token. Bumped on every authoritative search-state transition
    /// (new live search, restore, clear, failure) so an in-flight async numeric-display
    /// refresh from an earlier transition can detect it's been superseded and skip its write.
    private var searchStateRevision: [String: Int] = [:]

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
        refreshNumericDisplayCacheAfterRestore(results, for: wf)
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
        bumpSearchStateRevision(for: wf)
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
        setSearchQueryText(WorkflowKey(rawValue: wf)?.searchPrefix ?? "", for: wf)
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
        } else if wf == store.rtWorkspace.workflowID {
            store.rtWorkspace.cachedSearchResults = result
        }
    }

    private func clearSearchMirrors(for wf: String) {
        bumpSearchStateRevision(for: wf)
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
        } else if wf == store.rtWorkspace.workflowID {
            store.rtWorkspace.cachedSearchResults = []
            store.rtWorkspace.cachedSampleNumericDisplay = [:]
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
            store.aheWorkspace.cachedSampleNumericDisplay = await Self.buildNumericDisplayCache(
                from: result,
                libraryRootPath: libraryRootPath,
                dataActor: dataActor
            )
        } else if wf == store.threeOmegaWorkspace.workflowID {
            store.threeOmegaWorkspace.cachedSampleNumericDisplay = await Self.buildNumericDisplayCache(
                from: result,
                libraryRootPath: libraryRootPath,
                dataActor: dataActor
            )
        } else if wf == store.xyRotationWorkspace.workflowID {
            store.xyRotationWorkspace.lastLibraryRootPath = libraryRootPath ?? ""
            store.xyRotationWorkspace.cachedSampleNumericDisplay = await Self.buildNumericDisplayCache(
                from: result,
                libraryRootPath: libraryRootPath,
                dataActor: dataActor
            )
        } else if wf == store.ivWorkspace.workflowID {
            store.ivWorkspace.lastLibraryRootPath = libraryRootPath ?? ""
            store.ivWorkspace.cachedSampleNumericDisplay = await Self.buildNumericDisplayCache(
                from: result,
                libraryRootPath: libraryRootPath,
                dataActor: dataActor
            )
        } else if wf == store.rsmWorkspace.workflowID {
            store.rsmWorkspace.lastLibraryRootPath = libraryRootPath ?? ""
            store.rsmWorkspace.cachedSampleNumericDisplay = await Self.buildNumericDisplayCache(
                from: result,
                libraryRootPath: libraryRootPath,
                dataActor: dataActor
            )
        } else if wf == store.rtWorkspace.workflowID {
            store.rtWorkspace.lastLibraryRootPath = libraryRootPath ?? ""
            store.rtWorkspace.cachedSampleNumericDisplay = await Self.buildNumericDisplayCache(
                from: result,
                libraryRootPath: libraryRootPath,
                dataActor: dataActor
            )
        }
    }

    /// Stateless by design (no `self` capture): safe to run to completion even if this
    /// runtime or its owning `WorkbenchFeatureStore` is torn down while the lookup is in flight.
    private static func buildNumericDisplayCache(
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

    // MARK: - Numeric display refresh after Pack restore

    @discardableResult
    private func bumpSearchStateRevision(for wf: String) -> Int {
        let next = (searchStateRevision[wf] ?? 0) &+ 1
        searchStateRevision[wf] = next
        return next
    }

    private func lastLibraryRootPath(for wf: String) -> String {
        if wf == store.aheWorkspace.workflowID { return store.aheWorkspace.lastLibraryRootPath }
        if wf == store.threeOmegaWorkspace.workflowID { return store.threeOmegaWorkspace.lastLibraryRootPath }
        if wf == store.xyRotationWorkspace.workflowID { return store.xyRotationWorkspace.lastLibraryRootPath }
        if wf == store.ivWorkspace.workflowID { return store.ivWorkspace.lastLibraryRootPath }
        if wf == store.rsmWorkspace.workflowID { return store.rsmWorkspace.lastLibraryRootPath }
        if wf == store.rtWorkspace.workflowID { return store.rtWorkspace.lastLibraryRootPath }
        return ""
    }

    private func setLastLibraryRootPath(_ path: String, for wf: String) {
        if wf == store.aheWorkspace.workflowID { store.aheWorkspace.lastLibraryRootPath = path }
        else if wf == store.threeOmegaWorkspace.workflowID { store.threeOmegaWorkspace.lastLibraryRootPath = path }
        else if wf == store.xyRotationWorkspace.workflowID { store.xyRotationWorkspace.lastLibraryRootPath = path }
        else if wf == store.ivWorkspace.workflowID { store.ivWorkspace.lastLibraryRootPath = path }
        else if wf == store.rsmWorkspace.workflowID { store.rsmWorkspace.lastLibraryRootPath = path }
        else if wf == store.rtWorkspace.workflowID { store.rtWorkspace.lastLibraryRootPath = path }
    }

    /// Resolves, right now while `store` is known-alive, a writer closure that captures the
    /// *concrete workspace store* (a class instance) strongly. The async refresh below invokes
    /// this writer after an await gap during which `store` (held only `unowned` by this runtime)
    /// could have been deallocated — going through `store.<workspace>` again at that point would
    /// crash. Capturing the workspace object itself sidesteps `store`/`self` entirely for the write.
    private func numericDisplayWriter(for wf: String) -> ((_ cache: [String: [String: String]]) -> Void)? {
        if wf == store.aheWorkspace.workflowID {
            let workspace = store.aheWorkspace
            return { workspace.cachedSampleNumericDisplay = $0 }
        } else if wf == store.threeOmegaWorkspace.workflowID {
            let workspace = store.threeOmegaWorkspace
            return { workspace.cachedSampleNumericDisplay = $0 }
        } else if wf == store.xyRotationWorkspace.workflowID {
            let workspace = store.xyRotationWorkspace
            return { workspace.cachedSampleNumericDisplay = $0 }
        } else if wf == store.ivWorkspace.workflowID {
            let workspace = store.ivWorkspace
            return { workspace.cachedSampleNumericDisplay = $0 }
        } else if wf == store.rsmWorkspace.workflowID {
            let workspace = store.rsmWorkspace
            return { workspace.cachedSampleNumericDisplay = $0 }
        } else if wf == store.rtWorkspace.workflowID {
            let workspace = store.rtWorkspace
            return { workspace.cachedSampleNumericDisplay = $0 }
        }
        return nil
    }

    /// Resolves the library root for a workflow the same way Pack restore already does
    /// (`ThreeOmegaWorkspaceStore+Pack.swift` and peers): use the workspace's own cached
    /// root if set, otherwise fall back to the vault's configured root and persist it back.
    private func resolvedLibraryRootPath(for wf: String) -> String? {
        let current = lastLibraryRootPath(for: wf)
        if !current.isEmpty { return current }
        guard let fallback = store.analysisVault.libraryRootPath, !fallback.isEmpty else { return nil }
        setLastLibraryRootPath(fallback, for: wf)
        return fallback
    }

    /// Rebuilds `cachedSampleNumericDisplay` for every unique sampleKey among restored hits.
    ///
    /// `restoreSearchState` only projects `cachedSearchResults` (via `projectSearchResults`),
    /// unlike a live search which goes through `projectSearchMirrors` and also populates the
    /// numeric-display cache. Without this, `WorkflowHitRow` never shows the parenthesized
    /// growth-condition line for search rows restored from an Analysis Pack, in any workflow.
    ///
    /// Uses the full set of restored `sampleKey`s (`Set(results.map(\.sampleKey))`) — never
    /// just `.first` — and reuses `buildNumericDisplayCache` so restore and live search share
    /// one lookup implementation. Guarded by `searchStateRevision`: if another restore, search,
    /// or clear supersedes this one before the async Library lookup resolves, the write is
    /// dropped instead of clobbering newer state.
    private func refreshNumericDisplayCacheAfterRestore(
        _ results: [WorkflowMeasurementSearchHit],
        for wf: String
    ) {
        let revision = bumpSearchStateRevision(for: wf)
        // Resolved now, while `store` is definitely alive; the Task below never touches
        // `store` again, so a `store` deallocated during the await cannot crash the write.
        guard let writeCache = numericDisplayWriter(for: wf) else { return }
        let libraryRootPath = resolvedLibraryRootPath(for: wf)
        let capturedDataActor = dataActor

        Task {
            let cache = await Self.buildNumericDisplayCache(
                from: results,
                libraryRootPath: libraryRootPath,
                dataActor: capturedDataActor
            )
            await MainActor.run { [weak self] in
                guard let self, self.searchStateRevision[wf] == revision else { return }
                writeCache(cache)
            }
        }
    }
}
