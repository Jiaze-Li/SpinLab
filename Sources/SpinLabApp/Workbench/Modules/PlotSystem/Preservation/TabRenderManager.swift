import CoreGraphics
import Foundation
import Observation

// MARK: - CGPointCodable

/// CGPoint wrapper for Codable. Shared across all workflows.
struct CGPointCodable: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

// MARK: - DisplayOverridePolicy

/// Controls which per-tab display overrides setOutput/applyPipelineOutput may clear.
///
/// Default is `preserveDisplayOverrides`: title, axis labels, legend position,
/// series labels, series order, axis range, and point tags are preserved across
/// rerenders and re-analysis. Source identity updates may reset editor-local UI
/// state, but must not clear committed PlotSystem display overrides.
/// Use `clearDisplayOverridesIfSourceChanged` only in true source-replacement
/// paths where resetting the viewport is intentional.
enum DisplayOverridePolicy: Sendable {
    /// Preserve committed display overrides. Source identity changes must not clear
    /// title, axis labels, legend position, series labels, series order, axis range,
    /// or point tags.
    /// Use for all display-only rerenders (style, grid, labels, line/scatter, export).
    case preserveDisplayOverrides
    /// Clear both text overrides and axisRangeOverride when source identity changes.
    /// Use only in true new-analysis or source-replacement paths.
    case clearDisplayOverridesIfSourceChanged
    /// Always clear both text overrides and axisRangeOverride, regardless of source identity.
    case forceClearDisplayOverrides
}

// MARK: - WorkbenchTabRenderKind

/// Identifies which render family produced a tab output.
enum WorkbenchTabRenderKind: Codable, Hashable, Sendable {
    case xy
    case dualAxis
}

// MARK: - AxisRangeOverride

/// Per-tab axis range override. nil bounds fall back to auto-fit from data extents.
struct AxisRangeOverride: Codable, Hashable, Sendable {
    var xMin: Double?
    var xMax: Double?
    var yMin: Double?
    var yMax: Double?

    var isEmpty: Bool { xMin == nil && xMax == nil && yMin == nil && yMax == nil }
}

// MARK: - AxisRangeBound

/// Identifies one of the four axis range bounds for per-bound update callbacks.
enum AxisRangeBound: Sendable {
    case xMin, xMax, yMin, yMax
}

// MARK: - TabRenderState

    /// Per-tab display override state.
///
/// Captures all user-interactive display customizations for a single tab:
/// legend position, title/axis label overrides, series label renames.
/// Codable for AnalysisPack persistence. Workflow-agnostic.
struct TabRenderState: Codable, Hashable, Sendable {
    var legendPoint: CGPointCodable?
    var titleOverride: String = ""
    var xLabelOverride: String = ""
    var yLabelOverride: String = ""
    /// Stable-series-keyed legend label overrides.
    var seriesLabelOverrides: [String: String] = [:]
    /// Stable-series-keyed hidden series display state.
    /// Hidden series remain in analysis/pack data but are omitted from display paths.
    var hiddenSeriesKeys: [String] = []
    var hiddenPointLabelIndicesBySeries: [String: [Int]] = [:]
    // TODO(boundary): remove legacy Int-string key migration once all persisted packs are migrated to sampleID keys.
    /// User-defined visual series order keys.
    /// Contract: chip visual order == plot legend top-to-bottom order.
    /// nil = use workflow default visual order.
    /// Workflow adapters may derive renderer-internal order from this value, but
    /// TabRenderState itself must never store renderer-internal / stack bottom-to-top order.
    var seriesOrder: [String]? = nil
    /// Per-tab axis range override. nil = auto-fit from data extents.
    var axisRangeOverride: AxisRangeOverride? = nil
    /// Per-tab Cartesian XY tick-count override. nil = use WorkbenchChartStyle defaults.
    var tickOverride: PlotTickOverride? = nil
    /// Whether point tags are visible for this tab. Default false.
    var showPointTags: Bool = false

    init(
        legendPoint: CGPointCodable? = nil,
        titleOverride: String = "",
        xLabelOverride: String = "",
        yLabelOverride: String = "",
        seriesLabelOverrides: [String: String] = [:],
        hiddenSeriesKeys: [String] = [],
        hiddenPointLabelIndicesBySeries: [String: [Int]] = [:],
        seriesOrder: [String]? = nil,
        axisRangeOverride: AxisRangeOverride? = nil,
        tickOverride: PlotTickOverride? = nil,
        showPointTags: Bool = false
    ) {
        self.legendPoint = legendPoint
        self.titleOverride = titleOverride
        self.xLabelOverride = xLabelOverride
        self.yLabelOverride = yLabelOverride
        self.seriesLabelOverrides = seriesLabelOverrides
        self.hiddenSeriesKeys = hiddenSeriesKeys
        self.hiddenPointLabelIndicesBySeries = hiddenPointLabelIndicesBySeries
        self.seriesOrder = seriesOrder
        self.axisRangeOverride = axisRangeOverride
        self.tickOverride = tickOverride
        self.showPointTags = showPointTags
    }

