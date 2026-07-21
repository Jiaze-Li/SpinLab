import Foundation
import CoreGraphics
import CoreText

/// Shared CoreText text measurement and axis-spacing helpers for plot layouts.
///
/// This file deliberately owns only generic plot-axis geometry. It knows nothing
/// about RSM, heatmap colorbars, or XY series rendering.
struct PlotTextMeasurer {

    static func measuredWidth(
        _ text: String,
        fontSize: CGFloat,
        fontName: String,
        bold: Bool = false,
        boldFontName: String? = nil
    ) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        if MathMarkupRenderer.isMathLabel(text) {
            return MathMarkupRenderer.measuredWidth(
                text: MathMarkupRenderer.extractMathMarkup(text),
                size: fontSize,
                fontName: fontName
            )
        }
        if MathMarkupRenderer.containsMarkup(text) {
            return MathMarkupRenderer.measuredWidth(text: text, size: fontSize, fontName: fontName)
        }
        let resolvedFontName = bold ? (boldFontName ?? fontName) : fontName
        let font = CTFontCreateWithName(resolvedFontName as CFString, fontSize, nil)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
        ]
        guard let attrStr = CFAttributedStringCreate(
            kCFAllocatorDefault, text as CFString, attrs as CFDictionary
        ) else { return 0 }
        let line = CTLineCreateWithAttributedString(attrStr)
        return max(0, CTLineGetBoundsWithOptions(line, []).width)
    }

    static func measuredLineHeight(
        fontSize: CGFloat,
        fontName: String,
        bold: Bool = false,
        boldFontName: String? = nil
    ) -> CGFloat {
        let resolvedFontName = bold ? (boldFontName ?? fontName) : fontName
        let font = CTFontCreateWithName(resolvedFontName as CFString, fontSize, nil)
        return CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

    static func measuredCapHeight(
        fontSize: CGFloat,
        fontName: String,
        bold: Bool = false,
        boldFontName: String? = nil
    ) -> CGFloat {
        let resolvedFontName = bold ? (boldFontName ?? fontName) : fontName
        let font = CTFontCreateWithName(resolvedFontName as CFString, fontSize, nil)
        return CTFontGetCapHeight(font)
    }

    static func measuredMathMarkupHeight(
        _ text: String,
        fontSize: CGFloat,
        fontName: String
    ) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        var style = WorkbenchChartStyle()
        style.fontName = fontName
        let line = MathMarkupRenderer.makeLine(
            text: text,
            size: fontSize,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            style: style
        )
        return max(0, CTLineGetBoundsWithOptions(line, []).height)
    }

    static func maxTickLabelWidth(
        _ tickLabels: [String],
        fontSize: CGFloat,
        fontName: String,
        bold: Bool = false,
        boldFontName: String? = nil
    ) -> CGFloat {
        tickLabels
            .map {
                measuredWidth(
                    $0,
                    fontSize: fontSize,
                    fontName: fontName,
                    bold: bold,
                    boldFontName: boldFontName
                )
            }
            .max() ?? 0
    }
}

struct PlotYAxisLaneLayout: Sendable {
    let maxTickLabelWidth: CGFloat
    let axisTitleTextWidth: CGFloat
    let axisTitleLaneWidth: CGFloat
    let requiredLeftPadding: CGFloat
    let titleCenterX: CGFloat
    let tickLabelLaneLeadingX: CGFloat
    let tickLabelLaneTrailingX: CGFloat
}

struct PlotXAxisLaneLayout: Sendable {
    let maxTickLabelWidth: CGFloat
    let axisTitleTextWidth: CGFloat
    let axisTitleLaneHeight: CGFloat
    let requiredBottomPadding: CGFloat
    let titleCenterY: CGFloat
    let tickLabelCenterY: CGFloat
    let tickLabelTopY: CGFloat
}

struct PlotAxisTick: Sendable {
    let value: Double
    let label: String
    let tickPoint: CGPoint
    let labelPoint: CGPoint
}

struct PlotAxisSpacingCalculator {

