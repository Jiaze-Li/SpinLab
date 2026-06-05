import SwiftUI

struct WorkflowWorkspaceResultArea<Store: WorkbenchWorkspaceProviding>: View {
    @Environment(SpinLabAppState.self) private var appState

    let workflowID: WorkbenchWorkflowID
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

            WorkbenchLoadPackPopover(workflowID: workflowID.rawValue, store: store)

            WorkbenchPlotCanvas(
                imageData: store.activeImageData,
                layout: store.activeLayout,
                seriesLabelOverrides: store.seriesLabelOverrides,
                onLegendDrag: { pt in
                    store.updateLegendPoint(pt)
                    appState.flushInteractionSnapshotNow()
                },
                onEditTitle: { title in store.updatePlotTitle(title) },
                onEditXLabel: { label in store.updateXAxisLabel(label) },
                onEditYLabel: { label in store.updateYAxisLabel(label) },
                onEditLegendLabel: { key, label in
                    store.updateSeriesLabel(sampleID: key, newLabel: label)
                },
                onFontSizeChange: { key, size in
                    store.chartStyleOverrides[key] = "\(Int(size))"
                    store.rerenderForStyleChange()
                },
                onTogglePointLabelVisibility: { key, p in
                    store.togglePointLabelVisibility(sampleID: key, pointIndex: p)
                },
                onCopyPNG: { scale in store.renderPNGAtScale(scale) },
                onStyleOverrideChange: { key, value in
                    store.chartStyleOverrides[key] = value
                    store.rerenderForStyleChange()
                },
                chartStyleOverrides: store.chartStyleOverrides,
                seriesPayload: store.activeChartManifestPayload,
                relatedCharts: store.relatedCharts,
                libraryRootURL: store.libraryRootURL
            )
        }
    }
}
