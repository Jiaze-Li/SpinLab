import CoreGraphics
import Foundation

// MARK: - WorkbenchPlotExportSnapshot

/// Workflow-agnostic snapshot of all state needed to re-render the current plot for export.
///
/// Each workflow assembles this via `TabRenderManager.exportSnapshot(for:globalPlotDefaults:)`.
/// `WorkbenchPlotExportService` consumes it to produce a PNG at any pixel scale.
struct WorkbenchPlotExportSnapshot: Sendable {
    /// Fallback PNG when export pipeline fails or displayPayload is nil.
    var imageData: Data?
    /// Display-faithful payload: offset/stacked y-values applied. Primary export source.
    var displayPayload: WorkbenchPlotPayload?
    /// Canvas size in renderer pixel space. Used to match the logical export size.
    var layout: WorkbenchPlotLayout?
    /// Per-tab display overrides (title, axis labels, series labels, hidden point labels).
    var tabState: TabRenderState
    /// Whether to render grid lines.
    var showGrid: Bool
    /// Legend anchor preset (e.g. "topRight"). Ignored when tabState.legendPoint is set.
    var legendAnchor: String
    /// Global series render mode (line/scatter/both).
    var seriesRenderMode: SeriesRenderMode
    /// Chart style key-value overrides (font sizes, tick density, etc.).
    var chartStyleOverrides: [String: String]
    /// Shared plot defaults across workflows.
    var globalPlotDefaults: [String: String]
}

// MARK: - WorkbenchPlotExportService

/// Cross-workflow PNG export service for the Workbench Plot System.
///
/// All Cartesian XY workflows call `exportPNG(snapshot:scale:)` for Copy PNG. The only
/// semantic difference between 1x / 2x / 3x is `pixelScaleOverride`. Export scale is NOT
/// macOS Retina backing scale.
///
/// Contract:
/// - `displayPayload` is the primary source. `manifestPayload` is never used here.
/// - `imageData` is fallback only: nil displayPayload, pipeline failure, or empty render.
/// - Never returns a blank PNG when imageData exists.
enum WorkbenchPlotExportService {

    static func exportPNG(
        snapshot: WorkbenchPlotExportSnapshot,
        scale: CGFloat
    ) -> Data? {
        guard let displayPayload = snapshot.displayPayload else {
            return snapshot.imageData
        }

        var baseOptions = WorkbenchChartRenderer.Options()
        if let layout = snapshot.layout {
            baseOptions.width = Int(layout.rendererSize.width.rounded())
            baseOptions.height = Int(layout.rendererSize.height.rounded())
        }

        var patch: [String: String] = [:]
        if snapshot.showGrid { patch["showGrid"] = "true" }
        if !snapshot.legendAnchor.isEmpty, snapshot.tabState.legendPoint == nil {
            patch["legendAnchor"] = snapshot.legendAnchor
        }

        let tabState = snapshot.tabState
        var input = WorkbenchRenderPipeline.Input(
            payload: displayPayload,
            baseOptions: baseOptions,
            globalPlotDefaults: snapshot.globalPlotDefaults
        )
        input.pixelScaleOverride = scale
        input.legendPoint = tabState.legendPoint?.cgPoint
        input.seriesRenderMode = snapshot.seriesRenderMode
        input.chartStyleOverrides = snapshot.chartStyleOverrides
        input.seriesLabelOverrides = toIndexedOverrides(tabState.seriesLabelOverrides, series: displayPayload.series)
        input.titleOverride = tabState.titleOverride
        input.xLabelOverride = tabState.xLabelOverride
        input.yLabelOverride = tabState.yLabelOverride
        input.hiddenPointLabelsBySeries = toIndexedOverrides(
            tabState.hiddenPointLabelIndicesBySeries,
            series: displayPayload.series
        ).mapValues { Set($0) }
        input.styleParamsPatch = patch

        guard let rendered = try? WorkbenchRenderPipeline.render(input).imageData,
              !rendered.isEmpty else {
            return snapshot.imageData
        }
        return rendered
    }
}