    private enum CodingKeys: String, CodingKey {
        case legendPoint
        case titleOverride
        case xLabelOverride
        case yLabelOverride
        case seriesLabelOverrides
        case hiddenSeriesKeys
        case hiddenPointLabelIndicesBySeries
        case seriesOrder
        case axisRangeOverride
        case tickOverride
        case showPointTags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        legendPoint = try c.decodeIfPresent(CGPointCodable.self, forKey: .legendPoint)
        titleOverride = try c.decodeIfPresent(String.self, forKey: .titleOverride) ?? ""
        xLabelOverride = try c.decodeIfPresent(String.self, forKey: .xLabelOverride) ?? ""
        yLabelOverride = try c.decodeIfPresent(String.self, forKey: .yLabelOverride) ?? ""
        seriesLabelOverrides = try c.decodeIfPresent([String: String].self, forKey: .seriesLabelOverrides) ?? [:]
        hiddenSeriesKeys = try c.decodeIfPresent([String].self, forKey: .hiddenSeriesKeys) ?? []
        hiddenPointLabelIndicesBySeries = try c.decodeIfPresent([String: [Int]].self, forKey: .hiddenPointLabelIndicesBySeries) ?? [:]
        seriesOrder = try c.decodeIfPresent([String].self, forKey: .seriesOrder)
        axisRangeOverride = try c.decodeIfPresent(AxisRangeOverride.self, forKey: .axisRangeOverride)
        tickOverride = try c.decodeIfPresent(PlotTickOverride.self, forKey: .tickOverride)
        showPointTags = try c.decodeIfPresent(Bool.self, forKey: .showPointTags) ?? false
    }
}

// MARK: - TabRenderOutput

/// Per-tab cached render output (runtime only, not persisted).
struct TabRenderOutput: Sendable {
    var imageData: Data?
    /// Vector PDF artifact rendered from the same display-faithful render state as `imageData`.
    /// nil for render paths that do not yet produce a PDF artifact (e.g. DualAxis, Heatmap).
    var pdfData: Data?
    var renderKind: WorkbenchTabRenderKind = .xy
    var layout: WorkbenchPlotLayout?
    /// Persistence/schema record: raw series y-values, file references, data-column axis mapping.
    var manifestPayload: WorkbenchPlotPayload?
    /// Display-faithful payload: offset/stacked y-values already applied, real data for every tab.
    var displayPayload: WorkbenchPlotPayload?
    /// Dual-axis layout for tab families that do not use WorkbenchPlotLayout.
    var dualAxisLayout: DualAxisPlotLayout?
    /// Dual-axis payload for future consumers.
    var dualAxisPayload: DualAxisPlotPayload?
    /// Read-only control-model contract for series chips / ordering UI.
    var seriesControlModel: SeriesControlModel? = nil
}

// MARK: - AHEWorkbenchTab

/// Single-case tab for the AHE workflow.
/// Required for uniform TabRenderManager usage across all workflows.
enum AHEWorkbenchTab: String, CaseIterable, Hashable, Identifiable, Sendable {
    case ahe

    var id: String { rawValue }
}

// MARK: - TabRenderManager

/// Generic multi-tab render state manager for the Workbench shell.
///
/// Owns per-tab display overrides, per-tab render outputs, and shared
/// display settings (grid, render mode, chart style). Workflow stores
/// hold an instance parameterized over their tab enum.
///
/// This type is the single source of truth for:
/// - Which tab is active
/// - Shell-level display settings (apply to all tabs)
/// - Per-tab display overrides (legend position, label overrides)
/// - Per-tab render results (PNG, layout, manifest payload)
///
/// It does NOT know anything about workflow-specific data (ingestion results,
/// domain models, analysis parameters). That remains in the workflow store.
@MainActor
@Observable
final class TabRenderManager<Tab: Hashable & Sendable> {

    // MARK: - Active tab

    var activeTab: Tab

    // MARK: - Shared display settings (apply to all tabs)

    var showPlotGrid: Bool
    var seriesRenderMode: SeriesRenderMode
    var chartStyleOverrides: [String: String]
    /// Legend anchor preset (e.g. "topRight"). Empty = default.
    /// Per-tab legendPoint overrides this when set.
    var legendAnchor: String = ""

