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
    var seriesLabelOverrides: [String: String] = [:]
    var hiddenPointLabelIndicesBySeries: [String: [Int]] = [:]
    // TODO(boundary): remove legacy Int-string key migration once all persisted packs are migrated to sampleID keys.
    /// User-defined bottom-to-top series order keys. nil = use workflow default. (v5.3.6)
    var seriesOrder: [String]? = nil

    init(
        legendPoint: CGPointCodable? = nil,
        titleOverride: String = "",
        xLabelOverride: String = "",
        yLabelOverride: String = "",
        seriesLabelOverrides: [String: String] = [:],
        hiddenPointLabelIndicesBySeries: [String: [Int]] = [:],
        seriesOrder: [String]? = nil
    ) {
        self.legendPoint = legendPoint
        self.titleOverride = titleOverride
        self.xLabelOverride = xLabelOverride
        self.yLabelOverride = yLabelOverride
        self.seriesLabelOverrides = seriesLabelOverrides
        self.hiddenPointLabelIndicesBySeries = hiddenPointLabelIndicesBySeries
        self.seriesOrder = seriesOrder
    }

    private enum CodingKeys: String, CodingKey {
        case legendPoint
        case titleOverride
        case xLabelOverride
        case yLabelOverride
        case seriesLabelOverrides
        case hiddenPointLabelIndicesBySeries
        case seriesOrder
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
    }
}

// MARK: - TabRenderOutput

/// Per-tab cached render output (runtime only, not persisted).
struct TabRenderOutput: Sendable {
    var imageData: Data?
    var layout: WorkbenchPlotLayout?
    var manifestPayload: WorkbenchPlotPayload?
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

    // Tracks the last rendered chart identity key per tab for stale-override detection.
    // Not persisted — only live session state.
    private var tabChartIdentityKeys: [Tab: String] = [:]

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

    func updateSeriesLabel(sampleID: String, newLabel: String) {
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            tabStates[activeTab, default: TabRenderState()].seriesLabelOverrides.removeValue(forKey: sampleID)
        } else {
            tabStates[activeTab, default: TabRenderState()].seriesLabelOverrides[sampleID] = trimmed
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

    func setOutput(_ output: TabRenderOutput, for tab: Tab) {
        tabOutputs[tab] = output
    }

    /// Convenience: apply a WorkbenchRenderPipeline.Output to a tab.
    ///
    /// When the chart identity changes (different files, axis mapping, or semantic params),
    /// text overrides (title, axis labels, series labels) are cleared automatically while
    /// legendPoint and seriesOrder are preserved.
    func applyPipelineOutput(_ pipelineOutput: WorkbenchRenderPipeline.Output, for tab: Tab) {
        let newKey = WorkbenchChartIdentity.makeIdentityKey(from: pipelineOutput.manifestPayload)
        if let oldKey = tabChartIdentityKeys[tab], oldKey != newKey {
            clearStatesForTab(tab)
        }
        tabChartIdentityKeys[tab] = newKey
        tabOutputs[tab] = TabRenderOutput(
            imageData: pipelineOutput.imageData,
            layout: pipelineOutput.layout,
            manifestPayload: pipelineOutput.manifestPayload
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
        extraStyleParams: [String: String] = [:],
        for tab: Tab? = nil
    ) -> WorkbenchRenderPipeline.Input {
        let targetTab = tab ?? activeTab
        let s = tabStates[targetTab] ?? TabRenderState()
        var patch = extraStyleParams
        if showPlotGrid { patch["showGrid"] = "true" }
        if !legendAnchor.isEmpty, s.legendPoint == nil {
            patch["legendAnchor"] = legendAnchor
        }
        return WorkbenchRenderPipeline.Input(
            payload: payload,
            baseOptions: baseOptions,
            legendPoint: s.legendPoint?.cgPoint,
            seriesRenderMode: seriesRenderMode,
            chartStyleOverrides: chartStyleOverrides,
            seriesLabelOverrides: toIndexedOverrides(s.seriesLabelOverrides, series: payload.series),
            titleOverride: s.titleOverride,
            xLabelOverride: s.xLabelOverride,
            yLabelOverride: s.yLabelOverride,
            hiddenPointLabelsBySeries: toIndexedOverrides(hiddenPointLabelsBySampleID(for: targetTab), series: payload.series).mapValues { Set($0) },
            styleParamsPatch: patch,
            seriesOrder: s.seriesOrder
        )
    }

    // MARK: - Clear

    func clearOutputs() {
        tabOutputs = [:]
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

    /// Clears outputs and per-tab overrides, preserving legend positions.
    func clearAll() {
        clearStates()
        tabOutputs = [:]
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

/// Translates a sampleID-keyed or Int-string-keyed dictionary to index-keyed.
/// - Int-parseable key → direct index (AHE/XY fallback path)
/// - Otherwise → first index in series where sampleID matches (3ω path)
func toIndexedOverrides<V>(_ stringKeyed: [String: V], series: [WorkbenchPlotSeries]) -> [Int: V] {
    var result: [Int: V] = [:]
    for (key, value) in stringKeyed {
        if let idx = Int(key) {
            result[idx] = value
        } else if let idx = series.firstIndex(where: { $0.sampleID == key }) {
            result[idx] = value
        }
    }
    return result
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
