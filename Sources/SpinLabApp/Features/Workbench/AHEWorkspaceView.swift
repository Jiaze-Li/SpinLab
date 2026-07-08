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
                ahe.updateAxisBound(bound, value: value)
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
                        appState.scheduleInteractionSnapshotFlush(source: "aheSeriesOrderCommit")
                    },
                    allowsReordering: true,
                    seriesLabelOverrides: ahe.tabs.activeSeriesLabelOverrides,
                    onVisibilityChange: { key, isVisible in
                        ahe.updateSeriesVisibility(identityKey: key, isVisible: isVisible)
                        appState.scheduleInteractionSnapshotFlush(source: "aheSeriesVisibility")
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
                        appState.scheduleInteractionSnapshotFlush(source: "aheTitleTemplateChange")
                    }
                )
                WorkbenchPlotSpacingInlineControls(
                    stackOffset: $bindableAhe.stackOffsetMultiplier,
                    stackRange: 0...1.6,
                    minGapFraction: $bindableAhe.minGapFraction,
                    onStackChange: {
                        ahe.rerenderForStyleChange()
                        appState.scheduleInteractionSnapshotFlush(source: "aheStackOffsetChange")
                    },
                    onGapSubmit: {
                        ahe.rerenderForStyleChange()
                        appState.scheduleInteractionSnapshotFlush(source: "aheGapSubmit")
                    },
                    sliderWidth: 110
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