    // MARK: - Per-tab state

    var tabStates: [Tab: TabRenderState] = [:]

    // MARK: - Per-tab render output

    var tabOutputs: [Tab: TabRenderOutput] = [:]

    // Tracks the last analyzed source identity per tab so title resets only when
    // the underlying input changes.
    private var tabTitleSourceIdentityKeys: [Tab: String] = [:]

    // MARK: - Init

    init(
        defaultTab: Tab,
        showPlotGrid: Bool = true,
        seriesRenderMode: SeriesRenderMode = .line,
        chartStyleOverrides: [String: String] = [:]
    ) {
        self.activeTab = defaultTab
        self.showPlotGrid = showPlotGrid
        self.seriesRenderMode = seriesRenderMode
        self.chartStyleOverrides = chartStyleOverrides
    }

    // MARK: - Active tab convenience

    /// Display state for the active tab.
    var activeState: TabRenderState {
        tabStates[activeTab] ?? TabRenderState()
    }

    /// Render output for the active tab.
    var activeOutput: TabRenderOutput {
        tabOutputs[activeTab] ?? TabRenderOutput()
    }

    /// Active tab's rendered PNG image data.
    var activeImageData: Data? { activeOutput.imageData }

    /// Active tab's rendered vector PDF data.
    var activePdfData: Data? { activeOutput.pdfData }

    /// Active tab's plot layout (for canvas hit-testing).
    var activeLayout: WorkbenchPlotLayout? { activeOutput.layout }

    /// Active tab's manifest payload (for Save to Library).
    var activeManifestPayload: WorkbenchPlotPayload? { activeOutput.manifestPayload }

    /// Source identity token for the active tab's most recently analyzed input.
    /// Plot Controls uses this to reset inline editor state when a new source replaces the old one.
    var activeSourceIdentityKey: String { tabTitleSourceIdentityKeys[activeTab] ?? "" }

    /// Active tab's series label overrides (convenience for canvas).
    var activeSeriesLabelOverrides: [String: String] {
        activeState.seriesLabelOverrides
    }

    // MARK: - State for specific tab

    func state(for tab: Tab) -> TabRenderState {
        tabStates[tab] ?? TabRenderState()
    }

    func output(for tab: Tab) -> TabRenderOutput {
        tabOutputs[tab] ?? TabRenderOutput()
    }

    // MARK: - Per-tab state mutators (operate on active tab)

    func updateLegendPoint(_ point: CGPoint) {
        tabStates[activeTab, default: TabRenderState()].legendPoint = CGPointCodable(point)
    }

    func updateTitleOverride(_ title: String) {
        tabStates[activeTab, default: TabRenderState()].titleOverride = title
    }

    func updateXLabelOverride(_ label: String) {
        tabStates[activeTab, default: TabRenderState()].xLabelOverride = label
    }

    func updateYLabelOverride(_ label: String) {
        tabStates[activeTab, default: TabRenderState()].yLabelOverride = label
    }