    static func yAxisLane(
        axisTitleText: String,
        tickLabels: [String],
        axisTitleFontSize: CGFloat,
        axisTitleFontName: String,
        axisTitleBold: Bool = false,
        axisTitleBoldFontName: String? = nil,
        tickLabelFontSize: CGFloat,
        tickLabelFontName: String,
        tickLabelBold: Bool = false,
        tickLabelBoldFontName: String? = nil,
        minimumAxisTitleLane: CGFloat,
        titleToTickGap: CGFloat,
        tickToPlotGap: CGFloat,
        baseLeftPadding: CGFloat,
        maxSideInset: CGFloat? = nil,
        titleCenterBias: CGFloat = 0.38
    ) -> PlotYAxisLaneLayout {
        let maxTickLabelWidth = PlotTextMeasurer.maxTickLabelWidth(
            tickLabels,
            fontSize: tickLabelFontSize,
            fontName: tickLabelFontName,
            bold: tickLabelBold,
            boldFontName: tickLabelBoldFontName
        )
        return yAxisLane(
            maxTickLabelWidth: maxTickLabelWidth,
            axisTitleText: axisTitleText,
            axisTitleFontSize: axisTitleFontSize,
            axisTitleFontName: axisTitleFontName,
            axisTitleBold: axisTitleBold,
            axisTitleBoldFontName: axisTitleBoldFontName,
            minimumAxisTitleLane: minimumAxisTitleLane,
            titleToTickGap: titleToTickGap,
            tickToPlotGap: tickToPlotGap,
            baseLeftPadding: baseLeftPadding,
            maxSideInset: maxSideInset,
            titleCenterBias: titleCenterBias
        )
    }

    static func yAxisLane(
        maxTickLabelWidth: CGFloat,
        axisTitleText: String,
        axisTitleFontSize: CGFloat,
        axisTitleFontName: String,
        axisTitleBold: Bool = false,
        axisTitleBoldFontName: String? = nil,
        minimumAxisTitleLane: CGFloat,
        titleToTickGap: CGFloat,
        tickToPlotGap: CGFloat,
        baseLeftPadding: CGFloat,
        maxSideInset: CGFloat? = nil,
        titleCenterBias: CGFloat = 0.38,
        mathLabelSizeOverride: CGSize? = nil
    ) -> PlotYAxisLaneLayout {
        let axisTitleTextWidth = PlotTextMeasurer.measuredWidth(
            axisTitleText,
            fontSize: axisTitleFontSize,
            fontName: axisTitleFontName,
            bold: axisTitleBold,
            boldFontName: axisTitleBoldFontName
        )
        // The Y-axis title is drawn rotated 90°. Its horizontal footprint equals
        // the label's rendered height (which becomes the horizontal dimension after rotation).
        // For math markup, measure the rendered math line height; otherwise use font line height.
        let axisTitleRotatedHorizontalFootprint: CGFloat
        if axisTitleText.isEmpty {
            axisTitleRotatedHorizontalFootprint = 0
        } else if MathMarkupRenderer.isMathLabel(axisTitleText) {
            let mathText = MathMarkupRenderer.extractMathMarkup(axisTitleText)
            axisTitleRotatedHorizontalFootprint = mathLabelSizeOverride?.height ??
                PlotTextMeasurer.measuredMathMarkupHeight(mathText, fontSize: axisTitleFontSize, fontName: axisTitleFontName)
        } else {
            axisTitleRotatedHorizontalFootprint = PlotTextMeasurer.measuredLineHeight(
                fontSize: axisTitleFontSize,
                fontName: axisTitleFontName,
                bold: axisTitleBold,
                boldFontName: axisTitleBoldFontName
            )
        }
        let axisTitleLaneWidth = axisTitleTextWidth > 0
            ? max(axisTitleRotatedHorizontalFootprint, minimumAxisTitleLane)
            : 0
        let desiredLeft = max(
            baseLeftPadding,
            axisTitleLaneWidth + titleToTickGap + maxTickLabelWidth + tickToPlotGap
        )
        let upperBound = maxSideInset ?? .greatestFiniteMagnitude
        let requiredLeftPadding = min(max(desiredLeft, baseLeftPadding), upperBound)
        let tickLabelLaneTrailingX = max(0, requiredLeftPadding - tickToPlotGap)
        let tickLabelLaneLeadingX = max(0, tickLabelLaneTrailingX - maxTickLabelWidth)

        let titleCenterX: CGFloat
        if axisTitleLaneWidth > 0 {
            let leftEdgeLimit = axisTitleLaneWidth / 2 + 4
            let rightEdgeLimit = tickLabelLaneLeadingX - titleToTickGap - axisTitleLaneWidth / 2
            let biasLimit = max(baseLeftPadding * titleCenterBias, leftEdgeLimit)
            titleCenterX = max(leftEdgeLimit, min(rightEdgeLimit, biasLimit))
        } else {
            titleCenterX = max(0, baseLeftPadding * titleCenterBias)
        }

        return PlotYAxisLaneLayout(
            maxTickLabelWidth: maxTickLabelWidth,
            axisTitleTextWidth: axisTitleTextWidth,
            axisTitleLaneWidth: axisTitleLaneWidth,
            requiredLeftPadding: requiredLeftPadding,
            titleCenterX: titleCenterX,
            tickLabelLaneLeadingX: tickLabelLaneLeadingX,
            tickLabelLaneTrailingX: tickLabelLaneTrailingX
        )
    }

