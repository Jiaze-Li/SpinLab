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
/// Default is `preserveDisplayOverrides`: only text overrides (title, axis labels) are
/// cleared when the source identity changes; axisRangeOverride is never touched.
/// Use `clearDisplayOverridesIfSourceChanged` only in true new-analysis or
/// source-replacement paths where resetting the viewport is intentional.
enum DisplayOverridePolicy: Sendable {
    /// Never clear axisRangeOverride. Clear text overrides only when source identity changes.
    /// Use for all display-only rerenders (style, grid, labels, line/scatter, export).
    case preserveDisplayOverrides
    /// Clear both text overrides and axisRangeOverride when source identity changes.
    /// Use only in true new-analysis or source-replacement paths.
    case clearDisplayOverridesIfSourceChanged
    /// Always clear both text overrides and axisRangeOverride, regardless of source identity.
    case forceClearDisplayOverrides
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
    var hiddenPointLabelIndicesBySeries: [String: [Int]] = [:]
    // TODO(boundary): remove legacy Int-string key migration once all persisted packs are migrated to sampleID keys.
    /// User-defined bottom-to-top series order keys. nil = use workflow default. (v5.3.6)
    var seriesOrder: [String]? = nil
    /// Per-tab axis range override. nil = auto-fit from data extents.
    var axisRangeOverride: AxisRangeOverride? = nil

    init(
        legendPoint: CGPointCodable? = nil,
        titleOverride: String = "",
        xLabelOverride: String = "",
        yLabelOverride: String = "",
        seriesLabelOverrides: [String: String] = [:],
        hiddenPointLabelIndicesBySeries: [String: [Int]] = [:],
        seriesOrder: [String]? = nil,
        axisRangeOverride: AxisRangeOverride? = nil
    ) {
        self.legendPoint = legendPoint
        self.titleOverride = titleOverride
        self.xLabelOverride = xLabelOverride
        self.yLabelOverride = yLabelOverride
        self.seriesLabelOverrides = seriesLabelOverrides
        self.hiddenPointLabelIndicesBySeries = hiddenPointLabelIndicesBySeries
        self.seriesOrder = seriesOrder
        self.axisRangeOverride = axisRangeOverride
    }

    private enum CodingKeys: String, CodingKey {
        case legendPoint
        case titleOverride
        case xLabelOverride
        case yLabelOverride
        case seriesLabelOverrides
        case hiddenPointLabelIndicesBySeries
        case seriesOrder
        case axisRangeOverride
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        legendPoint = try c.decodeIfPresent(CGPointCodable.self, forKey: .legendPoint)
        titleOverride = try c.decodeIfPresent(String.self, forKey: .titleOverride) ?? ""
        xLabelOverride = try c.decodeIfPresent(String.self, forKey: .xLabelOverride) ?? ""
        yLabelOverride = try c.decodeIfPresent(String.self, forKey: .yLabelOverride) ?? ""
        seriesLabelOverrides = try c.decodeIfPresent([String: String].self, forKey: .seriesLabelOverrides) ?? [:]
        hiddenPointLabelIndicesBySeries = try c.decodeIfPresent([String: [Int]].self, forKey: .hiddenPointLabelIndicesBySeries) ?? [:]
        seriesOrder = try c.decodeIfPresent([String].self, forKey: .seriesOrder)
        axisRangeOverride = try c.decodeIfPresent(AxisRangeOverride.self, forKey: .axisRangeOverride)
    }
}

// MARK: - TabRenderOutput

/// Per-tab cached render output (runtime only, not persisted).
struct TabRenderOutput: Sendable {
    var imageData: Data?
    var layout: WorkbenchPlotLayout?
    /// Persistence/schema record: raw series y-values, file references, data-column axis mapping.
    /// NOT for use as a Copy PNG source — y-values are unmodified raw measurements.
    var manifestPayload: WorkbenchPlotPayload?
    /// Display-faithful payload: offset/stacked y-values already applied, real data for every tab.
    /// Used as the source for Copy PNG at all export scales.
    /// 1x / 2x / 3x differ only by WorkbenchRenderPipeline.Input.pixelScaleOverride.
    var displayPayload: WorkbenchPlotPayload?
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

    // Toggle a point label's visibility for the active tab.
    func togglePointLabelVisibility(sampleID: String, pointIndex: Int) {
        var hidden = tabStates[activeTab, default: TabRenderState()].hiddenPointLabelIndicesBySeries
        var indices = Set(hidden[sampleID] ?? [])
        if indices.contains(pointIndex) {
            indices.remove(pointIndex)
        } else {
            indices.insert(pointIndex)
        }
        hidden[sampleID] = indices.isEmpty ? nil : indices.sorted()
        tabStates[activeTab, default: TabRenderState()].hiddenPointLabelIndicesBySeries = hidden
    }

    // Returns the hidden-point-label indices for a given tab, keyed by sampleID or Int-string.
    func hiddenPointLabelsBySampleID(for tab: Tab) -> [String: [Int]] {
        (tabStates[tab] ?? TabRenderState()).hiddenPointLabelIndicesBySeries
    }

    // MARK: - Render output management

