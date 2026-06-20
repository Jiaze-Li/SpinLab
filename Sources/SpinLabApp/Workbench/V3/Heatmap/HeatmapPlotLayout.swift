import CoreGraphics

/// Geometry type for the heatmap render path (Plot System-owned).
/// Parallel to WorkbenchPlotLayout; must not inherit or extend it.
/// Owns: gridRect, colorbarRect, title/axis label positions, colorbar tick positions.
struct HeatmapPlotLayout: Sendable {

    struct Options: Sendable {
        var width: Int = 800
        var height: Int = 600
        var pixelScale: CGFloat = 2.0
        var paddingTop: CGFloat = 60
        var paddingBottom: CGFloat = 80
        var paddingLeft: CGFloat = 80
        var colorbarGap: CGFloat = 30
        var colorbarWidth: CGFloat = 20
        var colorbarTickArea: CGFloat = 60

        var paddingRight: CGFloat { colorbarGap + colorbarWidth + colorbarTickArea }
    }

    let rendererSize: CGSize
    /// Plot grid area in CG renderer pixel space (origin bottom-left, Y increases upward).
    let gridRect: CGRect
    /// Vertical colorbar area in CG renderer pixel space.
    let colorbarRect: CGRect
    let titleCenter: CGPoint
    let xLabelCenter: CGPoint
    let yLabelCenter: CGPoint
    /// Center for the Z-axis (colorbar) label, rotated 90°.
    let colorbarLabelCenter: CGPoint
    /// Colorbar tick marks: (cgY position, formatted label string).
    /// Tick Y positions match the active color scale mode (linear or log10),
    /// so marks align with the actual color gradient in the colorbar.
    let colorbarTicks: [(y: CGFloat, label: String)]
    let zMin: Double
    let zMax: Double

    // MARK: - Factory

    static func compute(
        payload: HeatmapPlotPayload,
        options: Options = .init(),
        colorScaleMode: HeatmapColorScaleMode = .linear
    ) -> HeatmapPlotLayout {
        let w = CGFloat(options.width)
        let h = CGFloat(options.height)

        let gridRect = CGRect(
            x: options.paddingLeft,
            y: options.paddingBottom,
            width:  w - options.paddingLeft - options.paddingRight,
            height: h - options.paddingTop  - options.paddingBottom
        )

        let colorbarRect = CGRect(
            x: gridRect.maxX + options.colorbarGap,
            y: gridRect.minY,
            width:  options.colorbarWidth,
            height: gridRect.height
        )

        let titleCenter = CGPoint(x: gridRect.midX, y: h - options.paddingTop * 0.45)
        let xLabelCenter = CGPoint(x: gridRect.midX, y: options.paddingBottom * 0.35)
        let yLabelCenter = CGPoint(x: options.paddingLeft * 0.28, y: gridRect.midY)
        let colorbarLabelCenter = CGPoint(
            x: colorbarRect.maxX + options.colorbarTickArea * 0.80,
            y: gridRect.midY
        )

        // Z range
        let zMin: Double
        let zMax: Double
        if let lo = payload.zRangeClampMin, let hi = payload.zRangeClampMax, lo < hi {
            zMin = lo; zMax = hi
        } else {
            let allZ = payload.grid.zMatrix.flatMap { $0 }
            zMin = allZ.min() ?? 0
            zMax = allZ.max() ?? 1
        }

        let tickValues = niceTicks(min: zMin, max: zMax, targetCount: 5)
        let span = zMax - zMin
        // Tick Y positions use a temporary HeatmapColorScale so that log10 ticks
        // align with the actual rendered color gradient rather than sitting at
        // linearly-spaced positions.
        let tickScale = HeatmapColorScale(zMin: zMin, zMax: zMax, mode: colorScaleMode, colormapKey: "viridis")
        let colorbarTicks: [(y: CGFloat, label: String)] = tickValues.map { z in
            let t = tickScale.normalizedValue(for: z)
            let y = colorbarRect.minY + CGFloat(t) * colorbarRect.height
            return (y, formatTickValue(z, range: span))
        }

        return HeatmapPlotLayout(
            rendererSize:        CGSize(width: w, height: h),
            gridRect:            gridRect,
            colorbarRect:        colorbarRect,
            titleCenter:         titleCenter,
            xLabelCenter:        xLabelCenter,
            yLabelCenter:        yLabelCenter,
            colorbarLabelCenter: colorbarLabelCenter,
            colorbarTicks:       colorbarTicks,
            zMin:                zMin,
            zMax:                zMax
        )
    }

    // MARK: - Tick utilities

    /// Returns 3–7 "nice" tick values spanning [min, max].
    static func niceTicks(min: Double, max: Double, targetCount: Int = 5) -> [Double] {
        guard max > min, targetCount > 0 else { return [min, max] }
        let range = max - min
        let roughStep = range / Double(targetCount)
        let magnitude = pow(10.0, floor(Darwin.log10(abs(roughStep))))
        let normalized = roughStep / magnitude
        let niceNorm: Double
        if normalized < 1.5      { niceNorm = 1 }
        else if normalized < 3.5 { niceNorm = 2 }
        else if normalized < 7.5 { niceNorm = 5 }
        else                     { niceNorm = 10 }
        let step = niceNorm * magnitude
        let firstTick = Darwin.ceil(min / step) * step
        var ticks: [Double] = []
        var tick = firstTick
        let eps = step * 1e-9
        while tick <= max + eps {
            ticks.append(tick)
            tick += step
        }
        return ticks
    }

    static func formatTickValue(_ value: Double, range: Double) -> String {
        if abs(value) < 1e-15 { return "0" }
        if range == 0 { return String(format: "%.3g", value) }
        if range >= 1e4 || (range < 0.01 && range > 0) {
            return String(format: "%.2g", value)
        } else if range >= 100 { return String(format: "%.0f", value) }
        else if range >= 10    { return String(format: "%.1f", value) }
        else if range >= 1     { return String(format: "%.2f", value) }
        else if range >= 0.1   { return String(format: "%.3f", value) }
        else                   { return String(format: "%.2g", value) }
    }
}
