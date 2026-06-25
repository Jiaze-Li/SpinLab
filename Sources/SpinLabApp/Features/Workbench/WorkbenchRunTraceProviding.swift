import Foundation

// MARK: - WorkbenchRunTraceProviding

/// Read surface for the most recent run trace.
/// Not part of the Plot System — compose into workspace-level protocols only.
@MainActor
protocol WorkbenchRunTraceProviding: AnyObject {
    /// 最近一次运行的 trace（nil = 尚未运行）。
    var currentRunTrace: WorkbenchRunTraceProjection? { get }
}
