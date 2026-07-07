import SwiftUI

struct WorkflowWorkspaceResultArea<Store: WorkbenchWorkspaceProviding>: View {
    @Environment(SpinLabAppState.self) private var appState

    let workflowID: String
    let store: Store
    let workbench: WorkbenchFeatureStore

    var body: some View {
        let queryText = workbench.searchQueryText(for: workflowID)

        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            WorkbenchResultHeaderShell(
                store: store,
                analysisMessage: store.saveMessage ?? store.analysisMessage,
                warningCount: store.warningLog.count,
                isAnalyzing: store.isAnalyzing,
                hasAnalysisResult: store.hasAnalysisResult,
                hasActiveImageData: store.activeImageData != nil,
                hasActiveManifestPayload: store.activeChartManifestPayload != nil,
                onClearPlot: { store.clearPlot() },
                onSaveAnalysis: {
                    store.saveAnalysis(searchQueryText: queryText)
                },
                onSaveToLibrary: {
                    store.persistToLibrary {
                        appState.library.loadWorkbenchResultsForCurrentSelection()
                        appState.library.loadMeasurementDataForCurrentSelection()
                    }
                }
            )

            WorkbenchPlotCanvas(
                imageData: store.activeImageData,
                layout: store.activeLayout,
                legendDragGeometry: store.activeLegendDragGeometry,
                onLegendDrag: { pt in
                    store.updateLegendPoint(pt)
                    appState.scheduleInteractionSnapshotFlush(source: "legendDrag")
                },
                onTogglePointLabelVisibility: { key, p in
                    store.togglePointLabelVisibility(sampleID: key, pointIndex: p)
                },
                onCopyPNG: { scale in store.renderPNGAtScale(scale) },
                seriesPayload: store.activeChartManifestPayload,
                relatedCharts: store.relatedCharts,
                libraryRootURL: store.libraryRootURL
            )
        }
    }
}
