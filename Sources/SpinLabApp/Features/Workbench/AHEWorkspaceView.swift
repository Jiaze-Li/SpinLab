import SwiftUI
import AppKit

/// AHE workflow workspace — shell-based layout.
struct AHEWorkspaceView: View, WorkflowWorkspaceProvider {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let ahe = appState.workbench.aheWorkspace

        WorkflowWorkspaceShell(
            workflowID: ahe.workflowID,
            store: ahe,
            workbench: appState.workbench,
            searchExtra: { EmptyView() },
            plotControls: {
                AHEPlotControlsPanel()
                    .environment(appState)
            },
            leftExtra: { EmptyView() },
            rightExtra: { EmptyView() }
        )
        .onAppear {
            print("[PERF][workbench] workspaceAppear name=AHE")
        }
    }
}

// MARK: - AHE Plot Controls Panel (title + grid)

private struct AHEPlotControlsPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let ahe = appState.workbench.aheWorkspace
        @Bindable var workbench = appState.workbench
        @Bindable var bindableAhe = appState.workbench.aheWorkspace

        WorkbenchPlotControlsPanel(
            seriesRenderMode: $bindableAhe.seriesRenderMode,
            globalPlotDefaults: $workbench.globalPlotDefaults,
            chartStyleOverrides: $bindableAhe.chartStyleOverrides,
            onStyleChange: { ahe.rerenderForStyleChange() },
            activeLayout: ahe.tabs.activeLayout,
            axisRangeOverride: ahe.tabs.activeState.axisRangeOverride,
            onAxisBoundUpdate: { bound, value in
                AxisRangeDebug.log("AHEWorkspaceView onAxisBoundUpdate BEFORE updateAxisBound bound=\(bound) value=\(value.map { String(format: "%g", $0) } ?? "nil") | axisRangeOverride=\(String(describing: ahe.tabs.activeState.axisRangeOverride))")
                ahe.tabs.updateAxisBound(bound, value: value)
                AxisRangeDebug.log("AHEWorkspaceView onAxisBoundUpdate AFTER updateAxisBound | axisRangeOverride=\(String(describing: ahe.tabs.activeState.axisRangeOverride))")
                AxisRangeDebug.log("AHEWorkspaceView onAxisBoundUpdate BEFORE rerenderForStyleChange")
                ahe.rerenderForStyleChange()
                AxisRangeDebug.log("AHEWorkspaceView onAxisBoundUpdate AFTER rerenderForStyleChange")
            },
            sourceResetToken: ahe.tabs.activeSourceIdentityKey,
            supplementalContent: {
                WorkbenchSeriesOrderPanel(
                    seriesControlModel: ahe.tabs.activeOutput.seriesControlModel,
                    payload: ahe.tabs.activeManifestPayload,
                    currentSeriesOrder: ahe.tabs.activeState.seriesOrder,
                    hiddenSeriesKeys: ahe.tabs.activeState.hiddenSeriesKeys,
                    isVisible: ahe.tabs.activeManifestPayload != nil,
                    onCommit: { order in
                        ahe.updateSeriesOrder(order)
                        appState.flushInteractionSnapshotNow(source: "aheSeriesOrderCommit")
                    },
                    allowsReordering: true,
                    seriesLabelOverrides: ahe.tabs.activeSeriesLabelOverrides,
                    onVisibilityChange: { key, isVisible in
                        ahe.updateSeriesVisibility(identityKey: key, isVisible: isVisible)
                        appState.flushInteractionSnapshotNow(source: "aheSeriesVisibility")
                    },
                    onRenameLabel: { key, label in
                        ahe.updateSeriesLabel(identityKey: key, newLabel: label)
                    }
                )
            },
            extraContent: {
                WorkbenchPlotControlsPluginSection {
                    AHEOverridesControls()
                }
            }
        ) {
            HStack(alignment: .top, spacing: 12) {
                WorkbenchTitleTemplateField(
                    titleTemplate: $bindableAhe.titleTemplate,
                    numericDisplayCache: ahe.cachedSampleNumericDisplay,
                    onChange: {
                        appState.flushInteractionSnapshotNow(source: "aheTitleTemplateChange")
                    }
                )
                Toggle("Grid", isOn: $bindableAhe.showPlotGrid)
                    .toggleStyle(.checkbox)
                    .padding(.top, 2)
            }
            SharedPlotTextControls(
                titleOverride: ahe.tabs.activeState.titleOverride,
                xLabelOverride: ahe.tabs.activeState.xLabelOverride,
                yLabelOverride: ahe.tabs.activeState.yLabelOverride,
                renderedTitle: ahe.tabs.activeLayout?.chartTitle ?? "",
                renderedXLabel: ahe.tabs.activeLayout?.xAxisLabel ?? "",
                renderedYLabel: ahe.tabs.activeLayout?.yAxisLabel ?? "",
                sourceResetToken: ahe.tabs.activeSourceIdentityKey,
                onTitleOverride: { ahe.updatePlotTitle($0) },
                onXLabelOverride: { ahe.updateXAxisLabel($0) },
                onYLabelOverride: { ahe.updateYAxisLabel($0) }
            )
        }
    }
}

