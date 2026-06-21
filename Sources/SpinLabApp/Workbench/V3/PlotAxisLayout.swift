import CoreGraphics
import CoreText

/// Shared CoreText text measurement and Y-axis lane spacing for plot layouts.
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
        titleCenterBias: CGFloat = 0.38
    ) -> PlotYAxisLaneLayout {
        let axisTitleTextWidth = PlotTextMeasurer.measuredWidth(
            axisTitleText,
            fontSize: axisTitleFontSize,
            fontName: axisTitleFontName,
            bold: axisTitleBold,
            boldFontName: axisTitleBoldFontName
        )
        let axisTitleLaneWidth = axisTitleTextWidth > 0
            ? max(axisTitleTextWidth, minimumAxisTitleLane)
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
}
