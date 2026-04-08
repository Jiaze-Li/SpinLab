import SwiftUI

/// Marker protocol for all per-workflow workspace views.
///
/// Each workflow (AHE, RT, 3W …) provides one concrete conforming view.
/// `WorkbenchView` never references concrete workspace types directly —
/// it resolves the correct view through `WorkflowWorkspaceRegistry`.
///
/// ## Shell regions
/// Every workspace view is expected to own the following UI regions
/// (layout and ordering within each region are up to the concrete view):
///
/// | Region          | Purpose                                          |
/// |-----------------|--------------------------------------------------|
/// | `queryBar`      | Workflow search input + library-root label       |
/// | `actionBar`     | Primary action buttons (search, plot, clear …)   |
/// | `statusArea`    | Progress indicators and status messages          |
/// | `plotCanvas`    | Rendered chart image                             |
/// | `plotControls`  | Axis / style / legend controls                   |
/// | `tracePanel`    | Last-run trace details                           |
/// | `resultsList`   | Selectable measurement hit rows                  |
protocol WorkflowWorkspaceProvider: View {}

// MARK: - ActiveChartProviding
//
// Implemented by workflow stores that support "Save to Library" for the
// currently active chart. Any workflow store conforming to this protocol
// can be wired to a generic Save to Library button.

@MainActor
protocol ActiveChartProviding: AnyObject {
    /// PNG data of the currently active chart (nil = nothing to save).
    var activeChartPNG: Data? { get }
    /// Manifest payload for the active chart. sourceRef must be populated on all series.
    var activeChartManifestPayload: WorkbenchPlotPayload? { get }
    /// Sample keys associated with the active chart.
    var activeChartSampleKeys: [String] { get }
    /// Metric entries to persist alongside the chart (empty = no metrics for this tab).
    func buildActiveChartMetrics() -> [PendingMetricEntry]
}
