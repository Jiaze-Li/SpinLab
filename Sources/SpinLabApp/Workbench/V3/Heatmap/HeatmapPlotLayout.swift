import CoreGraphics
import Foundation

/// Selects how colorbar tick labels are generated. Display-only — never affects the
/// actual color-to-value mapping (`colorScaleMode`), only how tick values are formatted.
enum HeatmapColorbarTickStyle: Sendable, Equatable {
    /// Ticks are derived directly from `colorScaleMode` (nice linear or log10 values).
    case standard
    /// `zMin`/`zMax` are already `log10(rawIntensity + 1)` values (e.g. from
    /// `HeatmapGridInterpolator.logSpace` display smoothing). Ticks are generated as nice
    /// values over that log-space domain but labeled as powers of ten of the *original*
    /// intensity (10^0, 10^1, ...), since colors are mapped linearly over the log values.
    case powerOfTenFromLogValues
    /// Displays only the top and bottom endpoints (e.g. for Gwyddion-style colorbars).
    /// `decimals`: Number of decimal places to format endpoints with (default: 2).
    /// Shifts colorbar rightwards by 20.57 pt (+100 px at 350 dpi).
    case endpointsOnly(decimals: Int = 2, unit: String = "")
    /// AFM Z colorbar: 5 evenly spaced height ticks (both limits always included),
    /// numbers on the right of the bar, the unit written once after the upper-limit value. Same large
    /// right-hand typography and rightward shift as `endpointsOnly`.
    case zHeightTicks(unit: String = "")

    /// True for the AFM-style colorbars (large fixed label font, shifted bar).
    var usesAFMColorbarTypography: Bool {
        switch self {
        case .endpointsOnly, .zHeightTicks: return true
        case .standard, .powerOfTenFromLogValues: return false
        }
    }

    var isZHeightTicks: Bool {
        if case .zHeightTicks = self { return true }
        return false
    }