    func updateSeriesLabel(identityKey: String, newLabel: String) {
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            tabStates[activeTab, default: TabRenderState()].seriesLabelOverrides.removeValue(forKey: identityKey)
        } else {
            tabStates[activeTab, default: TabRenderState()].seriesLabelOverrides[identityKey] = trimmed
        }
    }

    // MARK: - Render output management

    func setOutput(_ output: TabRenderOutput, for tab: Tab, policy: DisplayOverridePolicy = .preserveDisplayOverrides) {
        AxisRangeDebug.log("TabRenderManager.setOutput tab=\(tab) policy=\(policy) | axisRangeOverride before=\(tabStates[tab]?.axisRangeOverride.map { "\($0)" } ?? "nil")")
        updateTitleSourceIdentity(from: output.manifestPayload, for: tab, policy: policy)
        var storedOutput = output
        if storedOutput.seriesControlModel == nil {
            storedOutput.seriesControlModel = makeSeriesControlModel(for: storedOutput, tab: tab)
        }
        tabOutputs[tab] = storedOutput
        pruneSeriesLabelOverrides(using: storedOutput.manifestPayload ?? storedOutput.displayPayload, for: tab)
        AxisRangeDebug.log("TabRenderManager.setOutput done tab=\(tab) | axisRangeOverride after=\(tabStates[tab]?.axisRangeOverride.map { "\($0)" } ?? "nil")")
    }

    /// Convenience: apply a WorkbenchRenderPipeline.Output to a tab.
    ///
    /// By default uses `.preserveDisplayOverrides`: committed display overrides are
    /// preserved across rerenders and source updates.
    /// Pass `policy: .clearDisplayOverridesIfSourceChanged` only in true source-replacement paths.
    ///
    /// Pass `displayPayload` to store the pre-pipeline domain payload for persistence.
    func applyPipelineOutput(
        _ pipelineOutput: WorkbenchRenderPipeline.Output,
        displayPayload: WorkbenchPlotPayload? = nil,
        manifestPayload: WorkbenchPlotPayload? = nil,
        for tab: Tab,
        policy: DisplayOverridePolicy = .preserveDisplayOverrides
    ) {
        let manifest = manifestPayload ?? pipelineOutput.manifestPayload
        setOutput(TabRenderOutput(
            imageData: pipelineOutput.imageData,
            pdfData: pipelineOutput.pdfData,
            renderKind: .xy,
            layout: pipelineOutput.layout,
            manifestPayload: manifest,
            displayPayload: displayPayload
        ), for: tab, policy: policy)
    }

    /// Clears per-tab text overrides for a single tab while preserving legendPoint and seriesOrder.
    func clearStatesForTab(_ tab: Tab) {
        let lp = tabStates[tab]?.legendPoint
        let so = tabStates[tab]?.seriesOrder
        let hs = tabStates[tab]?.hiddenSeriesKeys ?? []
        if lp != nil || so != nil || !hs.isEmpty {
            tabStates[tab] = TabRenderState(legendPoint: lp, hiddenSeriesKeys: hs, seriesOrder: so)
        } else {
            tabStates[tab] = nil
        }
    }

    // MARK: - Pipeline bridge

    /// Builds a WorkbenchRenderPipeline.Input by combining per-tab state
    /// with shared display settings.
    ///
    /// The caller provides the workflow-specific payload (domain data);
    /// this method adds all shell-level display configuration.
    func buildPipelineInput(
        payload: WorkbenchPlotPayload,
        baseOptions: WorkbenchChartRenderer.Options = .init(),
        globalPlotDefaults: [String: String] = [:],
        extraStyleParams: [String: String] = [:],
        for tab: Tab? = nil
    ) -> WorkbenchRenderPipeline.Input {
        let targetTab = tab ?? activeTab
        let sourceIdentityKey = WorkbenchChartIdentity.makeSourceIdentityKey(from: payload)
        let s = preparedState(for: targetTab, sourceIdentityKey: sourceIdentityKey)
        return buildPipelineInput(
            payload: payload,
            baseOptions: baseOptions,
            globalPlotDefaults: globalPlotDefaults,
            extraStyleParams: extraStyleParams,
            tabState: WorkbenchTabDisplayStateSnapshot(
                titleOverride: s.titleOverride,
                xLabelOverride: s.xLabelOverride,
                yLabelOverride: s.yLabelOverride,
                seriesLabelOverrides: s.seriesLabelOverrides,
                legendPoint: s.legendPoint?.cgPoint,
                hiddenSeriesKeys: s.hiddenSeriesKeys,
                hiddenPointLabelsBySeries: s.hiddenPointLabelIndicesBySeries,
                seriesOrder: s.seriesOrder,
                axisRangeOverride: s.axisRangeOverride,
                tickOverride: s.tickOverride,
                showPointTags: s.showPointTags
            ),
            showPlotGrid: showPlotGrid,
            seriesRenderMode: seriesRenderMode,
            chartStyleOverrides: chartStyleOverrides,
            legendAnchor: legendAnchor,
            for: targetTab
        )
    }

    /// Builds a WorkbenchRenderPipeline.Input from a captured display-state snapshot.
    ///
    /// Use this from detached render flows so the render input is derived from the
    /// exact tab state captured at task start, without mutating live tabState.
    func buildPipelineInput(
        payload: WorkbenchPlotPayload,
        baseOptions: WorkbenchChartRenderer.Options = .init(),
        globalPlotDefaults: [String: String] = [:],
        extraStyleParams: [String: String] = [:],
        tabState: WorkbenchTabDisplayStateSnapshot,
        showPlotGrid: Bool,
        seriesRenderMode: SeriesRenderMode,
        chartStyleOverrides: [String: String],
        legendAnchor: String,
        for tab: Tab? = nil
    ) -> WorkbenchRenderPipeline.Input {
        var patch = extraStyleParams
        if showPlotGrid { patch["showGrid"] = "true" }
        if !legendAnchor.isEmpty, tabState.legendPoint == nil {
            patch["legendAnchor"] = legendAnchor
        }
        var input = WorkbenchRenderPipeline.Input(
            payload: payload,
            baseOptions: baseOptions,
            legendPoint: tabState.legendPoint,
            globalPlotDefaults: globalPlotDefaults,
            seriesRenderMode: seriesRenderMode,
            chartStyleOverrides: chartStyleOverrides,
            seriesLabelOverrides: indexedDisplayLabelOverrides(tabState.seriesLabelOverrides, payload: payload),
            titleOverride: tabState.titleOverride,
            xLabelOverride: tabState.xLabelOverride,
            yLabelOverride: tabState.yLabelOverride,
            hiddenPointLabelsBySeries: indexedDisplayHiddenPointLabels(tabState.hiddenPointLabelsBySeries, payload: payload),
            hiddenSeriesKeys: tabState.hiddenSeriesKeys,
            styleParamsPatch: patch,
            seriesOrder: tabState.seriesOrder,
            axisRangeOverride: tabState.axisRangeOverride,
            tickOverride: tabState.tickOverride,
            showPointTags: tabState.showPointTags
        )
        input.pixelScaleOverride = WorkbenchPlotRenderScale.display
        return input
    }

    // MARK: - Display state snapshot

    /// Captures a sendable per-tab display state snapshot for use in detached render tasks.
    ///
    /// Covers all PlotSystem-owned overrides: title, axis labels, series label renames,
    /// legend position, hidden point labels, series order, axis range, and point tag visibility.
    func displayStateSnapshot(for tab: Tab) -> WorkbenchTabDisplayStateSnapshot {
        let s = tabStates[tab] ?? TabRenderState()
        return WorkbenchTabDisplayStateSnapshot(
            titleOverride: s.titleOverride,
            xLabelOverride: s.xLabelOverride,
            yLabelOverride: s.yLabelOverride,
            seriesLabelOverrides: s.seriesLabelOverrides,
            legendPoint: s.legendPoint?.cgPoint,
            hiddenSeriesKeys: s.hiddenSeriesKeys,
            hiddenPointLabelsBySeries: s.hiddenPointLabelIndicesBySeries,
            seriesOrder: s.seriesOrder,
            axisRangeOverride: s.axisRangeOverride,
            tickOverride: s.tickOverride,
            showPointTags: s.showPointTags
        )
    }

    // MARK: - Clear

    func clearOutputs() {
        tabOutputs = [:]
        tabTitleSourceIdentityKeys = [:]
    }

    /// Clears per-tab display overrides (title, axis, series labels) but preserves
    /// legend positions and series order — both are canvas preferences that survive re-analysis.
    func clearStates() {
        for tab in tabStates.keys {
            let lp = tabStates[tab]?.legendPoint
            let so = tabStates[tab]?.seriesOrder
            let hs = tabStates[tab]?.hiddenSeriesKeys ?? []
            if lp != nil || so != nil || !hs.isEmpty {
                tabStates[tab] = TabRenderState(legendPoint: lp, hiddenSeriesKeys: hs, seriesOrder: so)
            } else {
                tabStates[tab] = nil
            }
        }
    }

    func updateSeriesOrder(_ order: [String]?) {
        if let order, !order.isEmpty {
            tabStates[activeTab, default: TabRenderState()].seriesOrder = order
        } else {
            tabStates[activeTab, default: TabRenderState()].seriesOrder = nil
        }
    }

    func resetSeriesOrder() {
        tabStates[activeTab]?.seriesOrder = nil
    }

    func updateSeriesVisibility(identityKey: String, isVisible: Bool) {
        var state = tabStates[activeTab] ?? TabRenderState()
        var hidden = state.hiddenSeriesKeys
        if isVisible {
            hidden.removeAll { $0 == identityKey }
        } else if !hidden.contains(identityKey) {
            hidden.append(identityKey)
        }
        state.hiddenSeriesKeys = hidden
        tabStates[activeTab] = state
    }

    func resetHiddenSeries() {
        tabStates[activeTab]?.hiddenSeriesKeys = []
    }

    func updateAxisRangeOverride(_ override: AxisRangeOverride?) {
        if let override, !override.isEmpty {
            tabStates[activeTab, default: TabRenderState()].axisRangeOverride = override
        } else {
            tabStates[activeTab, default: TabRenderState()].axisRangeOverride = nil
        }
    }

    /// Merges a single bound update into the latest per-tab state.
    ///
    /// Always reads from the current tabStates[activeTab] — never a stale snapshot.
    /// Validates that effective lo < hi (using the rendered layout for auto bounds)
    /// before writing. Invalid updates are silently discarded.
    /// Returns true iff `axisRangeOverride` actually changed (rejected/no-op updates return false),
    /// so callers can skip an unnecessary rerender.
    @discardableResult
    func updateAxisBound(_ bound: AxisRangeBound, value: Double?) -> Bool {
        let layout = activeOutput.layout
        AxisRangeDebug.log("TabRenderManager.updateAxisBound BEFORE | activeTab=\(activeTab) old axisRangeOverride=\(String(describing: tabStates[activeTab]?.axisRangeOverride)) layout xMin=\((layout?.axisXMin).map { String(format: "%g", $0) } ?? "nil") xMax=\((layout?.axisXMax).map { String(format: "%g", $0) } ?? "nil") yMin=\((layout?.axisYMin).map { String(format: "%g", $0) } ?? "nil") yMax=\((layout?.axisYMax).map { String(format: "%g", $0) } ?? "nil") | bound=\(bound) value=\(value.map { String(format: "%g", $0) } ?? "nil")")
        var state = tabStates[activeTab] ?? TabRenderState()
        let oldRange = state.axisRangeOverride
        var range = oldRange ?? AxisRangeOverride()
        switch bound {
        case .xMin: range.xMin = value
        case .xMax: range.xMax = value
        case .yMin: range.yMin = value
        case .yMax: range.yMax = value
        }
        if value != nil {
            let valid: Bool
            switch bound {
            case .xMin, .xMax:
                let lo = range.xMin ?? layout?.axisXMin
                let hi = range.xMax ?? layout?.axisXMax
                valid = lo == nil || hi == nil || lo! < hi!
            case .yMin, .yMax:
                let lo = range.yMin ?? layout?.axisYMin
                let hi = range.yMax ?? layout?.axisYMax
                valid = lo == nil || hi == nil || lo! < hi!
            }
            AxisRangeDebug.log("TabRenderManager.updateAxisBound validation | bound=\(bound) valid=\(valid) effective lo=\(bound == .xMin || bound == .xMax ? (range.xMin ?? layout?.axisXMin).map { String(format: "%g", $0) } ?? "nil" : (range.yMin ?? layout?.axisYMin).map { String(format: "%g", $0) } ?? "nil") hi=\(bound == .xMin || bound == .xMax ? (range.xMax ?? layout?.axisXMax).map { String(format: "%g", $0) } ?? "nil" : (range.yMax ?? layout?.axisYMax).map { String(format: "%g", $0) } ?? "nil")")
            guard valid else {
                AxisRangeDebug.log("TabRenderManager.updateAxisBound REJECTED (invalid range)")
                return false
            }
        }
        let newRange = range.isEmpty ? nil : range
        guard newRange != oldRange else { return false }
        state.axisRangeOverride = newRange
        tabStates[activeTab] = state
        AxisRangeDebug.log("TabRenderManager.updateAxisBound AFTER | new axisRangeOverride=\(String(describing: tabStates[activeTab]?.axisRangeOverride))")
        return true
    }

    /// Updates the per-tab Cartesian XY tick-count override for the given axis.
    /// Returns true iff the stored value actually changed, so callers can skip an
    /// unnecessary rerender. Parallel to `updateAxisBound` for tick density instead of axis range.
    @discardableResult
    func updateTickCount(axis: PlotTickAxis, count: Int) -> Bool {
        let clamped = PlotTickConfiguration.clamp(count)
        var state = tabStates[activeTab] ?? TabRenderState()
        var override = state.tickOverride ?? PlotTickOverride()
        switch axis {
        case .x:
            guard override.x != clamped else { return false }
            override.x = clamped
        case .y:
            guard override.y != clamped else { return false }
            override.y = clamped
        }
        state.tickOverride = override
        tabStates[activeTab] = state
        return true
    }

    /// Clears outputs and per-tab overrides, preserving legend positions.
    func clearAll() {
        clearStates()
        tabOutputs = [:]
        tabTitleSourceIdentityKeys = [:]
    }

    // MARK: - Pack persistence

    /// Exports per-tab state for pack serialization.
    func snapshotStates(keyFor: (Tab) -> String) -> [String: TabRenderState] {
        tabStates.reduce(into: [:]) { dict, pair in
            dict[keyFor(pair.key)] = pair.value
        }
    }

    /// Restores per-tab state from a pack snapshot.
    func restoreStates(_ snapshot: [String: TabRenderState], tabFor: (String) -> Tab?) {
        tabStates = [:]
        for (key, state) in snapshot {
            if let tab = tabFor(key) {
                tabStates[tab] = state
            }
        }
    }
}

