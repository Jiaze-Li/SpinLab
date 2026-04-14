import CoreGraphics

/// Centralised chart styling for the Workbench plot renderer, layout, and canvas.
///
/// Defaults match prior hardcoded values except `titleBold` (now false).
/// User-chosen overrides are parsed from `WorkbenchPlotPayload.styleParams`.
struct WorkbenchChartStyle: Codable, Hashable, Sendable {
    var titleFontSize: CGFloat = 25
    var titleBold: Bool = false
    var axisTitleFontSize: CGFloat = 20
    var tickLabelFontSize: CGFloat = 19
    var legendFontSize: CGFloat = 18
    var tickTargetX: Int = 6
    var tickTargetY: Int = 5
    /// Fixed x-axis tick step (nil = auto from niceTicks).
    var xTickStep: Double? = nil
    /// Fixed y-axis tick step (nil = auto from niceTicks).
    var yTickStep: Double? = nil

    // MARK: - Parse from styleParams

    /// Creates a style by overlaying any recognised keys from `styleParams` onto defaults.
    static func from(styleParams: [String: String]) -> WorkbenchChartStyle {
        var s = WorkbenchChartStyle()
        if let v = styleParams["titleFontSize"], let n = Double(v) { s.titleFontSize = CGFloat(n) }
        if let v = styleParams["titleBold"]                        { s.titleBold = (v == "true") }
        if let v = styleParams["axisTitleFontSize"], let n = Double(v) { s.axisTitleFontSize = CGFloat(n) }
        if let v = styleParams["tickLabelFontSize"], let n = Double(v) { s.tickLabelFontSize = CGFloat(n) }
        if let v = styleParams["legendFontSize"], let n = Double(v) { s.legendFontSize = CGFloat(n) }
        if let v = styleParams["tickTargetX"], let n = Int(v) { s.tickTargetX = n }
        if let v = styleParams["tickTargetY"], let n = Int(v) { s.tickTargetY = n }
        if let v = styleParams["xTickStep"], let n = Double(v), n > 0 { s.xTickStep = n }
        if let v = styleParams["yTickStep"], let n = Double(v), n > 0 { s.yTickStep = n }
        return s
    }
}
