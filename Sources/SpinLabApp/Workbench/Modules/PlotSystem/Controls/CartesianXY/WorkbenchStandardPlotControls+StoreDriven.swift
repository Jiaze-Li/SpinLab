import SwiftUI

/// Store-driven convenience initializer for the four standard stacked-curve workflows
/// (AHE, IV, RT, XY Rotation). Replaces the four private per-workflow `PlotControlsPanel`
/// wrappers that used to forward ~25 named arguments 1:1 from `store`/`store.tabs` into
/// `WorkbenchStandardPlotControls` — those derivations now live here, once, driven by
/// `WorkbenchStandardPlotWorkspaceStore` conformance.
///
/// What stays at the call site (genuinely workflow-specific, not accidental duplication):
/// - `activeTab`'s `tabLabel` closure (AHE hardcodes "AHE"; others use `$0.displayName`)
/// - `canReorderSeries` / `currentSeriesOrder` (AHE's concrete values differ from what its
///   `WorkbenchWorkspaceProviding` conformance would report — see
///   `WorkbenchStandardPlotWorkspaceStore`)
/// - the mutation callbacks (`onChange`, `onSeriesOrderCommit`, `onTitleOverride`, …) —
///   each workflow pairs its store mutation with its own `scheduleInteractionSnapshotFlush`
///   source label for diagnostics
/// - `titleRowTrailingContent` (per-workflow spacing controls) and `extraContent`
///   (per-workflow plugin controls, e.g. AHE's Hc/R_AHE overrides, IV's specific controls,
///   XY's Center/Detrend/x=180 toggles)
extension WorkbenchStandardPlotControls {
    init<Store: WorkbenchStandardPlotWorkspaceStore>(
        store: Store,
        tabLabel: @escaping (Tab) -> String,
        globalPlotDefaults: Binding<[String: String]>,
        stackRange: ClosedRange<Double> = 0...1.6,
        canReorderSeries: Bool,
        currentSeriesOrder: [String]?,
        onSeriesOrderCommit: @escaping ([String]) -> Void,
        onChange: @escaping () -> Void,
        onTransientChange: (() -> Void)? = nil,
        onTitleOverride: ((String) -> Void)? = nil,
        onXLabelOverride: ((String) -> Void)? = nil,
        onYLabelOverride: ((String) -> Void)? = nil,
        onRenameSeriesLabel: ((String, String) -> Void)? = nil,
        onVisibilityChange: ((String, Bool) -> Void)? = nil,
        onAxisBoundUpdate: ((AxisRangeBound, Double?) -> Void)? = nil,
        onResetRanges: (() -> Void)? = nil,
        onTickCountUpdate: ((PlotTickAxis, Int) -> Void)? = nil,
        hideTabRow: Bool = false,
        @ViewBuilder titleRowTrailingContent: @escaping () -> TitleRowTrailing,
        @ViewBuilder extraContent: @escaping () -> Extra
    ) where Store.PlotTab == Tab {
        self.init(
            activeTab: Binding(
                get: { store.tabs.activeTab },
                set: { store.tabs.activeTab = $0 }
            ),
            tabLabel: tabLabel,
            stackOffset: Binding(
                get: { store.stackOffsetMultiplier },
                set: { store.stackOffsetMultiplier = $0 }
            ),
            stackRange: stackRange,
            minGapFraction: Binding(
                get: { store.minGapFraction },
                set: { store.minGapFraction = $0 }
            ),
            showGrid: Binding(
                get: { store.showPlotGrid },
                set: { store.showPlotGrid = $0 }
            ),
            showTitle: Binding(
                get: { store.tabs.activeState.showTitle },
                set: { store.tabs.updateShowTitle($0) }
            ),
            titleTemplate: Binding(
                get: { store.titleTemplate },
                set: { store.titleTemplate = $0 }
            ),
            numericDisplayCache: store.cachedSampleNumericDisplay,
            seriesRenderMode: Binding(
                get: { store.seriesRenderMode },
                set: { store.seriesRenderMode = $0 }
            ),
            globalPlotDefaults: globalPlotDefaults,
            chartStyleOverrides: Binding(
                get: { store.chartStyleOverrides },
                set: { store.chartStyleOverrides = $0 }
            ),
            seriesOrderPayload: store.activeChartManifestPayload,
            seriesControlModel: store.tabs.activeOutput.seriesControlModel,
            currentSeriesOrder: currentSeriesOrder,
            canReorderSeries: canReorderSeries,
            onSeriesOrderCommit: onSeriesOrderCommit,
            onChange: onChange,
            onTransientChange: onTransientChange,
            activeTitleOverride: store.tabs.activeState.titleOverride,
            activeXLabelOverride: store.tabs.activeState.xLabelOverride,
            activeYLabelOverride: store.tabs.activeState.yLabelOverride,
            renderedTitle: store.tabs.activeLayout?.chartTitle ?? "",
            renderedXLabel: store.tabs.activeLayout?.xAxisLabel ?? "",
            renderedYLabel: store.tabs.activeLayout?.yAxisLabel ?? "",
            sourceResetToken: store.tabs.activeSourceIdentityKey,
            onTitleOverride: onTitleOverride,
            onXLabelOverride: onXLabelOverride,
            onYLabelOverride: onYLabelOverride,
            activeSeriesLabelOverrides: store.seriesLabelOverrides,
            activeSeriesHiddenKeys: store.tabs.activeState.hiddenSeriesKeys,
            onRenameSeriesLabel: onRenameSeriesLabel,
            onVisibilityChange: onVisibilityChange,
            activeLayout: store.tabs.activeLayout,
            axisRangeOverride: store.tabs.activeState.axisRangeOverride,
            onAxisBoundUpdate: onAxisBoundUpdate,
            onResetRanges: onResetRanges,
            tickOverride: store.tabs.activeState.tickOverride,
            onTickCountUpdate: onTickCountUpdate,
            hideTabRow: hideTabRow,
            titleRowTrailingContent: titleRowTrailingContent,
            extraContent: extraContent
        )
    }
}