    static func xAxisLane(
        axisTitleText: String,
        tickLabels: [String],
        axisTitleFontSize: CGFloat,
        axisTitleFontName: String,
        axisTitleBold: Bool = false,
        axisTitleBoldFontName: String? = nil,
        tickLabelFontSize: CGFloat,
        tickLabelFontName: String,
        tickLabelBold: Bool = false,
        tickLabelBoldFontName: String? = nil,
        minimumAxisTitleLane: CGFloat,
        titleToTickGap: CGFloat,
        tickToPlotGap: CGFloat,
        baseBottomPadding: CGFloat,
        maxSideInset: CGFloat? = nil,
        titleCenterBias: CGFloat = 0.58,
        mathLabelSizeOverride: CGSize? = nil
    ) -> PlotXAxisLaneLayout {
        let maxTickLabelWidth = PlotTextMeasurer.maxTickLabelWidth(
            tickLabels,
            fontSize: tickLabelFontSize,
            fontName: tickLabelFontName,
            bold: tickLabelBold,
            boldFontName: tickLabelBoldFontName
        )
        let axisTitleTextWidth = PlotTextMeasurer.measuredWidth(
            axisTitleText,
            fontSize: axisTitleFontSize,
            fontName: axisTitleFontName,
            bold: axisTitleBold,
            boldFontName: axisTitleBoldFontName
        )
        // For math markup and text labels it equals the rendered text height.
        let axisTitleLaneHeight: CGFloat
        if axisTitleText.isEmpty {
            axisTitleLaneHeight = 0
        } else if MathMarkupRenderer.isMathLabel(axisTitleText) {
            let mathText = MathMarkupRenderer.extractMathMarkup(axisTitleText)
            axisTitleLaneHeight = max(
                mathLabelSizeOverride?.height ??
                    PlotTextMeasurer.measuredMathMarkupHeight(mathText, fontSize: axisTitleFontSize, fontName: axisTitleFontName),
                minimumAxisTitleLane
            )
        } else {
            axisTitleLaneHeight = max(PlotTextMeasurer.measuredLineHeight(
                fontSize: axisTitleFontSize,
                fontName: axisTitleFontName,
                bold: axisTitleBold,
                boldFontName: axisTitleBoldFontName
            ), minimumAxisTitleLane)
        }
        let tickLabelFootprint = PlotTextMeasurer.measuredCapHeight(
            fontSize: tickLabelFontSize,
            fontName: tickLabelFontName,
            bold: tickLabelBold,
            boldFontName: tickLabelBoldFontName
        )
        let desiredBottom = max(
            baseBottomPadding,
            axisTitleLaneHeight + titleToTickGap + tickLabelFootprint + tickToPlotGap
        )
        let upperBound = maxSideInset ?? .greatestFiniteMagnitude
        let requiredBottomPadding = min(max(desiredBottom, baseBottomPadding), upperBound)
        let tickLabelTopY = max(0, requiredBottomPadding - tickToPlotGap)
        let tickLabelCenterY = max(0, tickLabelTopY - tickLabelFootprint / 2)

        let titleCenterY: CGFloat
        if axisTitleLaneHeight > 0 {
            let bottomEdgeLimit = axisTitleLaneHeight / 2 + 4
            let topEdgeLimit = tickLabelCenterY - titleToTickGap - axisTitleLaneHeight / 2
            let biasLimit = max(baseBottomPadding * titleCenterBias, bottomEdgeLimit)
            titleCenterY = max(bottomEdgeLimit, min(topEdgeLimit, biasLimit))
        } else {
            titleCenterY = max(0, baseBottomPadding * titleCenterBias)
        }

        return PlotXAxisLaneLayout(
            maxTickLabelWidth: maxTickLabelWidth,
            axisTitleTextWidth: axisTitleTextWidth,
            axisTitleLaneHeight: axisTitleLaneHeight,
            requiredBottomPadding: requiredBottomPadding,
            titleCenterY: titleCenterY,
            tickLabelCenterY: tickLabelCenterY,
            tickLabelTopY: tickLabelTopY
        )
    }

