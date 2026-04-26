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
    var seriesLabelOverrides: [Int: String] = [:]
    var hiddenPointLabelIndicesBySeries: [Int: [Int]] = [:]

    init(
        legendPoint: CGPointCodable? = nil,
        titleOverride: String = "",
        xLabelOverride: String = "",
        yLabelOverride: String = "",
        seriesLabelOverrides: [Int: String] = [:],
        hiddenPointLabelIndicesBySeries: [Int: [Int]] = [:]
    ) {
        self.legendPoint = legendPoint
        self.titleOverride = titleOverride
        self.xLabelOverride = xLabelOverride
        self.yLabelOverride = yLabelOverride
        self.seriesLabelOverrides = seriesLabelOverrides
        self.hiddenPointLabelIndicesBySeries = hiddenPointLabelIndicesBySeries
    }

    private enum CodingKeys: String, CodingKey {
        case legendPoint
        case titleOverride
        case xLabelOverride
        case yLabelOverride
        case seriesLabelOverrides
        case hiddenPointLabelIndicesBySeries
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        legendPoint = try c.decodeIfPresent(CGPointCodable.self, forKey: .legendPoint)
        titleOverride = try c.decodeIfPresent(String.self, forKey: .titleOverride) ?? ""
        xLabelOverride = try c.decodeIfPresent(String.self, forKey: .xLabelOverride) ?? ""
        yLabelOverride = try c.decodeIfPresent(String.self, forKey: .yLabelOverride) ?? ""
        seriesLabelOverrides = try c.decodeIfPresent([Int: String].self, forKey: .seriesLabelOverrides) ?? [:]
        hiddenPointLabelIndicesBySeries = try c.decodeIfPresent([Int: [Int]].self, forKey: .hiddenPointLabelIndicesBySeries) ?? [:]
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
    var activeSeriesLabelOverrides: [Int: String] {
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

    func updateSeriesLabel(index: Int, newLabel: String) {
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            tabStates[activeTab, default: TabRenderState()].seriesLabelOverrides.removeValue(forKey: index)
        } else {
            tabStates[activeTab, default: TabRenderState()].seriesLabelOverrides[index] = trimmed
        }
    }

    // Toggle a point label's visibility for the active tab.
    func togglePointLabelVisibility(seriesIndex: Int, pointIndex: Int) {
        var hidden = tabStates[activeTab, default: TabRenderState()].hiddenPointLabelIndicesBySeries
        var indices = Set(hidden[seriesIndex] ?? [])
        if indices.contains(pointIndex) {
            indices.remove(pointIndex)
        } else {
            indices.insert(pointIndex)
        }
        hidden[seriesIndex] = indices.isEmpty ? nil : indices.sorted()
        tabStates[activeTab, default: TabRenderState()].hiddenPointLabelIndicesBySeries = hidden
    }

    // Returns the hidden-point-label set for a given tab (runtime format for O(1) lookup).
    func hiddenPointLabelSet(for tab: Tab) -> [Int: Set<Int>] {
        let indices = (tabStates[tab] ?? TabRenderState()).hiddenPointLabelIndicesBySeries
        return indices.mapValues { Set($0) }
    }

    // MARK: - Render output management

    func setOutput(_ output: TabRenderOutput, for tab: Tab) {
        tabOutputs[tab] = output
    }

    /// Convenience: apply a WorkbenchRenderPipeline.Output to a tab.
    func applyPipelineOutput(_ pipelineOutput: WorkbenchRenderPipeline.Output, for tab: Tab) {
        tabOutputs[tab] = TabRenderOutput(
            imageData: pipelineOutput.imageData,
            layout: pipelineOutput.layout,
            manifestPayload: pipelineOutput.manifestPayload
        )
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
            seriesLabelOverrides: s.seriesLabelOverrides,
            titleOverride: s.titleOverride,
            xLabelOverride: s.xLabelOverride,
            yLabelOverride: s.yLabelOverride,
            hiddenPointLabelsBySeries: hiddenPointLabelSet(for: targetTab),
            styleParamsPatch: patch
        )
    }

    // MARK: - Clear

    func clearOutputs() {
        tabOutputs = [:]
    }

    /// Clears per-tab display overrides (title, axis, series labels) but preserves legend positions.
    /// Legend positions are canvas preferences that persist across re-analyses.
    func clearStates() {
        for tab in tabStates.keys {
            let legendPoint = tabStates[tab]?.legendPoint
            tabStates[tab] = legendPoint.map { TabRenderState(legendPoint: $0) }
        }
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
