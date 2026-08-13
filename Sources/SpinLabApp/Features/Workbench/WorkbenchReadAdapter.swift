import Foundation

/// Read-only snapshot of a workflow store's shell-facing result surface.
///
/// Example:
/// `let read = WorkbenchReadAdapter(store: appState.workbench.xyRotationWorkspace)`
/// `let payload = read.activePayload`
@MainActor
struct WorkbenchReadAdapter<IngestionResult: Sendable, TabKey: Hashable & Sendable> {
    let ingestionResult: IngestionResult?
    let activePayload: WorkbenchPlotPayload?
    let activeImageData: Data?
    let activeLayout: WorkbenchPlotLayout?
    let tabOutputs: [TabKey: TabRenderOutput]

    init(
        ingestionResult: IngestionResult?,
        activePayload: WorkbenchPlotPayload?,
        activeImageData: Data?,
        activeLayout: WorkbenchPlotLayout?,
        tabOutputs: [TabKey: TabRenderOutput]
    ) {
        self.ingestionResult = ingestionResult
        self.activePayload = activePayload
        self.activeImageData = activeImageData
        self.activeLayout = activeLayout
        self.tabOutputs = tabOutputs
    }
}

// MARK: - WorkbenchReadiness

/// Read-only readiness summary for the active Workbench workflow.
///
/// This is a derived projection, not stored lifecycle state.
enum WorkbenchReadiness: String, Codable, Hashable, Sendable {
    case empty
    case foundData
    case selectedData
    case running
    case resultReady
    case saved
}

/// Derived board-level readiness projection for the active Workbench workflow.
///
/// The projection records the source signals used to derive readiness so future
/// UI gating and preflight logic can stay read-only.
struct WorkbenchReadinessProjection: Sendable, Hashable {
    let searchResultCount: Int
    let selectedCount: Int
    let isRunning: Bool
    let hasResultReady: Bool
    let hasSaved: Bool
    let readiness: WorkbenchReadiness

    init(
        searchResultCount: Int,
        selectedCount: Int,
        isRunning: Bool,
        hasResultReady: Bool,
        hasSaved: Bool
    ) {
        self.searchResultCount = max(0, searchResultCount)
        self.selectedCount = max(0, selectedCount)
        self.isRunning = isRunning
        self.hasResultReady = hasResultReady
        self.hasSaved = hasSaved

        if isRunning {
            readiness = .running
        } else if hasSaved {
            readiness = .saved
        } else if hasResultReady {
            readiness = .resultReady
        } else if selectedCount > 0 {
            readiness = .selectedData
        } else if searchResultCount > 0 {
            readiness = .foundData
        } else {
            readiness = .empty
        }
    }

    var hasFoundData: Bool { searchResultCount > 0 }
    var hasSelectedData: Bool { selectedCount > 0 }

    static func hasSavedPersistenceOutcome(_ outcome: PersistenceOutcome?) -> Bool {
        guard let outcome else { return false }
        switch outcome {
        case .success, .partial:
            return true
        case .failure:
            return false
        }
    }
}

extension WorkbenchReadinessProjection {
    @MainActor
    init<Store: WorkbenchWorkspaceProviding>(
        workbench: WorkbenchFeatureStore,
        workflowID: String,
        store: Store
    ) {
        self.init(
            searchResultCount: workbench.searchResultsList(for: workflowID).count,
            selectedCount: workbench.basketSelectedCount(for: workflowID),
            isRunning: workbench.isSearchRunning(for: workflowID) || store.isAnalyzing,
            hasResultReady: store.activeChartPNG != nil && store.activeChartManifestPayload != nil,
            hasSaved: Self.hasSavedPersistenceOutcome(store.persistenceOutcome)
        )
    }
}

extension WorkbenchFeatureStore {
    @MainActor
    func readinessProjection<Store: WorkbenchWorkspaceProviding>(
        for workflowID: String,
        store: Store
    ) -> WorkbenchReadinessProjection {
        WorkbenchReadinessProjection(workbench: self, workflowID: workflowID, store: store)
    }
}

extension WorkbenchReadAdapter {
    init(store: AHEWorkspaceStore) where IngestionResult == AHEIngestionResult, TabKey == AHEWorkbenchTab {
        self.init(
            ingestionResult: store.ingestionResult,
            activePayload: store.tabs.activeManifestPayload,
            activeImageData: store.tabs.activeImageData,
            activeLayout: store.tabs.activeLayout,
            tabOutputs: store.tabs.tabOutputs
        )
    }

    init(store: XYRotationWorkspaceStore) where IngestionResult == XYRotationIngestionResult, TabKey == XYRotationWorkbenchTab {
        self.init(
            ingestionResult: store.ingestionResult,
            activePayload: store.tabs.activeManifestPayload,
            activeImageData: store.tabs.activeImageData,
            activeLayout: store.tabs.activeLayout,
            tabOutputs: store.tabs.tabOutputs
        )
    }

    init(store: ThreeOmegaWorkspaceStore) where IngestionResult == ThreeOmegaIngestionResult, TabKey == ThreeOmegaWorkbenchTab {
        self.init(
            ingestionResult: store.ingestionResult,
            activePayload: store.tabs.activeManifestPayload,
            activeImageData: store.tabs.activeImageData,
            activeLayout: store.tabs.activeLayout,
            tabOutputs: store.tabs.tabOutputs
        )
    }
}
