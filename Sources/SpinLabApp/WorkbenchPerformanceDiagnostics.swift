import Foundation

/// Single switch gating the temporary `[PERF]` instrumentation added while
/// diagnosing Workbench plot-controls rebuilds and snapshot flush churn.
/// Defaults to off so normal runs stay quiet; flip to `true` locally when
/// re-investigating a rebuild/flush regression.
enum WorkbenchPerformanceDiagnostics {
    static let isEnabled = false
}
