import CoreGraphics

// MARK: - WorkbenchPlotRenderScale

/// Default pixel density for all Workbench live plot rendering.
/// Copy PNG has no separate re-render path — it copies whatever imageData
/// the live render already produced at this scale.
enum WorkbenchPlotRenderScale {
    static let display: CGFloat = 3
}