    static func fixedTicks(min: Double, max: Double, step: Double) -> (ticks: [Double], step: Double) {
        guard max > min, step > 0 else { return ([min, max], max - min) }
        let firstTick = ceil(min / step) * step
        var ticks: [Double] = []
        var tick = firstTick
        let eps = step * 1e-9
        while tick <= max + eps {
            ticks.append(tick)
            tick += step
        }
        return (ticks, step)
    }

    /// Candidate step mantissas, ascending, tried against the rough step's order of
    /// magnitude. Includes intermediate values (2.5, 3, 6) alongside the classic
    /// 1/2/5/10 so ranges like 0–360 can land on a step of 6 × 10^n (e.g. 60).
    static let niceStepMantissas: [Double] = [1, 2, 2.5, 3, 5, 6, 10]

    private static func niceMantissa(for normalized: Double) -> Double {
        let mantissas = niceStepMantissas
        for i in 0..<(mantissas.count - 1) {
            let midpoint = (mantissas[i] + mantissas[i + 1]) / 2
            if normalized < midpoint { return mantissas[i] }
        }
        return mantissas[mantissas.count - 1]
    }

    static func niceTicks(min: Double, max: Double, targetCount: Int = 5) -> (ticks: [Double], step: Double) {
        guard max > min, targetCount > 0 else { return ([min, max], max - min) }
        let range = max - min
        let roughStep = range / Double(targetCount)
        let magnitude = pow(10.0, floor(log10(abs(roughStep))))
        let normalized = roughStep / magnitude
        let step = niceMantissa(for: normalized) * magnitude
        let firstTick = ceil(min / step) * step
        var ticks: [Double] = []
        var tick = firstTick
        let eps = step * 1e-9
        while tick <= max + eps {
            ticks.append(tick)
            tick += step
        }
        return (ticks, step)
    }

    static func resolvedXTicks(
        min: Double,
        max: Double,
        plotRect: CGRect,
        style: WorkbenchChartStyle = .init()
    ) -> (ticks: [Double], step: Double, targetCount: Int) {
        if let step = style.xTickStep {
            let fixed = fixedTicks(min: min, max: max, step: step)
            return (fixed.ticks, fixed.step, Swift.max(style.tickTargetX, 3))
        }

        let targetStart = Swift.max(style.tickTargetX, 3)
        guard max > min else { return ([min, max], max - min, targetStart) }

        for target in stride(from: targetStart, through: 3, by: -1) {
            let result = niceTicks(min: min, max: max, targetCount: target)
            if xTickLabelsFit(
                ticks: result.ticks,
                step: result.step,
                min: min,
                max: max,
                plotWidth: plotRect.width,
                fontSize: style.tickLabelFontSize,
                style: style
            ) || target == 3 {
                return (result.ticks, result.step, target)
            }
        }

        let fallback = niceTicks(min: min, max: max, targetCount: targetStart)
        return (fallback.ticks, fallback.step, targetStart)
    }

    static func formatTick(_ value: Double, step: Double) -> String {
        if abs(value) < step * 1e-9 { return "0" }
        if step >= 500 && abs(value.truncatingRemainder(dividingBy: 1000)) < 0.5 {
            let k = value / 1000
            return k == k.rounded(.toNearestOrEven)
                ? "\(Int(k.rounded()))k"
                : String(format: "%.1fk", k)
        }
        if step >= 100  { return String(format: "%.0f", value) }
        if step >= 10   { return String(format: "%.0f", value) }
        if step >= 1    { return String(format: "%.0f", value) }
        if step >= 0.1  { return String(format: "%.1f", value) }
        if step >= 0.01 { return String(format: "%.2f", value) }
        if step >= 0.001 { return String(format: "%.3f", value) }
        return compactScientificString(value)
    }

