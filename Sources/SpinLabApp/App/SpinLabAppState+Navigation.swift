import Foundation

/// Result of a navigation request. Only `.committed` changes any state.
enum NavigationOutcome: Equatable {
    /// Guard cleared; Route, Selection and Focus were committed together.
    case committed
    /// Deferred behind the unsaved-edit prompt; nothing was changed.
    case deferred
    /// A different request is already waiting on the prompt; nothing changed.
    case blockedByPendingRequest
    /// The target no longer exists (e.g. archived record gone); nothing changed
    /// and the user was told.
    case aborted
}

// MARK: - Navigation transaction: Request → Evaluate Guard → Defer or Commit
//
// Every entry point (Sidebar, Drawer/Search/Gallery sample jumps, Deep Links,
// cross-area switches) calls `navigate(to:)`. Nothing mutates Route, Drawer
// Selection or Detail Focus until the guard clears.

extension SpinLabAppState {

    func navigate(to routeStack: AppRouteStack) {
        let router = AppRouter()
        router.navigate(to: routeStack) { [weak self] route in
            self?.navigate(to: route)
        }
    }

    func openDeepLink(_ path: String) -> Bool {
        let router = AppRouter()
        guard let stack = router.deepLinkToRouteStack(path) else {
            return false
        }
        navigate(to: stack)
        return true
    }

    @discardableResult
    func navigate(to requested: AppRoutePath) -> NavigationOutcome {
        let route = resolvedRoute(requested)
        if case let .workbenchArchivedRecord(id) = route, !archivedRecordExists(id) {
            presentMissingArchivedRecord()
            return .aborted
        }
        if navigationRequiresDraftDecision(for: route) {
            let pending = LibraryPendingNavigation(
                selection: drawerSelectionChange(for: route),
                target: route,
                boundDraft: libraryFeatureStore.currentDraftBinding
            )
            let recorded = libraryFeatureStore.deferNavigation(
                pending,
                prompt: "You have unsaved sample edits. Save before leaving this sample?"
            )
            return recorded ? .deferred : .blockedByPendingRequest
        }
        // A clear guard supersedes nothing: if a request is waiting, the user
        // must resolve it first.
        if libraryFeatureStore.hasPendingSelectionChange() {
            return .blockedByPendingRequest
        }
        commitNavigation(route)
        return .committed
    }

    // MARK: Target resolution

    /// Normalises a Drawer target against loaded data. A target that does not
    /// resolve (unknown prefix/batch/sample) degrades to Library Management and
    /// never selects a different sample.
    private func resolvedRoute(_ route: AppRoutePath) -> AppRoutePath {
        guard case let .libraryDrawer(prefix, batchId, sampleId) = route else {
            return route
        }
        guard let group = libraryFeatureStore.libraryExistingGroups[prefix]?.first(where: { $0.batchId == batchId }) else {
            return .library
        }
        if let sampleId {
            guard group.samples.contains(where: { $0.id == sampleId }) else {
                return .library
            }
            return route
        }
        return .libraryDrawer(prefix: prefix, batchId: batchId, sampleId: group.samples.first?.id)
    }

    private func archivedRecordExists(_ id: UUID) -> Bool {
        coordinator.routeToWorkbenchForArchivedRecord(
            recordID: id,
            archivedRecords: workbenchFeatureStore.archivedRecords
        ) != nil
    }

    private func presentMissingArchivedRecord() {
        presentAlert(
            title: "Record Unavailable",
            message: "The archived record you asked to open no longer exists, so nothing was opened."
        )
    }

    private func drawerSelectionChange(for route: AppRoutePath) -> LibraryPendingSelectionChange? {
        guard case let .libraryDrawer(prefix, batchId, sampleId) = route else {
            return nil
        }
        return .drawer(prefix: prefix, batchId: batchId, sampleId: sampleId)
    }

    // MARK: Guard

    /// True when committing `route` would unmount or retarget a dirty Drawer
    /// draft and the user has not yet decided what to do with it.
    private func navigationRequiresDraftDecision(for route: AppRoutePath) -> Bool {
        guard libraryFeatureStore.librarySampleEditIsDirty else {
            return false
        }
        let store = libraryFeatureStore
        switch route {
        case let .libraryDrawer(prefix, batchId, sampleId):
            // Same Drawer identity re-opens the sample being edited: allowed.
            return !store.isCurrentDrawerIdentity(prefix: prefix, batchId: batchId, sampleId: sampleId)
        case .library, .librarySearch, .libraryWorkflowGallery:
            guard selectedArea == .library else {
                return false // entering Library: nothing is being unmounted
            }
            if routeIsCurrentLibraryRoute(route) {
                return false
            }
            // Registry Browser preview is read-only and keeps the background
            // Drawer draft alive; only an editing view is being left otherwise.
            return store.libraryActiveSelectionSource != .browser
        case .inbox, .workbench, .workbenchArea, .workbenchArchivedRecord, .workbenchWorkflow:
            return selectedArea == .library
        }
    }

    private func routeIsCurrentLibraryRoute(_ route: AppRoutePath) -> Bool {
        switch (route, libraryFeatureStore.currentRoute) {
        case (.library, .management): return true
        case (.librarySearch, .search): return true
        case let (.libraryWorkflowGallery(id), .workflowGallery(current)): return id == current
        default: return false
        }
    }

    // MARK: Commit (guard has cleared or the user resolved the prompt)

    func commitNavigation(_ route: AppRoutePath) {
        switch route {
        case .inbox:
            selectedArea = .inbox
        case .workbench:
            selectedArea = .workbench
            workbenchFeatureStore.currentRoute = .measurements
        case .workbenchArea:
            selectedArea = .workbench
        case let .workbenchArchivedRecord(id):
            // Re-checked at commit: the record may have vanished while the
            // prompt was open. Select first, switch area only on success.
            guard archivedRecordExists(id),
                  workbenchFeatureStore.selectArchivedRecord(id, analysisModule: analysisModule) else {
                presentMissingArchivedRecord()
                return
            }
            selectedArea = .workbench
        case let .workbenchWorkflow(id):
            selectedArea = .workbench
            workbenchFeatureStore.selectWorkflow(id)
        case .library:
            selectedArea = .library
            libraryFeatureStore.selectManagement()
        case .librarySearch:
            selectedArea = .library
            libraryFeatureStore.selectSearch()
        case let .libraryDrawer(prefix, batchId, sampleId):
            // Selection and Route are applied together; Focus follows the
            // Drawer selection.
            selectExistingDrawerUnguarded(prefix: prefix, batchId: batchId, sampleId: sampleId)
            libraryFeatureStore.selectSampleWorkspace(prefix: prefix, batchId: batchId)
            selectedArea = .library
        case let .libraryWorkflowGallery(id):
            selectedArea = .library
            libraryFeatureStore.selectWorkflowGallery(id)
        }
    }
}
