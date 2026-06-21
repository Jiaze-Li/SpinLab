import CoreGraphics
import CoreText
import Foundation

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
        var paddingRight: CGFloat = 80
        var colorbarGap: CGFloat = 30
        var colorbarWidth: CGFloat = 20
        /// Target X-axis tick count (clamped to 2…20).
        var xTickCount: Int = 5
        /// Target Y-axis tick count (clamped to 2…20).
        var yTickCount: Int = 5
    }

    let rendererSize: CGSize
    /// Plot grid area in CG renderer pixel space (origin bottom-left, Y increases upward).
    let gridRect: CGRect
    /// Vertical colorbar area in CG renderer pixel space.
    let colorbarRect: CGRect
    let titleCenter: CGPoint
    let xLabelCenter: CGPoint
    let yLabelCenter: CGPoint
    /// Center for the Z-axis (colorbar) label, rotated 90°. Positioned LEFT of the colorbar.
    let colorbarLabelCenter: CGPoint
    /// Whether the colorbar block (gradient, tick labels, Z title) should be rendered.
    let showColorbar: Bool
    /// Colorbar tick marks: (cgY position, formatted label string).
    let colorbarTicks: [(y: CGFloat, label: String)]
    /// Precomputed X-axis tick entries for the renderer.
    let xTickEntries: [(col: Int, label: String)]
    /// Precomputed Y-axis tick entries for the renderer.
    let yTickEntries: [(row: Int, label: String)]
    let zMin: Double
    let zMax: Double

    // MARK: - Factory

    static func compute(
        payload: HeatmapPlotPayload,
        options: Options = .init(),
        colorScaleMode: PlotScaleTransform = .linear,
        chartStyle: WorkbenchChartStyle? = nil,
        showColorbar: Bool = true
    ) -> HeatmapPlotLayout {
        var opts = options
        let style = chartStyle ?? WorkbenchChartStyle()

        let w = CGFloat(opts.width)
        let h = CGFloat(opts.height)

        let zMin: Double
        let zMax: Double
        if let lo = payload.zRangeClampMin, let hi = payload.zRangeClampMax, lo < hi {
            zMin = lo; zMax = hi
        } else {
            let allZ = payload.grid.zMatrix.flatMap { $0 }
            zMin = allZ.min() ?? 0
            zMax = allZ.max() ?? 1
        }

        // X/Y tick entries driven by tick count options
        let xTickEntries = Self.sampledXAxisTickEntries(for: payload.grid, targetCount: opts.xTickCount)
        let yTickEntries = Self.sampledYAxisTickEntries(for: payload.grid, targetCount: opts.yTickCount)

        // Always compute colorbar ticks for stable gridRect sizing (even when colorbar is hidden).
        let colorbarTickEntriesForMeasure = Self.makeColorbarTickEntries(
            zMin: zMin,
            zMax: zMax,
            mode: colorScaleMode
        )
        let maxColorbarTickLabelWidth = colorbarTickEntriesForMeasure.map {
            Self.measuredTextWidth(
                $0.label,
                fontSize: style.tickLabelFontSize,
                fontName: style.fontName,
                boldFontName: style.boldFontName
            )
        }.max() ?? 0

        let yTickLabels = yTickEntries.map(\.label)
        let maxYTickLabelWidth = yTickLabels.map {
            Self.measuredTextWidth(
                $0,
                fontSize: style.tickLabelFontSize,
                fontName: style.fontName,
                boldFontName: style.boldFontName
            )
        }.max() ?? 0

        let yAxisTitleTextWidth = payload.yLabel.isEmpty ? 0 : Self.measuredTextWidth(
            payload.yLabel,
            fontSize: style.axisTitleFontSize,
            fontName: style.fontName,
            boldFontName: style.boldFontName
        )

        // Z title only when colorbar is visible and label is non-empty.
        let zAxisLabelText = showColorbar && !payload.zLabel.isEmpty
            ? Self.renderedZLabel(payload.zLabel, mode: colorScaleMode)
            : ""
        let zAxisTitleTextWidth = zAxisLabelText.isEmpty ? 0 : Self.measuredTextWidth(
            zAxisLabelText,
            fontSize: style.axisTitleFontSize,
            fontName: style.fontName,
            boldFontName: style.boldFontName
        )

        let titleLaneMin: CGFloat = max(style.axisTitleFontSize * 1.25, 24)
        let yAxisTitleLaneWidth = yAxisTitleTextWidth > 0 ? max(yAxisTitleTextWidth, titleLaneMin) : 0
        let zAxisTitleLaneWidth = zAxisTitleTextWidth > 0 ? max(zAxisTitleTextWidth, titleLaneMin) : 0
        let titleToTickGap: CGFloat = 10
        let tickToPlotGap: CGFloat = 8
        let colorbarTickLabelGap: CGFloat = 8
        let minGridWidth: CGFloat = 180
        let maxSideInset = max(96, (w - minGridWidth) / 2)

        let desiredLeft = yAxisTitleLaneWidth + titleToTickGap + maxYTickLabelWidth + tickToPlotGap
        // paddingRight is computed from colorbar metrics (Z title is LEFT of colorbar, not in paddingRight).
        // Always use the measured tick label width so gridRect stays stable across showColorbar toggles.
        let desiredRight = opts.colorbarGap + opts.colorbarWidth + colorbarTickLabelGap + maxColorbarTickLabelWidth

        opts.paddingLeft = clamp(desiredLeft, lower: options.paddingLeft, upper: maxSideInset)
        opts.paddingRight = clamp(desiredRight, lower: options.paddingRight, upper: maxSideInset)

        if w - opts.paddingLeft - opts.paddingRight < minGridWidth {
            let shortage = minGridWidth - (w - opts.paddingLeft - opts.paddingRight)
            let rightRoom = max(0, opts.paddingRight - options.paddingRight)
            let reduceRight = min(shortage, rightRoom)
            opts.paddingRight -= reduceRight
            let remainingShortage = shortage - reduceRight
            if remainingShortage > 0 {
                let leftRoom = max(0, opts.paddingLeft - options.paddingLeft)
                let reduceLeft = min(remainingShortage, leftRoom)
                opts.paddingLeft -= reduceLeft
            }
        }

        let gridRect = CGRect(
            x: opts.paddingLeft,
            y: opts.paddingBottom,
            width:  max(0, w - opts.paddingLeft - opts.paddingRight),
            height: max(0, h - opts.paddingTop - opts.paddingBottom)
        )

        // Colorbar placement — Z title sits LEFT of colorbar:
        // [gridRect] [zTitleGapBefore] [zTitle] [zTitleGapAfter] [colorbar] [tickGap] [tickLabels]
        // When no Z title: [gridRect] [colorbarGap] [colorbar] [tickGap] [tickLabels]
        let zTitleGapBefore: CGFloat = 12
        let zTitleGapAfter: CGFloat = 8

        let colorbarRect: CGRect
        let colorbarLabelCenter: CGPoint
        let colorbarTicks: [(y: CGFloat, label: String)]

        if showColorbar {
            let colorbarMinX: CGFloat
            let labelCenterX: CGFloat
            if zAxisTitleLaneWidth > 0 {
                colorbarMinX = gridRect.maxX + zTitleGapBefore + zAxisTitleLaneWidth + zTitleGapAfter
                labelCenterX = gridRect.maxX + zTitleGapBefore + zAxisTitleLaneWidth * 0.5
            } else {
                colorbarMinX = gridRect.maxX + opts.colorbarGap
                labelCenterX = 0  // no Z title to render
            }

            colorbarRect = CGRect(
                x: colorbarMinX,
                y: gridRect.minY,
                width:  opts.colorbarWidth,
                height: gridRect.height
            )
            colorbarLabelCenter = CGPoint(x: labelCenterX, y: gridRect.midY)
            colorbarTicks = colorbarTickEntriesForMeasure.map { entry in
                let y = colorbarRect.minY + entry.normalizedY * colorbarRect.height
                return (y: y, label: entry.label)
            }
        } else {
            colorbarRect = CGRect.zero
            colorbarLabelCenter = CGPoint.zero
            colorbarTicks = []
        }

        let titleCenter = CGPoint(x: gridRect.midX, y: h - opts.paddingTop * 0.45)
        let xLabelCenter = CGPoint(x: gridRect.midX, y: opts.paddingBottom * 0.35)
        let yLabelCenter = CGPoint(
            x: yAxisTitleLaneWidth > 0 ? yAxisTitleLaneWidth * 0.5 : max(0, opts.paddingLeft * 0.28),
            y: gridRect.midY
        )

        // Renderer canvas — expand to fit colorbar and Z title lane when visible.
        let rendererWidth: CGFloat
        if showColorbar {
            let rightEdge = colorbarRect.maxX + colorbarTickLabelGap + maxColorbarTickLabelWidth
            rendererWidth = max(w, rightEdge + 16)
        } else {
            rendererWidth = w
        }

        return HeatmapPlotLayout(
            rendererSize:        CGSize(width: rendererWidth, height: h),
            gridRect:            gridRect,
            colorbarRect:        colorbarRect,
            titleCenter:         titleCenter,
            xLabelCenter:        xLabelCenter,
            yLabelCenter:        yLabelCenter,
            colorbarLabelCenter: colorbarLabelCenter,
            showColorbar:        showColorbar,
            colorbarTicks:       colorbarTicks,
            xTickEntries:        xTickEntries,
            yTickEntries:        yTickEntries,
            zMin:                zMin,
            zMax:                zMax
        )
    }

    // MARK: - Tick utilities

    static func sampledXAxisTickEntries(for grid: HeatmapGrid, targetCount: Int = 8) -> [(col: Int, label: String)] {
        let nX = grid.nX
        guard nX > 0 else { return [] }
        let step = max(1, nX / max(1, targetCount))
        return stride(from: 0, to: nX, by: step).map { col in
            (col: col, label: formatAxisValue(grid.xValues[col]))
        }
    }

    static func sampledYAxisTickEntries(for grid: HeatmapGrid, targetCount: Int = 8) -> [(row: Int, label: String)] {
        let nY = grid.nY
        guard nY > 0 else { return [] }
        let step = max(1, nY / max(1, targetCount))
        return stride(from: 0, to: nY, by: step).map { row in
            (row: row, label: formatAxisValue(grid.yValues[row]))
        }
    }

    static func measuredTextWidth(
        _ text: String,
        fontSize: CGFloat,
        fontName: String,
        boldFontName: String
    ) -> CGFloat {
        _ = boldFontName
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
        ]
        let attrStr = CFAttributedStringCreate(
            kCFAllocatorDefault, text as CFString, attrs as CFDictionary
        )!
        let line = CTLineCreateWithAttributedString(attrStr)
        return CTLineGetBoundsWithOptions(line, []).width
    }

    static func renderedZLabel(_ label: String, mode: PlotScaleTransform) -> String {
        label
    }

    static func makeColorbarTickEntries(
        zMin: Double,
        zMax: Double,
        mode: PlotScaleTransform
    ) -> [(normalizedY: CGFloat, label: String)] {
        let tickScale = HeatmapColorScale(zMin: zMin, zMax: zMax, mode: mode, colormapKey: "viridis")
        switch mode {
        case .linear:
            let tickValues = niceTicks(min: zMin, max: zMax, targetCount: 5)
            let span = zMax - zMin
            return tickValues.map { z in
                let t = tickScale.normalizedValue(for: z)
                return (CGFloat(t), formatLinearTickValue(z, range: span))
            }

        case .log10:
            if let domain = PlotScaleTransform.log10Domain(lowerBound: zMin, upperBound: zMax) {
                let logMin = Darwin.log10(domain.min)
                let logMax = Darwin.log10(domain.max)
                let expTicks = niceTicks(min: logMin, max: logMax, targetCount: 5)
                return expTicks.map { exponent in
                    let z = pow(10.0, exponent)
                    let t = tickScale.normalizedValue(for: z)
                    return (CGFloat(t), formatLogTickValue(z))
                }
            } else {
                let tickValues = niceTicks(min: zMin, max: zMax, targetCount: 5)
                let span = zMax - zMin
                return tickValues.map { z in
                    let t = tickScale.normalizedValue(for: z)
                    return (CGFloat(t), formatLinearTickValue(z, range: span))
                }
            }
        }
    }

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
            return "1e\(expInt)"
        }
        return String(format: "%.2ge%d", mantissa, expInt)
    }

    static func formatAxisValue(_ value: Double) -> String {
        if abs(value) >= 1e4 || (abs(value) > 0 && abs(value) < 0.01) {
            return String(format: "%.2g", value)
        } else if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.3g", value)
        }
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(lower, upper))
    }
}
