import CoreGraphics
import CoreText

/// Centralised chart styling for the Workbench plot renderer, layout, and canvas.
///
/// Defaults match prior hardcoded values except `titleBold` (now false).
/// User-chosen overrides are parsed from `WorkbenchPlotPayload.styleParams`.
struct WorkbenchChartStyle: Codable, Hashable, Sendable {
    var fontName: String = "TimesNewRomanPSMT"
    var boldFontName: String = "TimesNewRomanPS-BoldMT"
    var titleFontSize: CGFloat = 25
    var titleBold: Bool = false
    var axisTitleFontSize: CGFloat = 20
    var tickLabelFontSize: CGFloat = 19
    var legendFontSize: CGFloat = 18
    var tickTargetX: Int = 6
    var tickTargetY: Int = 5
    var pointLabelFontSize: CGFloat = 20
    /// Fixed x-axis tick step (nil = auto from niceTicks).
    var xTickStep: Double? = nil
    /// Fixed y-axis tick step (nil = auto from niceTicks).
    var yTickStep: Double? = nil
    /// Global line width override (nil = use per-series default ~2.0).
    var lineWidth: Double? = nil
    /// Global scatter point radius override (nil = use renderer default 3.5).
    var pointRadius: Double? = nil

    // MARK: - Parse from styleParams

    /// Creates a style by overlaying any recognised keys from `styleParams` onto defaults.
    static func from(styleParams: [String: String]) -> WorkbenchChartStyle {
        var s = WorkbenchChartStyle()
        if let v = styleParams["plotFontName"], !v.isEmpty { s.fontName = v }
        if let v = styleParams["plotBoldFontName"], !v.isEmpty { s.boldFontName = v }
        if let v = styleParams["titleFontSize"], let n = Double(v) { s.titleFontSize = CGFloat(n) }
        if let v = styleParams["titleBold"]                        { s.titleBold = (v == "true") }
        if let v = styleParams["axisTitleFontSize"], let n = Double(v) { s.axisTitleFontSize = CGFloat(n) }
        if let v = styleParams["tickLabelFontSize"], let n = Double(v) { s.tickLabelFontSize = CGFloat(n) }
        if let v = styleParams["legendFontSize"], let n = Double(v) { s.legendFontSize = CGFloat(n) }
        if let v = styleParams["pointLabelFontSize"], let n = Double(v) { s.pointLabelFontSize = CGFloat(n) }
        if let v = styleParams["tickTargetX"], let n = Int(v) { s.tickTargetX = PlotTickConfiguration.clamp(n) }
        if let v = styleParams["tickTargetY"], let n = Int(v) { s.tickTargetY = PlotTickConfiguration.clamp(n) }
        if let v = styleParams["xTickStep"], let n = Double(v), n > 0 { s.xTickStep = n }
        if let v = styleParams["yTickStep"], let n = Double(v), n > 0 { s.yTickStep = n }
        if let v = styleParams["lineWidth"], let n = Double(v), n > 0 { s.lineWidth = n }
        if let v = styleParams["pointRadius"], let n = Double(v), n > 0 { s.pointRadius = n }
        return s
    }

    /// Derives a PlotTickConfiguration from the current XY tick target fields.
    var tickConfiguration: PlotTickConfiguration {
        PlotTickConfiguration(xTargetCount: tickTargetX, yTargetCount: tickTargetY)
    }

    func ctFont(size: CGFloat, bold: Bool = false) -> CTFont {
        let resolvedFontName = bold ? boldFontName : fontName
        return CTFontCreateWithName(resolvedFontName as CFString, size, nil)
    }

    /// Keys owned by the global plot-default layer.
    ///
    /// These values are shared across workflows and are not workflow-pack state.
    static let globalPlotDefaultKeys: Set<String> = [
        "titleFontSize",
        "axisTitleFontSize",
        "tickLabelFontSize",
        "legendFontSize",
        "pointLabelFontSize",
        "plotFontName",
        "plotBoldFontName",
        "lineWidth",
        "pointRadius",
    ]

    static func isGlobalPlotDefaultKey(_ key: String) -> Bool {
        globalPlotDefaultKeys.contains(key)
    }

    /// Splits a style-override dictionary into shared global defaults and
    /// workflow-local overrides.
    static func splitGlobalPlotDefaults(
        from styleOverrides: [String: String]
    ) -> (global: [String: String], local: [String: String]) {
        var global: [String: String] = [:]
        var local: [String: String] = [:]
        for (key, value) in styleOverrides {
            if isGlobalPlotDefaultKey(key) {
                global[key] = value
            } else {
                local[key] = value
            }
        }
        return (global, local)
    }
}