    static func xTickLabelsFit(
        ticks: [Double],
        step: Double,
        min: Double,
        max: Double,
        plotWidth: CGFloat,
        fontSize: CGFloat,
        style: WorkbenchChartStyle
    ) -> Bool {
        guard max > min, plotWidth > 0, ticks.count > 1 else { return true }
        let span = max - min
        var previousRightEdge: CGFloat?

        for tick in ticks {
            let label = formatTick(tick, step: step)
            let width = PlotTextMeasurer.measuredWidth(
                label,
                fontSize: fontSize,
                fontName: style.fontName,
                bold: false,
                boldFontName: style.boldFontName
            )
            let centerX = CGFloat((tick - min) / span) * plotWidth
            let leftEdge = centerX - width / 2
            if let previousRightEdge, previousRightEdge > leftEdge {
                return false
            }
            previousRightEdge = centerX + width / 2
        }
        return true
    }

    static func compactScientificString(_ value: Double) -> String {
        let raw = String(format: "%.2e", locale: Locale(identifier: "en_US_POSIX"), value)
        let normalized = raw.replacingOccurrences(of: "E", with: "e")
        guard let exponentIndex = normalized.firstIndex(of: "e") else { return normalized }

        var mantissa = String(normalized[..<exponentIndex])
        var exponent = String(normalized[normalized.index(after: exponentIndex)...])

        while mantissa.last == "0" {
            mantissa.removeLast()
        }
        if mantissa.last == "." {
            mantissa.removeLast()
        }

        if exponent.hasPrefix("+") {
            exponent.removeFirst()
        } else if exponent.hasPrefix("-") {
            let sign = exponent.removeFirst()
            while exponent.count > 1 && exponent.first == "0" {
                exponent.removeFirst()
            }
            exponent = String(sign) + exponent
            return mantissa + "e" + exponent
        }

        while exponent.count > 1 && exponent.first == "0" {
            exponent.removeFirst()
        }
        return mantissa + "e" + exponent
    }
}

/// Canonical resolved Cartesian axis bounds — the single source of truth for the
/// raw-range → fixed-override → ±5% padding computation.
///
/// `PlotAxisLayoutPlan` (tick pixel mapping), `WorkbenchChartRenderer` (data-point pixel
/// mapping), and `WorkbenchPlotLayout` (hit-testing) must all consume the same resolved
/// `PlotAxisBounds` instead of independently recomputing raw min/max, span, fixed
/// overrides, or padding. Tick *candidate value* selection (which round numbers become
/// tick marks) is a separate, narrower concern and intentionally still reads the raw
/// data/fixed extent directly in `PlotAxisLayoutPlan` — only the pixel-mapping denominator
/// (where 0% and 100% of the plot width/height land) is unified here.
struct PlotAxisBounds: Sendable {
    let xMin: Double
    let xMax: Double
    let yMin: Double
    let yMax: Double

    /// Resolves the canonical Cartesian bounds from series data and renderer fixed-bound
    /// options. Empty data falls back to a raw (0, 1) extent before padding. A degenerate
    /// raw span (single point or constant-valued series) falls back to a span of 1.0. A
    /// fixed bound on one side does not affect the padded automatic value on the other
    /// side — the padding is always derived from the pure raw data span.
    static func resolve(
        payload: WorkbenchPlotPayload,
        options: WorkbenchChartRenderer.Options
    ) -> PlotAxisBounds {
        let allX = payload.series.flatMap(\.x)
        let allY = payload.series.flatMap(\.y)

        let xRawMin = allX.min() ?? 0
        let xRawMax = allX.max() ?? 1
        let yRawMin = allY.min() ?? 0
        let yRawMax = allY.max() ?? 1

        let xRawSpan = xRawMax == xRawMin ? 1.0 : xRawMax - xRawMin
        let yRawSpan = yRawMax == yRawMin ? 1.0 : yRawMax - yRawMin

        let xMin = options.fixedXMin ?? (xRawMin - xRawSpan * 0.05)
        let xMax = options.fixedXMax ?? (xRawMax + xRawSpan * 0.05)
        let yMin = options.fixedYMin ?? (yRawMin - yRawSpan * 0.05)
        let yMax = options.fixedYMax ?? (yRawMax + yRawSpan * 0.05)

        return PlotAxisBounds(xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax)
    }
}