// MARK: - Translation helpers

/// Translates a stable-series-keyed or legacy Int-string-keyed dictionary to index-keyed.
/// - Exact stable key match (`sourceRef` / `sampleID` / resolver key) wins
/// - Otherwise, sampleID or sourceRef fallback
/// - Otherwise, Int-string fallback for pre-stable data
func toIndexedOverrides<V>(_ stringKeyed: [String: V], series: [WorkbenchPlotSeries]) -> [Int: V] {
    let identities = indexedSeriesIdentities(series)
    var result: [Int: V] = [:]
    for (key, value) in stringKeyed {
        if let idx = identities.firstIndex(where: { $0.identityKey == key }) {
            result[idx] = value
        } else if let idx = identities.firstIndex(where: { $0.sourceRef == key }) {
            result[idx] = value
        } else if let idx = identities.firstIndex(where: { $0.sampleID == key }) {
            result[idx] = value
        } else if let idx = Int(key), idx >= 0, (identities.isEmpty || identities.indices.contains(idx)) {
            result[idx] = value
        }
    }
    return result
}

func normalizedSeriesLabelOverrides(
    _ stringKeyed: [String: String],
    series: [WorkbenchPlotSeries]
) -> [String: String] {
    let identities = indexedSeriesIdentities(series)
    guard !stringKeyed.isEmpty, !identities.isEmpty else { return [:] }

    var result: [String: String] = [:]
    for (key, value) in stringKeyed {
        if identities.contains(where: { $0.identityKey == key }) {
            result[key] = value
        } else if let match = identities.first(where: { $0.sourceRef == key }) {
            result[match.identityKey] = value
        } else if let match = identities.first(where: { $0.sampleID == key }) {
            result[match.identityKey] = value
        } else if let idx = Int(key), identities.indices.contains(idx) {
            result[identities[idx].identityKey] = value
        }
    }
    return result
}

