import SwiftUI

/// IV workflow workspace — shell-based layout.
struct IVWorkspaceView: View, WorkflowWorkspaceProvider {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        WorkflowWorkspaceShell(
            workflowID: .iv,
            store: appState.workbench.ivWorkspace,
            workbench: appState.workbench,
            searchExtra: { EmptyView() },
            plotControls: {
                IVPlotControlsPanel()
                    .environment(appState)
            },
            leftExtra: { EmptyView() },
            rightExtra: { EmptyView() }
        )
    }
}

// MARK: - Plot Controls Panel

private struct IVPlotControlsPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.ivWorkspace
        @Bindable var workbench = appState.workbench

        WorkbenchStandardPlotControls(
            activeTab: $store.tabs.activeTab,
            tabLabel: { $0.displayName },
            stackOffset: $store.stackOffsetMultiplier,
            stackRange: 0...1.6,
            minGapFraction: $store.minGapFraction,
            showGrid: $store.tabs.showPlotGrid,
            titleTemplate: $store.titleTemplate,
            numericDisplayCache: store.cachedSampleNumericDisplay,
            seriesRenderMode: $store.tabs.seriesRenderMode,
            globalPlotDefaults: $workbench.globalPlotDefaults,
            chartStyleOverrides: $store.tabs.chartStyleOverrides,
            seriesOrderPayload: store.activeChartManifestPayload,
            currentSeriesOrder: store.activeSeriesOrder,
            canReorderSeries: store.canReorderSeries,
            onSeriesOrderCommit: { order in
                store.updateSeriesOrder(order)
                appState.flushInteractionSnapshotNow()
            },
            onChange: {
                store.rerenderForStyleChange()
                appState.flushInteractionSnapshotNow()
            },
            activeTitleOverride: store.tabs.activeState.titleOverride,
            activeXLabelOverride: store.tabs.activeState.xLabelOverride,
            activeYLabelOverride: store.tabs.activeState.yLabelOverride,
            renderedTitle: store.tabs.activeLayout?.chartTitle ?? "",
            renderedXLabel: store.tabs.activeLayout?.xAxisLabel ?? "",
            renderedYLabel: store.tabs.activeLayout?.yAxisLabel ?? "",
            sourceResetToken: store.tabs.activeSourceIdentityKey,
            onTitleOverride: { store.updatePlotTitle($0) },
            onXLabelOverride: { store.updateXAxisLabel($0) },
            onYLabelOverride: { store.updateYAxisLabel($0) },
            activeSeriesLabelOverrides: store.seriesLabelOverrides,
            onRenameSeriesLabel: { key, label in
                store.updateSeriesLabel(identityKey: key, newLabel: label)
                appState.flushInteractionSnapshotNow()
            }
        ) {
            HStack(spacing: WorkbenchUIStyle.controlRowSpacing) {
                IVCurrentBasisPicker(
                    basis: Binding(
                        get: { store.xCurrentBasis },
                        set: { newValue in
                            let oldValue = store.xCurrentBasis
                            store.updateXCurrentBasis(newValue, previousBasis: oldValue)
                            store.rerenderForStyleChange()
                            appState.flushInteractionSnapshotNow()
                        }
                    )
                )

                IVChannelPicker(
                    label: "ch1",
                    component: $store.ch1Component,
                    confidence: store.ch1Confidence,
                    onChange: {
                        store.rerenderForStyleChange()
                        appState.flushInteractionSnapshotNow()
                    }
                )

                IVChannelPicker(
                    label: "ch2",
                    component: $store.ch2Component,
                    confidence: store.ch2Confidence,
                    onChange: {
                        store.rerenderForStyleChange()
                        appState.flushInteractionSnapshotNow()
                    }
                )
            }
        }
    }
}

// MARK: - Channel Picker

private struct IVCurrentBasisPicker: View {
    @Binding var basis: IVCurrentBasis

    var body: some View {
        HStack(spacing: WorkbenchUIStyle.controlInlineSpacing) {
            Text("X basis")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)

            Picker("", selection: $basis) {
                ForEach(IVCurrentBasis.allCases, id: \.self) { currentBasis in
                    Text(currentBasis.displayName).tag(currentBasis)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 88)
            .font(WorkbenchUIStyle.controlValueFont)
        }
    }
}

private struct IVChannelPicker: View {
    let label: String
    @Binding var component: IVSignalComponent
    let confidence: Double
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: WorkbenchUIStyle.controlInlineSpacing) {
            Text(label)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)

            Picker("", selection: $component) {
                ForEach(IVSignalComponent.allCases, id: \.self) { c in
                    Text(c.rawValue).tag(c)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 56)
            .font(WorkbenchUIStyle.controlValueFont)
            .onChange(of: component) { _, _ in onChange() }

            if confidence > 1.01 {
                Text("\(confidence, specifier: "%.1f")×")
                    .font(WorkbenchUIStyle.confidenceBadgeFont)
                    .foregroundStyle(WorkbenchUIStyle.confidenceBadgeForeground)
                    .monospacedDigit()
                    .padding(.horizontal, WorkbenchUIStyle.chipHorizontalPadding)
                    .padding(.vertical, WorkbenchUIStyle.chipVerticalPadding)
                    .background(
                        WorkbenchUIStyle.confidenceBadgeBackground,
                        in: RoundedRectangle(cornerRadius: WorkbenchUIStyle.chipCornerRadius, style: .continuous)
                    )
                    .help(autoConfidenceHelpText)
                    .accessibilityLabel(autoConfidenceHelpText)
            }
        }
    }

    private var autoConfidenceHelpText: String {
        let axis = component.rawValue.uppercased()
        let otherAxis = axis == "X" ? "Y" : "X"
        return String(format: "Auto confidence: %@ is %.1f× stronger than %@", axis, confidence, otherAxis)
    }
}