struct PlotAxisLayoutPlan: Sendable {
    let plotRect: CGRect
    let titleCenter: CGPoint
    let titleHitRect: CGRect
    let xLabelCenter: CGPoint
    let xLabelHitRect: CGRect
    let yLabelCenter: CGPoint
    let yLabelHitRect: CGRect
    let xTickHitRect: CGRect
    let yTickHitRect: CGRect
    let xTicks: [PlotAxisTick]
    let yTicks: [PlotAxisTick]
    let xAxisLane: PlotXAxisLaneLayout
    let yAxisLane: PlotYAxisLaneLayout

    /// Top margin reserved above the plot when the title is hidden — just breathing
    /// room, not a text lane. Mirrors how paddingRight has no adaptive lane logic.
    static let noTitleTopPadding: CGFloat = 24

    static func compute(
        options: WorkbenchChartRenderer.Options,
        payload: WorkbenchPlotPayload,
        style: WorkbenchChartStyle = .init(),
        showTitle: Bool = true
    ) -> PlotAxisLayoutPlan {
        let w = CGFloat(options.width)
        let h = CGFloat(options.height)
        let effectivePaddingTop = showTitle ? options.paddingTop : Self.noTitleTopPadding
        let allX = payload.series.flatMap(\.x)
        let allY = payload.series.flatMap(\.y)
        // Canonical resolved bounds — the single source of truth for raw range, fixed
        // overrides, and ±5% padding, shared with WorkbenchChartRenderer (data-point pixel
        // mapping) and WorkbenchPlotLayout (hit-testing). Tick *candidate value* selection
        // below intentionally still reads the raw/fixed extent directly (not `bounds`),
        // since which round numbers become ticks is a separate concern from where 0%/100%
        // of the plot area land in data space.
        let bounds = PlotAxisBounds.resolve(payload: payload, options: options)
        let (preYTicks, preYStep) = style.yTickStep.map { PlotAxisSpacingCalculator.fixedTicks(min: bounds.yMin, max: bounds.yMax, step: $0) }
            ?? PlotAxisSpacingCalculator.niceTicks(min: bounds.yMin, max: bounds.yMax, targetCount: style.tickTargetY)
        let yTickLabels = preYTicks.map { PlotAxisSpacingCalculator.formatTick($0, step: preYStep) }
        let yLane = PlotAxisSpacingCalculator.yAxisLane(
            axisTitleText: payload.axisMapping.yField,
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
            titleToTickGap: 16,
            tickToPlotGap: 5,
            baseLeftPadding: options.paddingLeft
        )

        let preliminaryPlotRect = CGRect(
            x: yLane.requiredLeftPadding,
            y: options.paddingBottom,
            width: max(0, w - yLane.requiredLeftPadding - options.paddingRight),
            height: max(0, h - effectivePaddingTop - options.paddingBottom)
        )

        let xTickResult = PlotAxisSpacingCalculator.resolvedXTicks(
            min: options.fixedXMin ?? (allX.min() ?? 0),
            max: options.fixedXMax ?? (allX.max() ?? 1),
            plotRect: preliminaryPlotRect,
            style: style
        )
        let xTickLabels = xTickResult.ticks.map { PlotAxisSpacingCalculator.formatTick($0, step: xTickResult.step) }
        let xLane = PlotAxisSpacingCalculator.xAxisLane(
            axisTitleText: payload.axisMapping.xField,
            tickLabels: xTickLabels,
            axisTitleFontSize: style.axisTitleFontSize,
            axisTitleFontName: style.fontName,
            axisTitleBold: false,
            axisTitleBoldFontName: style.boldFontName,
            tickLabelFontSize: style.tickLabelFontSize,
            tickLabelFontName: style.fontName,
            tickLabelBold: false,
            tickLabelBoldFontName: style.boldFontName,
            minimumAxisTitleLane: max(style.axisTitleFontSize * 1.25, 24),
            titleToTickGap: 16,
            tickToPlotGap: 5,
            baseBottomPadding: options.paddingBottom
        )

        let plotRect = CGRect(
            x: yLane.requiredLeftPadding,
            y: xLane.requiredBottomPadding,
            width: max(0, w - yLane.requiredLeftPadding - options.paddingRight),
            height: max(0, h - effectivePaddingTop - xLane.requiredBottomPadding)
        )

        let xMin = bounds.xMin
        let xMax = bounds.xMax
        let yMin = bounds.yMin
        let yMax = bounds.yMax
        let xSpan = xMax - xMin
        let ySpan = yMax - yMin

        let xTicks: [PlotAxisTick]
        if allX.isEmpty {
            xTicks = []
        } else {
            xTicks = zip(xTickResult.ticks, xTickLabels).map { tick, label in
                let cx = plotRect.minX + CGFloat((tick - xMin) / xSpan) * plotRect.width
                return PlotAxisTick(
                    value: tick,
                    label: label,
                    tickPoint: CGPoint(x: cx, y: plotRect.minY),
                    labelPoint: CGPoint(x: cx, y: xLane.tickLabelCenterY)
                )
            }
        }

        let yTicks: [PlotAxisTick]
        if allY.isEmpty {
            yTicks = []
        } else {
            let (ticks, step) = style.yTickStep.map { PlotAxisSpacingCalculator.fixedTicks(min: yMin, max: yMax, step: $0) }
                ?? PlotAxisSpacingCalculator.niceTicks(min: yMin, max: yMax, targetCount: style.tickTargetY)
            let labels = ticks.map { PlotAxisSpacingCalculator.formatTick($0, step: step) }
            yTicks = zip(ticks, labels).map { tick, label in
                let cy = plotRect.minY + CGFloat((tick - yMin) / ySpan) * plotRect.height
                return PlotAxisTick(
                    value: tick,
                    label: label,
                    tickPoint: CGPoint(x: plotRect.minX, y: cy),
                    labelPoint: CGPoint(x: yLane.tickLabelLaneTrailingX, y: cy)
                )
            }
        }

        let titleCenter = CGPoint(x: plotRect.midX, y: h - effectivePaddingTop * 0.45)
        let titleHitRect = showTitle
            ? CGRect(
                x: options.paddingLeft, y: h - effectivePaddingTop,
                width: plotRect.width,  height: effectivePaddingTop * 0.9
            )
            : .zero
        let xLabelCenter = CGPoint(x: plotRect.midX, y: xLane.titleCenterY)
        let xLabelHitRect = CGRect(
            x: options.paddingLeft,
            y: max(0, xLabelCenter.y - max(14, xLane.axisTitleLaneHeight / 2)),
            width: plotRect.width,
            height: max(28, xLane.axisTitleLaneHeight * 1.2)
        )
        let yLabelCenter = CGPoint(x: yLane.titleCenterX, y: plotRect.midY)
        let hitWidth: CGFloat = max(36, yLane.axisTitleLaneWidth + 10)
        let yLabelHitRect = CGRect(
            x: max(0, yLane.titleCenterX - hitWidth / 2),
            y: plotRect.minY,
            width: hitWidth,
            height: plotRect.height
        )
        let xTickHitRect = CGRect(
            x: plotRect.minX,
            y: xLabelCenter.y + max(14, xLane.axisTitleLaneHeight / 2),
            width: plotRect.width,
            height: max(0, plotRect.minY - (xLabelCenter.y + max(14, xLane.axisTitleLaneHeight / 2)))
        )
        let yTickHitRect = CGRect(
            x: yLane.titleCenterX + hitWidth / 2,
            y: plotRect.minY,
            width: max(0, plotRect.minX - (yLane.titleCenterX + hitWidth / 2)),
            height: plotRect.height
        )

        return PlotAxisLayoutPlan(
            plotRect: plotRect,
            titleCenter: titleCenter,
            titleHitRect: titleHitRect,
            xLabelCenter: xLabelCenter,
            xLabelHitRect: xLabelHitRect,
            yLabelCenter: yLabelCenter,
            yLabelHitRect: yLabelHitRect,
            xTickHitRect: xTickHitRect,
            yTickHitRect: yTickHitRect,
            xTicks: xTicks,
            yTicks: yTicks,
            xAxisLane: xLane,
            yAxisLane: yLane
        )
    }
}
