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

// MARK: - WorkbenchWorkspaceProviding

/// Unified capability contract for all workflow workspace stores.
///
/// Inherits canvas interaction (`WorkbenchPlottingStore`), pack save/load
/// (`AnalysisPackProviding`), and chart data (`ActiveChartProviding`).
/// The shell view (`WorkflowWorkspaceShell`) renders all shared UI
/// against this protocol; workflow-specific content goes into ViewBuilder slots.
@MainActor
protocol WorkbenchWorkspaceProviding: WorkbenchPlottingStore, AnalysisPackProviding, ActiveChartProviding {

    // MARK: Selection

    var cachedSearchResults: [WorkflowMeasurementSearchHit] { get }
    var selectedSearchResultIDs: Set<String> { get set }
    var isAllSelected: Bool { get }
    func selectAll()
    func deselectAll()
    func toggleSearchHitSelection(_ id: String)

    // MARK: Execution

    func runAnalysis()
    var isAnalyzing: Bool { get }

    // MARK: Re-render (style / label change without full re-analysis)

    func rerenderForStyleChange()

    // MARK: Clear

    /// Clears search results, selection, and resets analysis state.
    func clearResults()
    /// Clears only chart / tab render state (images, trace, layout).
    func clearPlot()

    // MARK: Warning

    var warningLog: [WorkbenchWarningEntry] { get set }

    // MARK: Trace (writable — overrides WorkbenchPlottingStore's get-only)

    var currentRunTrace: WorkbenchRunTraceProjection? { get set }

    /// Build a trace snapshot from the current analysis state.
    /// Called by `commitRunTrace()` after analysis completes.
    func buildRunTrace() -> WorkbenchRunTraceProjection?

    // MARK: Display cache

    var cachedSampleNumericDisplay: [String: [String: String]] { get }

    // MARK: Chart access (derived from tabs)

    var activeImageData: Data? { get }
    var activeLayout: WorkbenchPlotLayout? { get }
    var seriesLabelOverrides: [Int: String] { get }
    var relatedCharts: [WorkbenchResultReference]? { get }
    var libraryRootURL: URL? { get }

    // MARK: Save to Library

    func persistToLibrary(onComplete: (() -> Void)?)
}

// MARK: - Default implementations

extension WorkbenchWorkspaceProviding {
    /// Append a warning to the log. Unified entry point for all workflows.
    func appendWarning(source: String, message: String) {
        warningLog.append(WorkbenchWarningEntry(source: source, message: message))
    }

    /// Generate and commit the run trace from current state.
    /// Call this at the end of `runAnalysis()` after results are applied.
    func commitRunTrace() {
        currentRunTrace = buildRunTrace()
    }
}

// MARK: - WorkbenchWarningEntry

/// Universal warning entry for all workflow analysis pipelines.
struct WorkbenchWarningEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let source: String
    let message: String

    init(source: String, message: String) {
        self.timestamp = Date()
        self.source = source
        self.message = message
    }
}
