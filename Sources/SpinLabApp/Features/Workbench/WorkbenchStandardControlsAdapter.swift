import SwiftUI

/// Builds the shared Controls Surface descriptor for the four stacked-curve workflows
/// (AHE, IV, RT, XY Rotation). The workflow reads its store here and passes plain values and
/// closures to the Surface; the shared UI never touches the store (CS-28, AC4).
///
/// Per-workflow differences stay as explicit parameters: the snapshot-flush label used for
/// diagnostics, the series-reorder state (AHE's protocol defaults report it differently from
/// its real tab state), and the Specific content.
extension WorkbenchStandardPlotWorkspaceStore {
    @MainActor
    func standardControlsDescriptor(
        appState: SpinLabAppState,
        globalPlotDefaults: Binding<[String: String]>,
        flushSource: String,
        canReorderSeries: Bool,
        currentSeriesOrder: [String]?,
        specific: WorkbenchSpecificContent = .empty
    ) -> WorkbenchControlsDescriptor {
        // Persisted style change: re-render and flush the interaction snapshot.
        let onChange: () -> Void = {
            self.rerenderForStyleChange()
            appState.scheduleInteractionSnapshotFlush(source: flushSource)
        }
        // Per-tab render state (series order/visibility/rename, label overrides, ranges,
        // ticks) is not a snapshot field: re-render only.
        let onTransientChange: () -> Void = { self.rerenderForStyleChange() }
        let state = tabs.activeState
        let layout = tabs.activeLayout
        let sourceToken = tabs.activeSourceIdentityKey

        let common = WorkbenchCommonControlsModel(
            showTitle: state.showTitle,
            titleOverride: state.titleOverride,
            renderedTitle: layout?.chartTitle ?? "",
            sourceResetToken: sourceToken,
            globalPlotDefaults: globalPlotDefaults,
            titleTemplate: Binding(get: { self.titleTemplate }, set: { self.titleTemplate = $0 }),
            availableTokens: WorkbenchAvailableTokensHint.standardTokens(numericDisplayCache: cachedSampleNumericDisplay),
            onShowTitleChange: { value in
                self.tabs.updateShowTitle(value)
                onChange()
            },
            onTitleOverride: { value in
                self.updatePlotTitle(value)
                onTransientChange()
            },
            onTitleTemplateChange: onChange,
            onStyleChange: onChange
        )

        let plot = CartesianXYControlsModel(
            stackOffset: Binding(get: { self.stackOffsetMultiplier }, set: { self.stackOffsetMultiplier = $0 }),
            minGapFraction: Binding(get: { self.minGapFraction }, set: { self.minGapFraction = $0 }),
            showGrid: Binding(get: { self.showPlotGrid }, set: { self.showPlotGrid = $0 }),
            seriesRenderMode: Binding(get: { self.seriesRenderMode }, set: { self.seriesRenderMode = $0 }),
            globalPlotDefaults: globalPlotDefaults,
            chartStyleOverrides: Binding(get: { self.chartStyleOverrides }, set: { self.chartStyleOverrides = $0 }),
            series: CartesianXYSeriesControls(
                payload: activeChartManifestPayload,
                controlModel: tabs.activeOutput.seriesControlModel,
                currentOrder: currentSeriesOrder,
                hiddenKeys: state.hiddenSeriesKeys,
                labelOverrides: seriesLabelOverrides,
                canReorder: canReorderSeries,
                onOrderCommit: { self.updateSeriesOrder($0) },
                onVisibilityChange: { self.updateSeriesVisibility(identityKey: $0, isVisible: $1) },
                onRenameLabel: { self.updateSeriesLabel(identityKey: $0, newLabel: $1) }
            ),
            xLabelOverride: state.xLabelOverride,
            yLabelOverride: state.yLabelOverride,
            renderedXLabel: layout?.xAxisLabel ?? "",
            renderedYLabel: layout?.yAxisLabel ?? "",
            sourceResetToken: sourceToken,
            onXLabelOverride: { self.updateXAxisLabel($0) },
            onYLabelOverride: { self.updateYAxisLabel($0) },
            activeLayout: layout,
            axisRangeOverride: state.axisRangeOverride,
            onAxisBoundUpdate: { self.updateAxisBound($0, value: $1) },
            onResetRanges: { self.resetAxisRanges() },
            tickOverride: state.tickOverride,
            onTickCountUpdate: { self.updateTickCount(axis: $0, count: $1) },
            onChange: onChange,
            onTransientChange: onTransientChange
        )

        return WorkbenchControlsDescriptor(common: common, plot: .cartesianXY(plot), specific: specific)
    }
}
