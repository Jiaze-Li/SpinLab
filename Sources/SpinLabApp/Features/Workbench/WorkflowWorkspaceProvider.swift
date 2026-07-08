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
/// Inherits canvas interaction (`WorkbenchPlottingStore`), run-trace read surface
/// (`WorkbenchRunTraceProviding`), pack save/load (`AnalysisPackProviding`),
/// and chart data (`ActiveChartProviding`).
/// The shell view (`WorkflowWorkspaceShell`) renders all shared UI
/// against this protocol; workflow-specific content goes into ViewBuilder slots.
@MainActor
protocol WorkbenchWorkspaceProviding: WorkbenchPlottingStore, WorkbenchRunTraceProviding, AnalysisPackProviding, ActiveChartProviding {

    // MARK: Search results (cachedSearchResults is a workflow/search compatibility cache used only where the current UI still needs search-result context; it is not a selected-hit fallback and must not drive restored selection identity.)

    var cachedSearchResults: [WorkflowMeasurementSearchHit] { get }

    // MARK: Execution

    func runAnalysis()
    func runAnalysis(searchSnapshot: WorkbenchSearchSnapshot?)
    func runAnalysis(selectedHitsSnapshot: WorkbenchSelectedHitsSnapshot?)
    var isAnalyzing: Bool { get }

    // MARK: Re-render (style / label change without full re-analysis)

    func rerenderForStyleChange()

    // MARK: Clear

    /// Clears search results, selection, and resets analysis state.
    func clearResults()
    /// Clears only chart / tab render state (images, trace, layout).
    func clearPlot()

    // MARK: Warning

    var warningLog: WorkbenchWarningLog { get set }

    // MARK: Trace (writable — satisfies WorkbenchRunTraceProviding's get-only)

    var currentRunTrace: WorkbenchRunTraceProjection? { get set }

    /// Build a trace snapshot from the current analysis state.
    /// Called by `commitRunTrace()` after analysis completes.
    func buildRunTrace() -> WorkbenchRunTraceProjection?

    // MARK: Display cache

    var cachedSampleNumericDisplay: [String: [String: String]] { get }

    // MARK: Chart access (derived from tabs)

    var activeImageData: Data? { get }
    var activePdfData: Data? { get }
    var activeLayout: WorkbenchPlotLayout? { get }
    var activeLegendDragGeometry: PlotLegendDragGeometry? { get }
    var seriesLabelOverrides: [String: String] { get }
    var relatedCharts: [WorkbenchResultReference]? { get }
    var libraryRootURL: URL? { get }

    // MARK: Series reordering (opt-in)

    /// Bottom-to-top per-series order keys for the active tab; nil = workflow default order.
    var activeSeriesOrder: [String]? { get }
    /// Whether the active tab's chart supports drag-to-reorder curves.
    var canReorderSeries: Bool { get }
    /// Commits a new bottom-to-top series order from the canvas.
    func updateSeriesOrder(_ order: [String])
    /// Resets to workflow default order.
    func resetSeriesOrder()

    // MARK: Save to Library

    func persistToLibrary(onComplete: (() -> Void)?)

    /// Status message produced by the most recent `persistToLibrary()` call.
    /// Nil when no save has occurred, after `clearPlot()`, or when analysis starts.
    /// Preferred by the shell over `analysisMessage` when non-nil.
    var saveMessage: String? { get }

    /// Save outcome produced by the most recent `persistToLibrary()` call.
    /// Nil means the current analysis has not been saved yet.
    var persistenceOutcome: PersistenceOutcome? { get }
}


// MARK: - Default implementations

extension WorkbenchWorkspaceProviding {
    /// Render-path-agnostic export envelope composed from `activeImageData`/`activePdfData`.
    /// `WorkbenchPlotCanvas` consumes this without knowing which render path produced it.
    var activeExportArtifacts: WorkbenchGraphicExportArtifacts {
        WorkbenchGraphicExportArtifacts(pngData: activeImageData, pdfData: activePdfData)
    }

    /// Default: ignore snapshot and delegate to the legacy no-arg entrypoint.
    /// Workflow stores that consume snapshots override this method directly.
    func runAnalysis(searchSnapshot: WorkbenchSearchSnapshot?) { runAnalysis() }

    /// Default: keep existing compatibility path so workflows can opt-in gradually.
    func runAnalysis(selectedHitsSnapshot: WorkbenchSelectedHitsSnapshot?) {
        runAnalysis(searchSnapshot: nil)
    }

    /// Append a warning to the log. Unified entry point for all workflows.
    /// Same source+message pairs are coalesced inside `WorkbenchWarningLog`,
    /// so reruns of analyze/load/scaling don't stack identical entries.
    func appendWarning(source: String, message: String) {
        warningLog.append(source: source, message: message)
    }

    /// Generate and commit the run trace from current state.
    /// Call this at the end of `runAnalysis()` after results are applied.
    func commitRunTrace() {
        currentRunTrace = buildRunTrace()
    }

    var activeSeriesOrder: [String]? { nil }
    var canReorderSeries: Bool { false }
    func updateSeriesOrder(_ order: [String]) {}
    func resetSeriesOrder() {}

    var activeLegendDragGeometry: PlotLegendDragGeometry? { activeLayout?.legendDragGeometry }

    var saveMessage: String? { nil }
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

// MARK: - WorkbenchWarningLog

/// Shell-level container for workflow warnings. Enforces a single rule for
/// every workflow: identical source+message pairs are coalesced, so reruns
/// of analyze / load / scaling never stack duplicates. Stores can only
/// mutate the log through `append(...)` and `clear()` — direct array
/// manipulation is impossible by construction.
struct WorkbenchWarningLog: Sendable {
    private(set) var entries: [WorkbenchWarningEntry] = []

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    mutating func append(source: String, message: String) {
        guard !entries.contains(where: { $0.source == source && $0.message == message }) else { return }
        entries.append(WorkbenchWarningEntry(source: source, message: message))
    }

    mutating func clear() {
        entries.removeAll()
    }
}
