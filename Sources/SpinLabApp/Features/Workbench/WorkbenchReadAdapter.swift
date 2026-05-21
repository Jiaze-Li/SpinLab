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