    func setOutput(_ output: TabRenderOutput, for tab: Tab, policy: DisplayOverridePolicy = .preserveDisplayOverrides) {
        AxisRangeDebug.log("TabRenderManager.setOutput tab=\(tab) policy=\(policy) | axisRangeOverride before=\(tabStates[tab]?.axisRangeOverride.map { "\($0)" } ?? "nil")")
        updateTitleSourceIdentity(from: output.manifestPayload, for: tab, policy: policy)
        tabOutputs[tab] = output
        pruneSeriesLabelOverrides(using: output.manifestPayload, for: tab)
        AxisRangeDebug.log("TabRenderManager.setOutput done tab=\(tab) | axisRangeOverride after=\(tabStates[tab]?.axisRangeOverride.map { "\($0)" } ?? "nil")")
    }

    /// Convenience: apply a WorkbenchRenderPipeline.Output to a tab.
    ///
    /// By default uses `.preserveDisplayOverrides`: text overrides are cleared only when
    /// the analyzed source identity changes; axisRangeOverride is always preserved.
    /// Pass `policy: .clearDisplayOverridesIfSourceChanged` only in true source-replacement paths.
    ///
    /// Pass `displayPayload` to store the pre-pipeline domain payload so that
    /// `WorkbenchPlotExportService` can re-render at any export scale.
    func applyPipelineOutput(
        _ pipelineOutput: WorkbenchRenderPipeline.Output,
        displayPayload: WorkbenchPlotPayload? = nil,
        for tab: Tab,
        policy: DisplayOverridePolicy = .preserveDisplayOverrides
    ) {
        setOutput(TabRenderOutput(
            imageData: pipelineOutput.imageData,
            layout: pipelineOutput.layout,
            manifestPayload: pipelineOutput.manifestPayload,
            displayPayload: displayPayload
        ), for: tab, policy: policy)
    }

    // MARK: - Export snapshot

    /// Builds a workflow-agnostic export snapshot for the given tab.
    ///
    /// The caller provides `globalPlotDefaults`; everything else is read from this manager.
    /// Pass the result to `WorkbenchPlotExportService.exportPNG(snapshot:scale:)`.
    func exportSnapshot(for tab: Tab, globalPlotDefaults: [String: String]) -> WorkbenchPlotExportSnapshot {
        let output = tabOutputs[tab] ?? TabRenderOutput()
        let state = tabStates[tab] ?? TabRenderState()
        return WorkbenchPlotExportSnapshot(
            imageData: output.imageData,
            displayPayload: output.displayPayload,
            layout: output.layout,
            tabState: state,
            showGrid: showPlotGrid,
            legendAnchor: legendAnchor,
            seriesRenderMode: seriesRenderMode,
            chartStyleOverrides: chartStyleOverrides,
            globalPlotDefaults: globalPlotDefaults
        )
    }

    /// Clears per-tab text overrides for a single tab while preserving legendPoint and seriesOrder.
    func clearStatesForTab(_ tab: Tab) {
        let lp = tabStates[tab]?.legendPoint
        let so = tabStates[tab]?.seriesOrder
        if lp != nil || so != nil {
            tabStates[tab] = TabRenderState(legendPoint: lp, seriesOrder: so)
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
        var patch = extraStyleParams
        if showPlotGrid { patch["showGrid"] = "true" }
        if !legendAnchor.isEmpty, s.legendPoint == nil {
            patch["legendAnchor"] = legendAnchor
        }
        return WorkbenchRenderPipeline.Input(
            payload: payload,
            baseOptions: baseOptions,
            legendPoint: s.legendPoint?.cgPoint,
            globalPlotDefaults: globalPlotDefaults,
            seriesRenderMode: seriesRenderMode,
            chartStyleOverrides: chartStyleOverrides,
            seriesLabelOverrides: toIndexedOverrides(
                normalizedSeriesLabelOverrides(s.seriesLabelOverrides, series: payload.series),
                series: payload.series
            ),
            titleOverride: s.titleOverride,
            xLabelOverride: s.xLabelOverride,
            yLabelOverride: s.yLabelOverride,
            hiddenPointLabelsBySeries: toIndexedOverrides(hiddenPointLabelsBySampleID(for: targetTab), series: payload.series).mapValues { Set($0) },
            styleParamsPatch: patch,
            seriesOrder: s.seriesOrder,
            axisRangeOverride: s.axisRangeOverride
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
            if lp != nil || so != nil {
                tabStates[tab] = TabRenderState(legendPoint: lp, seriesOrder: so)
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
    func updateAxisBound(_ bound: AxisRangeBound, value: Double?) {
        let layout = activeOutput.layout
        AxisRangeDebug.log("TabRenderManager.updateAxisBound BEFORE | activeTab=\(activeTab) old axisRangeOverride=\(String(describing: tabStates[activeTab]?.axisRangeOverride)) layout xMin=\((layout?.axisXMin).map { String(format: "%g", $0) } ?? "nil") xMax=\((layout?.axisXMax).map { String(format: "%g", $0) } ?? "nil") yMin=\((layout?.axisYMin).map { String(format: "%g", $0) } ?? "nil") yMax=\((layout?.axisYMax).map { String(format: "%g", $0) } ?? "nil") | bound=\(bound) value=\(value.map { String(format: "%g", $0) } ?? "nil")")
        var state = tabStates[activeTab] ?? TabRenderState()
        var range = state.axisRangeOverride ?? AxisRangeOverride()
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
                return
            }
        }
        state.axisRangeOverride = range.isEmpty ? nil : range
        tabStates[activeTab] = state
        AxisRangeDebug.log("TabRenderManager.updateAxisBound AFTER | new axisRangeOverride=\(String(describing: tabStates[activeTab]?.axisRangeOverride))")
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
            if sourceChanged { clearTextOverrides(&state) }
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
}
