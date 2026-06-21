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
        colorScaleMode: PlotScaleTransform = .linear,
        chartStyle: WorkbenchChartStyle? = nil
    ) -> HeatmapPlotLayout {
        var opts = options
        if let style = chartStyle {
            // Ensure left padding is wide enough to fit rotated y-axis title + tick labels
            // without overlap at any supported font size.
            let estimatedTickWidth = style.tickLabelFontSize * 4.5
            let axisTitleRoom = style.axisTitleFontSize * 1.5
            opts.paddingLeft = max(options.paddingLeft, estimatedTickWidth + axisTitleRoom + 14)
        }

        let w = CGFloat(opts.width)
        let h = CGFloat(opts.height)

        let gridRect = CGRect(
            x: opts.paddingLeft,
            y: opts.paddingBottom,
            width:  w - opts.paddingLeft - opts.paddingRight,
            height: h - opts.paddingTop  - opts.paddingBottom
        )

        let colorbarRect = CGRect(
            x: gridRect.maxX + opts.colorbarGap,
            y: gridRect.minY,
            width:  opts.colorbarWidth,
            height: gridRect.height
        )

        let titleCenter = CGPoint(x: gridRect.midX, y: h - opts.paddingTop * 0.45)
        let xLabelCenter = CGPoint(x: gridRect.midX, y: opts.paddingBottom * 0.35)
        // Y-axis title (rotated 90°): position based on axis font size when known,
        // otherwise use a fixed fraction of paddingLeft.
        let yLabelCenterX: CGFloat
        if let style = chartStyle {
            yLabelCenterX = style.axisTitleFontSize * 0.75 + 2
        } else {
            yLabelCenterX = opts.paddingLeft * 0.28
        }
        let yLabelCenter = CGPoint(x: yLabelCenterX, y: gridRect.midY)
        let colorbarLabelCenter = CGPoint(
            x: colorbarRect.maxX + opts.colorbarTickArea * 0.80,
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

        let tickScale = HeatmapColorScale(zMin: zMin, zMax: zMax, mode: colorScaleMode, colormapKey: "viridis")
        let colorbarTicks: [(y: CGFloat, label: String)]
        switch colorScaleMode {
        case .linear:
            let tickValues = niceTicks(min: zMin, max: zMax, targetCount: 5)
            let span = zMax - zMin
            colorbarTicks = tickValues.map { z in
                let t = tickScale.normalizedValue(for: z)
                let y = colorbarRect.minY + CGFloat(t) * colorbarRect.height
                return (y, formatLinearTickValue(z, range: span))
            }

        case .log10:
            if let domain = PlotScaleTransform.log10Domain(lowerBound: zMin, upperBound: zMax) {
                let logMin = Darwin.log10(domain.min)
                let logMax = Darwin.log10(domain.max)
                let expTicks = niceTicks(min: logMin, max: logMax, targetCount: 5)
                colorbarTicks = expTicks.map { exponent in
                    let z = pow(10.0, exponent)
                    let t = tickScale.normalizedValue(for: z)
                    let y = colorbarRect.minY + CGFloat(t) * colorbarRect.height
                    return (y, formatLogTickValue(z))
                }
            } else {
                let tickValues = niceTicks(min: zMin, max: zMax, targetCount: 5)
                let span = zMax - zMin
                colorbarTicks = tickValues.map { z in
                    let t = tickScale.normalizedValue(for: z)
                    let y = colorbarRect.minY + CGFloat(t) * colorbarRect.height
                    return (y, formatLinearTickValue(z, range: span))
                }
            }
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

    static func formatLinearTickValue(_ value: Double, range: Double) -> String {
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

    static func formatLogTickValue(_ value: Double) -> String {
        guard value > 0 else { return "0" }
        let exponent = floor(Darwin.log10(value))
        let mantissa = value / pow(10.0, exponent)
        let expInt = Int(exponent)
        if abs(mantissa - 1.0) < 1e-6 {
            return "10^\(expInt)"
        }
        return String(format: "%.2gx10^%d", mantissa, expInt)
    }
}
