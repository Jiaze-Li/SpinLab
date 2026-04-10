import CoreGraphics
import CoreText

/// Single source of truth for chart text-element positions.
///
/// All geometry is in **CG renderer pixel space** (origin bottom-left, Y increases upward).
/// Both `WorkbenchChartRenderer` (drawing) and `WorkbenchPlotCanvas` (hit-testing) derive
/// their positions from `WorkbenchPlotLayout.compute(...)` — no duplicate constants.
///
/// Use `cgToScreen(_:fittedIn:rendererSize:)` to convert hit rects to SwiftUI screen coords.
struct WorkbenchPlotLayout: Sendable {

    // MARK: - Shared legend geometry constants

    static let legendLineLen:  CGFloat = 22
    static let legendRowH:     CGFloat = 26
    static let legendGap:      CGFloat = 6
    static let legendMargin:   CGFloat = 6
    /// Estimated label text width used for hit-rect sizing; visual label may be shorter.
    static let legendEstLabelW: CGFloat = 110

    // MARK: - LegendRow

    struct LegendRow {
        /// Zero-based series index — the stable key for `plotSeriesLabelOverrides`.
        let seriesIndex:   Int
        /// Original (pre-override) label, used for display in the edit panel.
        let originalLabel: String
        let cgRowY:        CGFloat   // CG y-center of this row
        let cgOriginX:     CGFloat   // X start of the color swatch line
        /// CoreText-measured label width in renderer coordinates (same font/size as drawLegend).
        let measuredLabelWidth: CGFloat

        // MARK: Renderer drawing helpers

        var lineStart: CGPoint {
            CGPoint(x: cgOriginX, y: cgRowY)
        }
        var lineEnd: CGPoint {
            CGPoint(x: cgOriginX + WorkbenchPlotLayout.legendLineLen, y: cgRowY)
        }
        /// Left edge of the label text — always to the right of the color line.
        var labelAnchor: CGPoint {
            CGPoint(x: cgOriginX + WorkbenchPlotLayout.legendLineLen
                                 + WorkbenchPlotLayout.legendGap,
                    y: cgRowY)
        }

        // MARK: Canvas hit-test helper

        var hitRect: CGRect {
            let w = WorkbenchPlotLayout.legendLineLen
                  + WorkbenchPlotLayout.legendGap
                  + measuredLabelWidth
            let h = WorkbenchPlotLayout.legendRowH
            // Block always extends rightward from cgOriginX ([line][gap][text]).
            return CGRect(x: cgOriginX, y: cgRowY - h / 2, width: w, height: h)
        }
    }

    // MARK: - Layout properties

    let titleCenter:    CGPoint
    let titleHitRect:   CGRect

    let xLabelCenter:   CGPoint
    let xLabelHitRect:  CGRect

    let yLabelCenter:   CGPoint
    let yLabelHitRect:  CGRect   // covers left-margin strip (rotated label visual footprint)

    let legendRows:     [LegendRow]

    /// The rendered chart title (after title override and workflow-name fallback).
    let chartTitle:  String
    /// The rendered X-axis label text (after display-label override).
    let xAxisLabel:  String
    /// The rendered Y-axis label text (after display-label override).
    let yAxisLabel:  String

    // MARK: - Factory

    static func compute(
        options: WorkbenchChartRenderer.Options,
        payload: WorkbenchPlotPayload,
        legendPoint: CGPoint?
    ) -> WorkbenchPlotLayout {
        let w = CGFloat(options.width)
        let h = CGFloat(options.height)
        let plotRect = CGRect(
            x: options.paddingLeft,
            y: options.paddingBottom,
            width:  w - options.paddingLeft - options.paddingRight,
            height: h - options.paddingTop  - options.paddingBottom
        )

        // Title — centered on plot area (not whole image)
        let titleCenter  = CGPoint(x: plotRect.midX, y: h - options.paddingTop * 0.45)
        let titleHitRect = CGRect(
            x: options.paddingLeft, y: h - options.paddingTop,
            width: plotRect.width,  height: options.paddingTop * 0.9
        )

        // X axis label — centered in bottom-padding band
        let xLabelCenter  = CGPoint(x: w / 2, y: options.paddingBottom * 0.58)
        let xLabelHitRect = CGRect(
            x: options.paddingLeft, y: xLabelCenter.y - 14,
            width: plotRect.width,  height: 28
        )

        // Y axis label (rotated 90°) — collision-based placement
        // Place title to the left of tick labels, not proportional to paddingLeft.
        let titleThickness: CGFloat = 24   // rotated font lineHeight for size 20
        let labelGap: CGFloat = 5          // gap between tick labels and axis
        let titleTickGap: CGFloat = 4      // gap between title and tick labels
        let tickLeft = options.paddingLeft - labelGap - options.maxYTickLabelWidth
        let yTitleX = max(titleThickness / 2 + 4,                           // clamp: at least 16pt from left edge
                          min(tickLeft - titleTickGap - titleThickness / 2,  // collision boundary
                              options.paddingLeft * 0.38))                   // never worse than old proportional
        let yLabelCenter  = CGPoint(x: yTitleX, y: h / 2)
        let hitWidth: CGFloat = 36  // fixed band around title center
        let yLabelHitRect = CGRect(
            x: max(0, yTitleX - hitWidth / 2), y: plotRect.minY,
            width:  hitWidth,
            height: plotRect.height
        )

        // Legend rows
        let legendRows = computeLegendRows(
            series:      payload.series,
            plotRect:    plotRect,
            legendPoint: legendPoint,
            styleParams: payload.styleParams
        )

        let chartTitle = payload.title.isEmpty ? payload.workflowDisplayName : payload.title
        let xAxisLabel = payload.axisMapping.xField
        let yAxisLabel = payload.axisMapping.yField

        return WorkbenchPlotLayout(
            titleCenter:   titleCenter,
            titleHitRect:  titleHitRect,
            xLabelCenter:  xLabelCenter,
            xLabelHitRect: xLabelHitRect,
            yLabelCenter:  yLabelCenter,
            yLabelHitRect: yLabelHitRect,
            legendRows:    legendRows,
            chartTitle:    chartTitle,
            xAxisLabel:    xAxisLabel,
            yAxisLabel:    yAxisLabel
        )
    }