    /// Unit written once, on the same line as the top (upper-limit) label (empty = none).
    var colorbarUnit: String {
        if case .zHeightTicks(let unit) = self { return unit }
        return ""
    }
}

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
        /// Shared tick count configuration for X and Y axes.
        var tickConfiguration: PlotTickConfiguration = .defaultValue
        /// Aspect ratio policy for the plot grid. Nil = use payload.aspectPolicy.
        var aspectPolicy: HeatmapAspectPolicy? = nil
        /// Whether spatial axes (ticks, tick labels, axis labels) should be hidden.
        var hideSpatialAxes: Bool = false
        /// Optional scale bar overlay configuration.
        var scaleBarOverlay: HeatmapScaleBarOverlay? = nil
    }

    /// Top margin reserved above the grid when the title is hidden — just breathing
    /// room, not a text lane. Mirrors WorkbenchPlotLayout / DualAxisPlotLayout.
    static let noTitleTopPadding: CGFloat = 24

    let rendererSize: CGSize
    /// Plot grid area in CG renderer pixel space (origin bottom-left, Y increases upward).
    let gridRect: CGRect
    /// Vertical colorbar area in CG renderer pixel space.
    let colorbarRect: CGRect
    let titleCenter: CGPoint
    /// Whether the chart title should be drawn. When false, no top padding is
    /// reserved for it either. Parallel to `showColorbar`.
    let showTitle: Bool
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
    let aspectPolicy: HeatmapAspectPolicy
    /// Whether spatial axes (X and Y ticks, tick labels, axis titles) should be hidden.
    let hideSpatialAxes: Bool
    /// Optional scale bar overlay (drawn inside lower-left of grid).
    let scaleBarOverlay: HeatmapScaleBarOverlay?

    // MARK: - Factory

    static func compute(
        payload: HeatmapPlotPayload,
        options: Options = .init(),
        colorScaleMode: PlotScaleTransform = .linear,
        chartStyle: WorkbenchChartStyle? = nil,
        showColorbar: Bool = true,
        showTitle: Bool = true,
        colorbarTickStyle: HeatmapColorbarTickStyle = .standard,
        aspectPolicy: HeatmapAspectPolicy? = nil
    ) -> HeatmapPlotLayout {
        var opts = options
        let style = chartStyle ?? WorkbenchChartStyle()

        let w = CGFloat(opts.width)
        let h = CGFloat(opts.height)
        let effectivePaddingTop = showTitle ? opts.paddingTop : Self.noTitleTopPadding

        let zMin: Double
        let zMax: Double
        if let lo = payload.zRangeClampMin, let hi = payload.zRangeClampMax, lo < hi {
            zMin = lo; zMax = hi
        } else {
            let allZ = payload.grid.zMatrix.flatMap { $0 }
            zMin = allZ.min() ?? 0
            zMax = allZ.max() ?? 1
        }

        let effectiveHideSpatialAxes = options.hideSpatialAxes || payload.hideSpatialAxes
        let effectiveScaleBarOverlay = options.scaleBarOverlay ?? payload.scaleBarOverlay

        // X/Y tick entries driven by tick count options (empty when spatial axes hidden)
        let xTickEntries: [(col: Int, label: String)]
        let yTickEntries: [(row: Int, label: String)]
        if effectiveHideSpatialAxes {
            xTickEntries = []
            yTickEntries = []
        } else {
            xTickEntries = Self.sampledXAxisTickEntries(for: payload.grid, targetCount: opts.tickConfiguration.xTargetCount)
            yTickEntries = Self.sampledYAxisTickEntries(for: payload.grid, targetCount: opts.tickConfiguration.yTargetCount)
        }

        // Always compute colorbar ticks using standard style for stable gridRect sizing
        // (even when colorbar is hidden or endpointsOnly is active).
        let colorbarTickEntriesForMeasure = Self.makeColorbarTickEntries(
            zMin: zMin,
            zMax: zMax,
            mode: colorScaleMode
        )
        let isEndpointsStyle: Bool
        isEndpointsStyle = colorbarTickStyle.usesAFMColorbarTypography
        let tickLabelFontSize = style.tickLabelFontSize
        let maxColorbarTickLabelWidth = colorbarTickEntriesForMeasure.map {
            Self.measuredTextWidth(
                $0.label,
                fontSize: tickLabelFontSize,
                fontName: style.fontName,
                boldFontName: style.boldFontName
            )
        }.max() ?? 0

        let yAxisLane: PlotYAxisLaneLayout
        if effectiveHideSpatialAxes {
            yAxisLane = PlotYAxisLaneLayout(
                maxTickLabelWidth: 0,
                axisTitleTextWidth: 0,
                axisTitleLaneWidth: 0,
                requiredLeftPadding: opts.paddingLeft,
                titleCenterX: 0,
                tickLabelLaneLeadingX: 0,
                tickLabelLaneTrailingX: 0
            )
        } else {
            let yTickLabels = yTickEntries.map(\.label)
            yAxisLane = PlotAxisSpacingCalculator.yAxisLane(
                axisTitleText: payload.yLabel,
                tickLabels: yTickLabels,
                axisTitleFontSize: style.axisTitleFontSize,
                axisTitleFontName: style.fontName,
                axisTitleBold: false,
                axisTitleBoldFontName: style.boldFontName,
                tickLabelFontSize: style.tickLabelFontSize,
                tickLabelFontName: style.fontName,
                tickLabelBold: false,
                tickLabelBoldFontName: style.boldFontName,
                minimumAxisTitleLane: max(style.axisTitleFontSize * 1.25, 24),
                titleToTickGap: 10,
                tickToPlotGap: 8,
                baseLeftPadding: opts.paddingLeft,
                maxSideInset: max(96, (w - 180) / 2)
            )
        }

        // Z title only when colorbar is visible and label is non-empty.
        let zAxisLabelText = showColorbar && !payload.zLabel.isEmpty
            ? Self.renderedZLabel(payload.zLabel, mode: colorScaleMode)
            : ""
        let zAxisTitleTextWidth = zAxisLabelText.isEmpty ? 0 : PlotTextMeasurer.measuredWidth(
            zAxisLabelText,
            fontSize: style.axisTitleFontSize,
            fontName: style.fontName,
            boldFontName: style.boldFontName
        )

        let titleLaneMin: CGFloat = max(style.axisTitleFontSize * 1.25, 24)
        // The Z title is rotated 90°, so the lane it occupies is one text line tall, not as wide
        // as the unrotated string.
        // Endpoint-only colorbars (AFM) reserve just one rotated text line; other styles keep
        // their established lane width.
        let zAxisTitleLaneWidth = zAxisTitleTextWidth > 0
            ? (isEndpointsStyle ? titleLaneMin : max(zAxisTitleTextWidth, titleLaneMin))
            : 0
        let colorbarTickLabelGap: CGFloat = 8
        let minGridWidth: CGFloat = 180
        let maxSideInset = max(96, (w - minGridWidth) / 2)

        let desiredLeft = yAxisLane.requiredLeftPadding
        // paddingRight is computed from colorbar metrics (Z title is LEFT of colorbar, not in paddingRight).
        // Always use the measured tick label width so gridRect stays stable across showColorbar toggles.
        var colorbarRightShift: CGFloat = 0
        if colorbarTickStyle.usesAFMColorbarTypography {
            // Rightward shift: +100 px at 350 dpi = 100 * 72 / 350 ≈ 20.5714 pt
            colorbarRightShift = 100.0 / 350.0 * 72.0
        }
        let desiredRight = opts.colorbarGap + opts.colorbarWidth + colorbarTickLabelGap + maxColorbarTickLabelWidth

        // With spatial axes hidden there is no Y tick/title lane: keep only breathing room.
        opts.paddingLeft = effectiveHideSpatialAxes
            ? Self.noTitleTopPadding
            : clamp(desiredLeft, lower: options.paddingLeft, upper: maxSideInset)
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

        let availableWidth = max(0, w - opts.paddingLeft - opts.paddingRight)
        let effectivePaddingBottom = effectiveHideSpatialAxes ? Self.noTitleTopPadding : opts.paddingBottom
        let availableHeight = max(0, h - effectivePaddingTop - effectivePaddingBottom)

        let resolvedAspectPolicy = aspectPolicy ?? opts.aspectPolicy ?? payload.aspectPolicy
        let gridRect: CGRect
        let rendererHeight: CGFloat

        switch resolvedAspectPolicy {
        case .fill:
            gridRect = CGRect(
                x: opts.paddingLeft,
                y: effectivePaddingBottom,
                width: availableWidth,
                height: availableHeight
            )
            rendererHeight = h

        case .physical:
            if let dataAspect = payload.grid.physicalDataAspectRatio,
               dataAspect > 0, availableWidth > 0, availableHeight > 0 {
                let currentAspect = availableWidth / availableHeight
                let gridW: CGFloat
                let gridH: CGFloat
                if currentAspect > CGFloat(dataAspect) {
                    // Height is the constraint
                    gridH = availableHeight
                    gridW = availableHeight * CGFloat(dataAspect)
                } else {
                    // Width is the constraint
                    gridW = availableWidth
                    gridH = availableWidth / CGFloat(dataAspect)
                }
                gridRect = CGRect(
                    x: opts.paddingLeft,
                    y: effectivePaddingBottom,
                    width: gridW,
                    height: gridH
                )
                rendererHeight = gridRect.maxY + effectivePaddingTop
            } else {
                gridRect = CGRect(
                    x: opts.paddingLeft,
                    y: effectivePaddingBottom,
                    width: availableWidth,
                    height: availableHeight
                )
                rendererHeight = h
            }
        }

        // Colorbar placement — Z title sits LEFT of colorbar:
        // [gridRect] [zTitleGapBefore] [zTitle] [zTitleGapAfter] [colorbar] [tickGap] [tickLabels]
        // When no Z title: [gridRect] [colorbarGap] [colorbar] [tickGap] [tickLabels]
        let zTitleGapBefore: CGFloat = 6
        let zTitleGapAfter: CGFloat = 6

        let colorbarRect: CGRect
        let colorbarLabelCenter: CGPoint
        let colorbarTicks: [(y: CGFloat, label: String)]

        if showColorbar {
            let colorbarMinX: CGFloat
            let labelCenterX: CGFloat
            if zAxisTitleLaneWidth > 0 {
                colorbarMinX = gridRect.maxX + zTitleGapBefore + zAxisTitleLaneWidth + zTitleGapAfter + colorbarRightShift
                labelCenterX = gridRect.maxX + zTitleGapBefore + zAxisTitleLaneWidth * 0.5 + colorbarRightShift
            } else {
                colorbarMinX = gridRect.maxX + opts.colorbarGap + colorbarRightShift
                labelCenterX = 0  // no Z title to render
            }

            colorbarRect = CGRect(
                x: colorbarMinX,
                y: gridRect.minY,
                width:  opts.colorbarWidth,
                height: gridRect.height
            )
            colorbarLabelCenter = CGPoint(x: labelCenterX, y: gridRect.midY)
            let activeTickEntries: [(normalizedY: CGFloat, label: String)]
            switch colorbarTickStyle {
            case .standard:
                activeTickEntries = colorbarTickEntriesForMeasure
            case .powerOfTenFromLogValues:
                activeTickEntries = Self.makePowerOfTenColorbarTickEntries(
                    logZMin: zMin,
                    logZMax: zMax
                )
            case .endpointsOnly(let decimals, let unit):
                activeTickEntries = Self.makeEndpointsColorbarTickEntries(
                    zMin: zMin,
                    zMax: zMax,
                    decimals: decimals,
                    unit: unit
                )
            case .zHeightTicks:
                activeTickEntries = Self.makeZHeightColorbarTickEntries(
                    zMin: zMin,
                    zMax: zMax,
                    minNormalizedGap: Self.zHeightLabelFontSize * 1.15 / max(colorbarRect.height, 1),
                    topUnit: colorbarTickStyle.colorbarUnit
                )
            }

            // AFM Z ticks are stroked 2 pt wide: keep the whole stroke inside the bar by
            // placing the end tick centres half a line width in from the bar edges.
            let tickInset: CGFloat = colorbarTickStyle.isZHeightTicks ? Self.zHeightTickWidth / 2 : 0
            let tickSpan = max(colorbarRect.height - 2 * tickInset, 0)
            colorbarTicks = activeTickEntries.map { entry in
                let y = colorbarRect.minY + tickInset + entry.normalizedY * tickSpan
                return (y: y, label: entry.label)
            }
        } else {
            colorbarRect = CGRect.zero
            colorbarLabelCenter = CGPoint.zero
            colorbarTicks = []
        }

        let titleCenter = CGPoint(x: gridRect.midX, y: gridRect.maxY + effectivePaddingTop * 0.55)
        let xLabelCenter = CGPoint(x: gridRect.midX, y: effectivePaddingBottom * 0.35)
        let yLabelCenter = CGPoint(
            x: yAxisLane.titleCenterX,
            y: gridRect.midY
        )

        // Renderer canvas — expand to fit colorbar and Z title lane when visible.
        let rendererWidth: CGFloat
        if showColorbar {
            // Endpoint labels are drawn at a larger fixed font (see HeatmapRenderer): reserve
            // canvas for the real label width so they are never clipped.
            var rightLabelWidth = maxColorbarTickLabelWidth
            if case .endpointsOnly(let decimals, let unit) = colorbarTickStyle {
                let endpointWidth = Self.makeEndpointsColorbarTickEntries(zMin: zMin, zMax: zMax, decimals: decimals, unit: unit)
                    .map { Self.measuredTextWidth($0.label, fontSize: 29.0, fontName: style.fontName, boldFontName: style.boldFontName) }
                    .max() ?? 0
                rightLabelWidth = max(rightLabelWidth, endpointWidth)
            } else if colorbarTickStyle.isZHeightTicks {
                let column = Self.zHeightLabelColumn(
                    labels: colorbarTicks.map(\.label), fontSize: Self.zHeightLabelFontSize,
                    fontName: style.fontName, boldFontName: style.boldFontName)
                // Labels start zHeightTickLength + zHeightLabelGap right of the bar, further than the
                // standard colorbar's gap.
                rightLabelWidth = max(rightLabelWidth, column.width + max(0, Self.zHeightTickLength + Self.zHeightLabelGap - colorbarTickLabelGap))
            }
            let rightEdge = colorbarRect.maxX + colorbarTickLabelGap + rightLabelWidth
            rendererWidth = max(gridRect.maxX + opts.paddingRight, rightEdge + 16)
        } else {
            rendererWidth = gridRect.maxX + opts.paddingRight
        }

        return HeatmapPlotLayout(
            rendererSize:        CGSize(width: rendererWidth, height: rendererHeight),
            gridRect:            gridRect,
            colorbarRect:        colorbarRect,
            titleCenter:         titleCenter,
            showTitle:           showTitle,
            xLabelCenter:        xLabelCenter,
            yLabelCenter:        yLabelCenter,
            colorbarLabelCenter: colorbarLabelCenter,
            showColorbar:        showColorbar,
            colorbarTicks:       colorbarTicks,
            xTickEntries:        xTickEntries,
            yTickEntries:        yTickEntries,
            zMin:                zMin,
            zMax:                zMax,
            aspectPolicy:        resolvedAspectPolicy,
            hideSpatialAxes:     effectiveHideSpatialAxes,
            scaleBarOverlay:     Self.resolveScaleBar(effectiveScaleBarOverlay, grid: payload.grid, gridRect: gridRect)
        )
    }

    // MARK: - Tick utilities

    static func makeEndpointsColorbarTickEntries(
        zMin: Double,
        zMax: Double,
        decimals: Int = 2,
        unit: String = ""
    ) -> [(normalizedY: CGFloat, label: String)] {
        let suffix = unit.isEmpty ? "" : " \(unit)"
        let minLabel = formatEndpointValue(zMin, decimals: decimals) + suffix
        let maxLabel = formatEndpointValue(zMax, decimals: decimals) + suffix
        return [
            (normalizedY: 0.0, label: minLabel),
            (normalizedY: 1.0, label: maxLabel)
        ]
    }

    /// Font size of the AFM-style colorbar labels (tick numbers and the single unit).
    static let zHeightLabelFontSize: CGFloat = 29.0
    /// AFM Z colorbar tick marks: pure black, clearly visible without overpowering the bar.
    static let zHeightTickLength: CGFloat = 8
    static let zHeightTickWidth: CGFloat = 2.0
    /// Clear space between the end of a tick mark and the label column (3 pt before + 5 pt).
    static let zHeightLabelGap: CGFloat = 8

    /// Horizontal geometry of the AFM Z label column. Numbers are aligned on the decimal point; a
    /// leading minus hangs to the left of the number body and takes no part in the alignment.
    /// All widths are real Arial glyph advances (no padding characters).
    struct ZHeightLabelColumn {
        /// Width reserved left of the number column for the minus (0 when no label is negative).
        let signWidth: CGFloat
        /// Per label: width of the minus (0 if none), integer part up to the decimal point, whole body.
        let parts: [(sign: CGFloat, integer: CGFloat, body: CGFloat)]
        let maxInteger: CGFloat
        /// Distance from the column's left edge to the right-most ink of the widest label.
        let width: CGFloat

        /// X of the body's first glyph, relative to the column's left edge.
        func bodyOffset(_ i: Int) -> CGFloat { signWidth + maxInteger - parts[i].integer }
        /// X of the minus glyph, relative to the column's left edge (drawn directly left of the body).
        func signOffset(_ i: Int) -> CGFloat { bodyOffset(i) - parts[i].sign }
    }

    static func splitZHeightLabel(_ label: String) -> (sign: String, body: String, integer: String) {
        let sign = label.hasPrefix("−") ? "−" : ""
        let body = String(label.dropFirst(sign.count))
        let integer = String(body.prefix { $0 != "." && $0 != "\u{00A0}" })
        return (sign, body, integer)
    }

    static func zHeightLabelColumn(labels: [String], fontSize: CGFloat, fontName: String, boldFontName: String) -> ZHeightLabelColumn {
        func w(_ t: String) -> CGFloat {
            t.isEmpty ? 0 : measuredTextWidth(t, fontSize: fontSize, fontName: fontName, boldFontName: boldFontName)
        }
        let parts = labels.map { l -> (sign: CGFloat, integer: CGFloat, body: CGFloat) in
            let sp = splitZHeightLabel(l)
            return (w(sp.sign), w(sp.integer), w(sp.body))
        }
        let signWidth = parts.map(\.sign).max() ?? 0
        let maxInteger = parts.map(\.integer).max() ?? 0
        let width = parts.map { signWidth + maxInteger - $0.integer + $0.body }.max() ?? 0
        return ZHeightLabelColumn(signWidth: signWidth, parts: parts, maxInteger: maxInteger, width: width)
    }
    /// Joins a value and its unit; the no-break space keeps them on one line.
    static let unitSeparator = "\u{00A0}"

    /// Default number of AFM Z colorbar ticks (both limits included).
    static let zHeightDefaultTickCount = 5

    /// AFM Z colorbar ticks: `zHeightDefaultTickCount` evenly spaced ticks from the true lower to
    /// the true upper Z limit (linear interpolation, so spacing on the bar is exactly uniform).
    /// When the bar is too short for that many labels (`minNormalizedGap`, a fraction of the bar
    /// height) the count is reduced, down to the two limits. Labels share one decimal count,
    /// chosen so no two labels are identical, and use a true minus sign. Labels are numbers only
    /// except the top one, which carries the unit once (`topUnit`, joined by a no-break space).
    static func makeZHeightColorbarTickEntries(
        zMin: Double,
        zMax: Double,
        minNormalizedGap: CGFloat = 0.06,
        topUnit: String = ""
    ) -> [(normalizedY: CGFloat, label: String)] {
        let span = zMax - zMin
        let unitSuffix = topUnit.isEmpty ? "" : unitSeparator + topUnit
        guard span > 0, span.isFinite else {
            return [(normalizedY: 0, label: formatEndpointValue(zMin) + unitSuffix)]
        }
        let gap = max(Double(minNormalizedGap), 0)
        var count = zHeightDefaultTickCount
        while count > 2, 1.0 / Double(count - 1) < gap { count -= 1 }

        func values(_ n: Int) -> [Double] {
            var result: [Double] = []
            result.reserveCapacity(n)

            for i in 0..<n {
                if i == 0 {
                    result.append(zMin)
                } else if i == n - 1 {
                    result.append(zMax)
                } else {
                    let fraction: Double = Double(i) / Double(n - 1)
                    result.append(zMin + span * fraction)
                }
            }

            return result
        }
        func texts(_ vals: [Double], decimals: Int) -> [String] {
            vals.map { v in
                let text = formatEndpointValue(v, decimals: decimals)
                return text == "−" + formatEndpointValue(0, decimals: decimals) ? formatEndpointValue(0, decimals: decimals) : text
            }
        }
        // Fewest decimals (at least 2) that keep every label distinct; on a very small span
        // that is the only way to tell neighbouring ticks apart.
        var vals = values(count)
        var decimals = 2
        var labels = texts(vals, decimals: decimals)
        // Rounding must also stay within 2.5 % of the bar so a label sits where its value is.
        while pow(10.0, -Double(decimals)) > span / 20, decimals < 8 {
            decimals += 1
        }
        labels = texts(vals, decimals: decimals)
        while Set(labels).count < labels.count, decimals < 8 {
            decimals += 1
            labels = texts(vals, decimals: decimals)
        }
        if Set(labels).count < labels.count {
            // Span is below display resolution: fall back to the two limits.
            count = 2
            vals = values(2)
            labels = texts(vals, decimals: decimals)
        }
        var entries: [(normalizedY: CGFloat, label: String)] = []
        for (i, v) in vals.enumerated() {
            let t = i == 0 ? 0 : (i == vals.count - 1 ? 1 : (v - zMin) / span)
            entries.append((CGFloat(t), labels[i] + (i == vals.count - 1 ? unitSuffix : "")))
        }
        return entries
    }

    static func formatEndpointValue(_ value: Double, decimals: Int = 2) -> String {
        let formatStr = "%.\(decimals)f"
        var formatted = String(format: formatStr, value)
        if formatted.hasPrefix("-") {
            formatted = "−" + formatted.dropFirst()
        }
        return formatted
    }

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
        PlotTextMeasurer.measuredWidth(
            text,
            fontSize: fontSize,
            fontName: fontName,
            boldFontName: boldFontName
        )
    }

    static func renderedZLabel(_ label: String, mode: PlotScaleTransform) -> String {
        label
    }

    /// Converts a physical-length scale bar into points using the exact cell mapping the
    /// renderer draws: nX equal cells spanning the full grid width, one pixel pitch per cell.
    static func resolveScaleBar(
        _ overlay: HeatmapScaleBarOverlay?,
        grid: HeatmapGrid,
        gridRect: CGRect
    ) -> HeatmapScaleBarOverlay? {
        guard var overlay else { return nil }
        guard let physical = overlay.physicalLength else { return overlay }
        guard grid.nX > 1, let minX = grid.xValues.min(), let maxX = grid.xValues.max(), maxX > minX else {
            return nil
        }
        let pitch = (maxX - minX) / Double(grid.nX - 1)
        let fullWidth = pitch * Double(grid.nX)
        let points = CGFloat(physical / fullWidth) * gridRect.width
        guard points.isFinite, points > 0, points < gridRect.width else { return nil }
        overlay.lengthInPoints = points
        return overlay
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

    /// Returns colorbar tick entries for a colorbar whose `zMatrix` already holds
    /// `log10(rawIntensity + 1)` values and is colored *linearly* over that domain
    /// (`logZMin`...`logZMax`). Tick positions are nice values in log space; labels show
    /// the corresponding original intensity as a power of ten (10^0, 10^1, ...).
    static func makePowerOfTenColorbarTickEntries(
        logZMin: Double,
        logZMax: Double
    ) -> [(normalizedY: CGFloat, label: String)] {
        guard logZMax > logZMin else { return [] }
        let tickScale = HeatmapColorScale(zMin: logZMin, zMax: logZMax, mode: .linear, colormapKey: "viridis")
        let exponentTicks = niceTicks(min: logZMin, max: logZMax, targetCount: 5)
        return exponentTicks.map { exponent in
            let t = tickScale.normalizedValue(for: exponent)
            return (CGFloat(t), formatPowerOfTenTickValue(exponent))
        }
    }

    /// Formats a log10 exponent as a power-of-ten label, e.g. `2.0` → `"10^2"`.
    /// Non-integer exponents (rare — only when `niceTicks` picks a fractional step) keep
    /// one decimal place, e.g. `"10^2.5"`.
    static func formatPowerOfTenTickValue(_ exponent: Double) -> String {
        let rounded = exponent.rounded()
        if abs(exponent - rounded) < 1e-6 {
            return "10^\(Int(rounded))"
        }
        return String(format: "10^%.1f", exponent)
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