/// WARNING: this reverses purely on reverseSeriesForLegend and must not be read as the
/// user-facing legend/chip order — that order comes from the canonical visual series order
/// (WorkbenchRenderPipeline.Input.seriesOrder / TabRenderState.seriesOrder), never from this.
func displaySeriesOrder(for payload: WorkbenchPlotPayload) -> [WorkbenchPlotSeries] {
    payload.reverseSeriesForLegend ? Array(payload.series.reversed()) : payload.series
}

/// Used only to remap index-keyed overrides (labels, hidden point-labels) across the
/// reverseSeriesForLegend reversal the pipeline applies before rendering. Renderer-internal
/// use only — WARNING: not a source of user-facing legend/chip order.
func displayIdentitySeries(for payload: WorkbenchPlotPayload) -> [WorkbenchPlotSeries] {
    guard payload.reverseSeriesForLegend,
          payload.series.count > 1,
          payload.series.allSatisfy({ !($0.sourceRef ?? "").isEmpty }) else {
        return payload.series
    }
    return Array(payload.series.reversed())
}

func indexedDisplayLabelOverrides(
    _ stringKeyed: [String: String],
    payload: WorkbenchPlotPayload
) -> [Int: String] {
    toIndexedOverrides(normalizedSeriesLabelOverrides(stringKeyed, series: payload.series), series: displayIdentitySeries(for: payload))
}