    private static func computeLegendRows(
        series:      [WorkbenchPlotSeries],
        plotRect:    CGRect,
        legendPoint: CGPoint?,
        styleParams: [String: String]
    ) -> [LegendRow] {
        series.enumerated().map { i, s in
            let cgRowY:      CGFloat
            let cgOriginX:   CGFloat
            let isLeftAligned: Bool
            let measuredW = measureLabelWidth(s.label)

            if let np = legendPoint {
                // Free-position mode — mirrors drawLegend free-position math exactly
                let cx = min(max(np.x, 0), 1)
                let cy = min(max(np.y, 0), 1)
                cgOriginX    = plotRect.minX + cx * plotRect.width
                let originY  = plotRect.minY + cy * plotRect.height
                cgRowY       = originY - CGFloat(i) * legendRowH - legendRowH * 0.4
                isLeftAligned = true
            } else {
                // Anchor mode — mirrors drawLegend anchor math exactly
                let anchor    = styleParams["legendAnchor"] ?? "top-right"
                isLeftAligned = anchor == "top-left"  || anchor == "bottom-left"
                let isBottom  = anchor == "bottom-right" || anchor == "bottom-left"
                let rowIndex  = CGFloat(i + 1)
                cgRowY = isBottom
                    ? plotRect.minY + rowIndex * legendRowH - legendRowH * 0.6
                    : plotRect.maxY - rowIndex * legendRowH + legendRowH * 0.4
                // For all anchors, text appears to the RIGHT of the color line.
                // Right-anchor entries are shifted left so [line][gap][text] fits within the plot.
                let blockW = legendLineLen + legendGap + legendEstLabelW
                cgOriginX = isLeftAligned
                    ? plotRect.minX + legendMargin
                    : plotRect.maxX - legendMargin - blockW
            }

            return LegendRow(
                seriesIndex:        i,
                originalLabel:      s.label,
                cgRowY:             cgRowY,
                cgOriginX:          cgOriginX,
                measuredLabelWidth: measuredW
            )
        }
    }

    /// Measures label text width in renderer coordinates using the same font as drawLegend.
    private static func measureLabelWidth(_ text: String) -> CGFloat {
        let font = CTFontCreateWithName("ArialMT" as CFString, 18, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font]
        let attrStr = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrStr)
        let w = CTLineGetBoundsWithOptions(line, []).width
        return w > 0 ? w : legendEstLabelW
    }

    // MARK: - Coordinate conversion

    /// Converts a CG-space rect to SwiftUI screen coordinates inside the fitted image area.
    /// CG origin is bottom-left; PNG/screen origin is top-left — Y is flipped.
    static func cgToScreen(
        _ cgRect: CGRect,
        fittedIn fitted: CGRect,
        rendererWidth:  CGFloat,
        rendererHeight: CGFloat
    ) -> CGRect {
        let scaleX = fitted.width  / rendererWidth
        let scaleY = fitted.height / rendererHeight
        let pngMinY = rendererHeight - cgRect.maxY   // flip Y
        return CGRect(
            x:      fitted.minX + cgRect.minX * scaleX,
            y:      fitted.minY + pngMinY     * scaleY,
            width:  cgRect.width  * scaleX,
            height: cgRect.height * scaleY
        )
    }
}