func indexedDisplayHiddenPointLabels(
    _ stringKeyed: [String: [Int]],
    payload: WorkbenchPlotPayload
) -> [Int: Set<Int>] {
    toIndexedOverrides(stringKeyed, series: displayIdentitySeries(for: payload)).mapValues { Set($0) }
}

func applySeriesLabelOverrides(
    _ overrides: [String: String],
    to series: [WorkbenchPlotSeries]
) -> [WorkbenchPlotSeries] {
    let indexed = toIndexedOverrides(overrides, series: series)
    guard !indexed.isEmpty else { return series }
    return series.enumerated().map { index, item in
        guard let label = indexed[index] else { return item }
        var copy = item
        copy.label = label
        return copy
    }
}

private struct IndexedSeriesIdentity {
    let identityKey: String
    let sampleID: String?
    let sourceRef: String?
}

private func indexedSeriesIdentities(_ series: [WorkbenchPlotSeries]) -> [IndexedSeriesIdentity] {
    WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: series).map {
        IndexedSeriesIdentity(
            identityKey: $0.identityKey,
            sampleID: $0.sampleID,
            sourceRef: $0.sourceRef
        )
    }
}

/// Migrates TabRenderState from Int-string keys (5.3.5 and earlier) to sampleID keys.
/// No-ops if keys are not pure Int-string format (already migrated or sampleID-keyed).
func migrateStateIfNeeded(_ state: inout TabRenderState, series: [WorkbenchPlotSeries]) {
    let labelsAreIntKeys = state.seriesLabelOverrides.keys.allSatisfy { Int($0) != nil }
    if labelsAreIntKeys && !state.seriesLabelOverrides.isEmpty {
        var migrated: [String: String] = [:]
        for (key, value) in state.seriesLabelOverrides {
            if let idx = Int(key), idx < series.count, let sid = series[idx].sampleID {
                migrated[sid] = value
            }
        }
        state.seriesLabelOverrides = migrated
    }
    let hiddenAreIntKeys = state.hiddenPointLabelIndicesBySeries.keys.allSatisfy { Int($0) != nil }
    if hiddenAreIntKeys && !state.hiddenPointLabelIndicesBySeries.isEmpty {
        var migrated: [String: [Int]] = [:]
        for (key, value) in state.hiddenPointLabelIndicesBySeries {
            if let idx = Int(key), idx < series.count, let sid = series[idx].sampleID {
                migrated[sid] = value
            }
        }
        state.hiddenPointLabelIndicesBySeries = migrated
    }
}

private extension TabRenderManager {
    func preparedState(for tab: Tab, sourceIdentityKey: String, policy: DisplayOverridePolicy = .preserveDisplayOverrides) -> TabRenderState {
        var state = tabStates[tab] ?? TabRenderState()
        if let previousKey = tabTitleSourceIdentityKeys[tab], previousKey != sourceIdentityKey {
            applyOverrideClearing(to: &state, policy: policy, sourceChanged: true)
            tabStates[tab] = state
        }
        tabTitleSourceIdentityKeys[tab] = sourceIdentityKey
        return state
    }

    func updateTitleSourceIdentity(from payload: WorkbenchPlotPayload?, for tab: Tab, policy: DisplayOverridePolicy = .preserveDisplayOverrides) {
        guard let payload else { return }
        let newKey = WorkbenchChartIdentity.makeSourceIdentityKey(from: payload)
        let sourceChanged = tabTitleSourceIdentityKeys[tab].map { $0 != newKey } ?? false
        AxisRangeDebug.log("TabRenderManager.updateTitleSourceIdentity tab=\(tab) policy=\(policy) sourceChanged=\(sourceChanged) | axisRangeOverride before=\(tabStates[tab]?.axisRangeOverride.map { "\($0)" } ?? "nil")")
        tabTitleSourceIdentityKeys[tab] = newKey
        applyOverrideClearing(to: &tabStates[tab, default: TabRenderState()], policy: policy, sourceChanged: sourceChanged)
        AxisRangeDebug.log("TabRenderManager.updateTitleSourceIdentity done tab=\(tab) | axisRangeOverride after=\(tabStates[tab]?.axisRangeOverride.map { "\($0)" } ?? "nil")")
    }

    func applyOverrideClearing(to state: inout TabRenderState, policy: DisplayOverridePolicy, sourceChanged: Bool) {
        switch policy {
        case .preserveDisplayOverrides:
            break
        case .clearDisplayOverridesIfSourceChanged:
            if sourceChanged { clearSourceScopedOverrides(&state) }
        case .forceClearDisplayOverrides:
            clearSourceScopedOverrides(&state)
        }
    }

    func clearTextOverrides(_ state: inout TabRenderState) {
        state.titleOverride = ""
        state.xLabelOverride = ""
        state.yLabelOverride = ""
    }

    func clearViewportOverrides(_ state: inout TabRenderState) {
        state.axisRangeOverride = nil
    }

    func clearSourceScopedOverrides(_ state: inout TabRenderState) {
        clearTextOverrides(&state)
        clearViewportOverrides(&state)
    }

    func pruneSeriesLabelOverrides(using payload: WorkbenchPlotPayload?, for tab: Tab) {
        guard let payload, !payload.series.isEmpty, var state = tabStates[tab] else { return }
        let normalized = normalizedSeriesLabelOverrides(state.seriesLabelOverrides, series: payload.series)
        guard normalized != state.seriesLabelOverrides else { return }
        state.seriesLabelOverrides = normalized
        tabStates[tab] = state
    }

    func makeSeriesControlModel(for output: TabRenderOutput, tab: Tab) -> SeriesControlModel? {
        guard let payload = output.manifestPayload ?? output.displayPayload else { return nil }
        guard output.renderKind != .dualAxis else { return nil }
        let state = tabStates[tab] ?? TabRenderState()
        return SeriesControlModel.fromPayload(
            payload,
            currentSeriesOrder: state.seriesOrder,
            hiddenSeriesKeys: state.hiddenSeriesKeys
        )
    }
}
