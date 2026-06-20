import CoreGraphics
import CoreText

/// Single source of truth for chart text-element positions.
///
/// All geometry is in **CG renderer pixel space** (origin bottom-left, Y increases upward).
/// Both `WorkbenchChartRenderer` (drawing) and `WorkbenchPlotCanvas` (hit-testing) derive
/// their positions from `WorkbenchPlotLayout.compute(...)` — no duplicate constants.
///
/// Use `CoordinateContext` to convert hit rects to SwiftUI screen coords.
struct WorkbenchPlotLayout: Sendable {

    // MARK: - Legend style

    /// Explicit legend geometry and font metrics used for both layout and rendering.
    struct LegendStyle: Sendable {
        struct FontMetrics: Sendable {
            let ascent: CGFloat
            let descent: CGFloat
            let leading: CGFloat

            var lineHeight: CGFloat {
                ascent + descent + leading
            }
        }

        /// Padding inside the legend box around the rows.
        let boxPadding: CGFloat
        /// Inset from the plot boundary when anchoring the legend box.
        let edgeInset: CGFloat
        /// Vertical padding inside each row around the font line height.
        let rowVerticalPadding: CGFloat
        /// Width of the color swatch line.
        let symbolWidth: CGFloat
        /// Gap between swatch line and label text.
        let symbolLabelGap: CGFloat
        /// Font size used to measure and draw legend labels.
        let fontSize: CGFloat
        /// CoreText font metrics for the legend label font.
        let fontMetrics: FontMetrics
        /// Estimated label width used when a measured width is unavailable.
        let estimatedLabelWidth: CGFloat
        /// Font name used to measure and draw legend labels.
        let fontName: String

        var rowHeight: CGFloat {
            fontMetrics.lineHeight + rowVerticalPadding * 2
        }

        static func `default`(fontSize: CGFloat, fontName: String) -> LegendStyle {
            let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
            let metrics = FontMetrics(
                ascent: CTFontGetAscent(font),
                descent: CTFontGetDescent(font),
                leading: CTFontGetLeading(font)
            )
            let targetRowHeight: CGFloat = 26
            let rowVerticalPadding = max(0, (targetRowHeight - metrics.lineHeight) / 2)
            return LegendStyle(
                boxPadding: 6,
                edgeInset: 6,
                rowVerticalPadding: rowVerticalPadding,
                symbolWidth: 22,
                symbolLabelGap: 6,
                fontSize: fontSize,
                fontMetrics: metrics,
                estimatedLabelWidth: 110,
                fontName: fontName
            )
        }

        func boxRect(for rows: [LegendRow]) -> CGRect? {
            guard !rows.isEmpty else { return nil }
            let minX = rows.map(\.cgOriginX).min()! - boxPadding
            let maxX = rows.map { $0.labelAnchor.x + $0.measuredLabelWidth }.max()! + boxPadding
            let minY = rows.map(\.cgRowY).min()! - rowHeight * 0.5 - boxPadding
            let maxY = rows.map(\.cgRowY).max()! + rowHeight * 0.5 + boxPadding
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    // MARK: - LegendRow

    struct LegendRow {
        /// Zero-based series index — the stable key for `plotSeriesLabelOverrides`.
        let seriesIndex:   Int
        /// Original (pre-override) label, used for display in the edit panel.
        let originalLabel: String
        /// Legend style used to derive the row geometry.
        let style:         LegendStyle
        let cgRowY:        CGFloat   // CG y-center of this row
        let cgOriginX:     CGFloat   // X start of the color swatch line
        /// CoreText-measured label width in renderer coordinates (same font/size as drawLegend).
        let measuredLabelWidth: CGFloat

        // MARK: Renderer drawing helpers

        var lineStart: CGPoint {
            CGPoint(x: cgOriginX, y: cgRowY)
        }
        var lineEnd: CGPoint {
            CGPoint(x: cgOriginX + style.symbolWidth, y: cgRowY)
        }
        /// Left edge of the label text — always to the right of the color line.
        var labelAnchor: CGPoint {
            CGPoint(x: cgOriginX + style.symbolWidth
                                 + style.symbolLabelGap,
                    y: cgRowY)
        }

        // MARK: Canvas hit-test helper

        var hitRect: CGRect {
            let w = style.symbolWidth
                  + style.symbolLabelGap
                  + measuredLabelWidth
            let h = style.rowHeight
            // Block always extends rightward from cgOriginX ([line][gap][text]).
            return CGRect(x: cgOriginX, y: cgRowY - h / 2, width: w, height: h)
        }
    }

    struct PointHitTarget: Sendable {
        let seriesIndex: Int
        let pointIndex:  Int
        let hitRect:     CGRect
    }

    struct PointLabelGeometry: Sendable {
        enum Placement: Sendable {
            case right
            case left
            case below
        }

        let placement: Placement
        let pointDotHitRect: CGRect
        let pointLabelHitRect: CGRect
        let drawAnchor: CGPoint
    }

    // MARK: - Layout properties

    /// The plot drawing area in renderer pixel space (CG origin bottom-left).
    /// Canvas uses this instead of recomputing from default Options.
    let plotRect:       CGRect
    /// The renderer image size in pixels.
    let rendererSize:   CGSize

    let titleCenter:    CGPoint
    let titleHitRect:   CGRect

    let xLabelCenter:   CGPoint
    let xLabelHitRect:  CGRect

    let yLabelCenter:   CGPoint
    let yLabelHitRect:  CGRect   // covers left-margin strip (rotated label visual footprint)

    /// Hit rect for x-axis tick label area (bottom padding, between plot and x-axis title).
    let xTickHitRect:   CGRect
    /// Hit rect for y-axis tick label area (left padding, between y-axis title and plot).
    let yTickHitRect:   CGRect

    /// Explicit legend sizing and font metrics.
    let legendStyle:    LegendStyle
    let legendRows:     [LegendRow]

    /// Bounding box of the rendered legend in CG renderer pixel space (origin bottom-left).
    /// Single source of truth for both the renderer box and canvas drag preview geometry.
    /// `nil` when there are no legend rows.
    var legendBoxRect: CGRect? {
        legendStyle.boxRect(for: legendRows)
    }

    let pointDotHitTargets:   [PointHitTarget]
    let pointLabelHitTargets: [PointHitTarget]

    /// The rendered chart title (after title override and workflow-name fallback).
    let chartTitle:  String
    /// The rendered X-axis label text (after display-label override).
    let xAxisLabel:  String
    /// The rendered Y-axis label text (after display-label override).
    let yAxisLabel:  String

    /// Actual axis range used by the renderer (mirrors WorkbenchChartRenderer logic).
    /// Hit-test coordinate math must use these values, not re-derive from raw data.
    let axisXMin: Double
    let axisXMax: Double
    let axisYMin: Double
    let axisYMax: Double

    // MARK: - Factory

    static func compute(
        options: WorkbenchChartRenderer.Options,
        payload: WorkbenchPlotPayload,
        legendPoint: CGPoint?,
        style: WorkbenchChartStyle = .init(),
        seriesLabelOverrides: [Int: String] = [:]
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

        // X axis label — centered on plot area (not whole image)
        let xLabelCenter  = CGPoint(x: plotRect.midX, y: options.paddingBottom * 0.58)
        let xLabelHitRect = CGRect(
            x: options.paddingLeft, y: xLabelCenter.y - 14,
            width: plotRect.width,  height: 28
        )

        // Y axis label (rotated 90°) — collision-based placement
        // Place title to the left of tick labels, not proportional to paddingLeft.
        let titleThickness: CGFloat = style.axisTitleFontSize * 1.2   // rotated font lineHeight
        let labelGap: CGFloat = 5          // gap between tick labels and axis
        let titleTickGap: CGFloat = 4      // gap between title and tick labels
        let tickLeft = options.paddingLeft - labelGap - options.maxYTickLabelWidth
        let yTitleX = max(titleThickness / 2 + 4,                           // clamp: at least half-title from left edge
                          min(tickLeft - titleTickGap - titleThickness / 2,  // collision boundary
                              options.paddingLeft * 0.38))                   // never worse than old proportional
        let yLabelCenter  = CGPoint(x: yTitleX, y: plotRect.midY)
        let hitWidth: CGFloat = 36  // fixed band around title center
        let yLabelHitRect = CGRect(
            x: max(0, yTitleX - hitWidth / 2), y: plotRect.minY,
            width:  hitWidth,
            height: plotRect.height
        )

        // Tick label hit rects — strip between axis edge and axis title
        let xTickHitRect = CGRect(
            x: plotRect.minX,
            y: xLabelCenter.y + 14,    // above x-axis title
            width: plotRect.width,
            height: plotRect.minY - (xLabelCenter.y + 14)
        )
        let yTickHitRect = CGRect(
            x: yTitleX + hitWidth / 2,  // right of y-axis title
            y: plotRect.minY,
            width: plotRect.minX - (yTitleX + hitWidth / 2),
            height: plotRect.height
        )

        // Legend rows
        let legendStyle = LegendStyle.default(fontSize: style.legendFontSize, fontName: style.fontName)
        let legendRows = computeLegendRows(
            series:             payload.series,
            plotRect:           plotRect,
            legendPoint:        legendPoint,
            styleParams:        payload.styleParams,
            legendStyle:        legendStyle,
            labelOverrides:     seriesLabelOverrides
        )

        // Axis range — mirrors WorkbenchChartRenderer axis computation exactly.
        // Computed unconditionally so hitTestSeries can use it.
        let allXForHit = payload.series.flatMap(\.x)
        let allYForHit = payload.series.flatMap(\.y)
        let axisXMin: Double
        let axisXMax: Double
        let axisYMin: Double
        let axisYMax: Double
        if allXForHit.isEmpty {
            axisXMin = 0; axisXMax = 1; axisYMin = 0; axisYMax = 1
        } else {
            let xRawH = options.fixedXMin ?? allXForHit.min()!
            let xRawMaxH = options.fixedXMax ?? allXForHit.max()!
            let yRawH = allYForHit.min()!, yRawMaxH = allYForHit.max()!
            let xRawSpanH = xRawMaxH == xRawH ? 1.0 : xRawMaxH - xRawH
            let yRawSpanH = yRawMaxH == yRawH ? 1.0 : yRawMaxH - yRawH
            axisXMin = options.fixedXMin != nil ? xRawH    : xRawH    - xRawSpanH * 0.05
            axisXMax = options.fixedXMax != nil ? xRawMaxH : xRawMaxH + xRawSpanH * 0.05
            axisYMin = yRawH    - yRawSpanH * 0.05
            axisYMax = yRawMaxH + yRawSpanH * 0.05
        }
        let axisXSpan = axisXMax - axisXMin
        let axisYSpan = axisYMax - axisYMin

        // Point dot + label hit targets (for series that carry point labels)
        var pointDotHitTargets:   [WorkbenchPlotLayout.PointHitTarget] = []
        var pointLabelHitTargets: [WorkbenchPlotLayout.PointHitTarget] = []
        if !allXForHit.isEmpty, payload.series.contains(where: { !$0.pointLabels.isEmpty }) {
            let xSpanH = axisXSpan, ySpanH = axisYSpan
            let xMinH = axisXMin,   yMinH = axisYMin
            for (si, series) in payload.series.enumerated() {
                guard !series.pointLabels.isEmpty,
                      series.x.count == series.y.count else { continue }
                for k in 0..<series.x.count {
                    let cx = plotRect.minX + CGFloat((series.x[k] - xMinH) / xSpanH) * plotRect.width
                    let cy = plotRect.minY + CGFloat((series.y[k] - yMinH) / ySpanH) * plotRect.height
                    let geometry = pointLabelGeometry(center: CGPoint(x: cx, y: cy), plotRect: plotRect)
                    pointDotHitTargets.append(PointHitTarget(
                        seriesIndex: si,
                        pointIndex: k,
                        hitRect: geometry.pointDotHitRect
                    ))
                    pointLabelHitTargets.append(PointHitTarget(
                        seriesIndex: si,
                        pointIndex: k,
                        hitRect: geometry.pointLabelHitRect
                    ))
                }
            }
        }

        let chartTitle = payload.title.isEmpty ? payload.workflowDisplayName : payload.title
        let xAxisLabel = payload.axisMapping.xField
        let yAxisLabel = payload.axisMapping.yField

        return WorkbenchPlotLayout(
            plotRect:      plotRect,
            rendererSize:  CGSize(width: w, height: h),
            titleCenter:   titleCenter,
            titleHitRect:  titleHitRect,
            xLabelCenter:  xLabelCenter,
            xLabelHitRect: xLabelHitRect,
            yLabelCenter:  yLabelCenter,
            yLabelHitRect: yLabelHitRect,
            xTickHitRect:  xTickHitRect,
            yTickHitRect:  yTickHitRect,
            legendStyle:   legendStyle,
            legendRows:    legendRows,
            pointDotHitTargets: pointDotHitTargets,
            pointLabelHitTargets: pointLabelHitTargets,
            chartTitle:    chartTitle,
            xAxisLabel:    xAxisLabel,
            yAxisLabel:    yAxisLabel,
            axisXMin:      axisXMin,
            axisXMax:      axisXMax,
            axisYMin:      axisYMin,
            axisYMax:      axisYMax
        )
    }

    private static func computeLegendRows(
        series:         [WorkbenchPlotSeries],
        plotRect:       CGRect,
        legendPoint:    CGPoint?,
        styleParams:    [String: String],
        legendStyle:    LegendStyle,
        labelOverrides: [Int: String] = [:]
    ) -> [LegendRow] {
        guard !series.isEmpty else { return [] }

        // Pre-measure all display labels so right-anchor uses actual max width, not the estimate.
        let measuredWidths: [CGFloat] = series.enumerated().map { i, s in
            measureLabelWidth(labelOverrides[i] ?? s.label, fontSize: legendStyle.fontSize, fontName: legendStyle.fontName)
        }
        let maxMeasuredW = measuredWidths.max() ?? legendStyle.estimatedLabelWidth

        let rawRows: [LegendRow] = series.enumerated().map { i, s in
            let cgRowY:    CGFloat
            let cgOriginX: CGFloat
            let measuredW = measuredWidths[i]

            if let np = legendPoint {
                // Free-position mode — mirrors drawLegend free-position math exactly
                let cx = min(max(np.x, 0), 1)
                let cy = min(max(np.y, 0), 1)
                cgOriginX = plotRect.minX + cx * plotRect.width
                let originY = plotRect.minY + cy * plotRect.height
                cgRowY = originY - CGFloat(i) * legendStyle.rowHeight - legendStyle.rowHeight * 0.4
            } else {
                // Anchor mode — row0 is placed so legendBoxRect stays inside plotRect.
                // boxPad must match the constant in legendBoxRect.
                let anchor   = styleParams["legendAnchor"] ?? "top-right"
                let isLeft   = anchor == "top-left" || anchor == "bottom-left"
                let isBottom = anchor == "bottom-right" || anchor == "bottom-left"
                let boxPad = legendStyle.boxPadding
                if isBottom {
                    // row0 at bottom: legendBoxRect.minY = row0Y - rowH*0.5 - boxPad = plotRect.minY + edgeInset
                    let row0Y = plotRect.minY + legendStyle.edgeInset + boxPad + legendStyle.rowHeight * 0.5
                    cgRowY = row0Y + CGFloat(i) * legendStyle.rowHeight
                } else {
                    // row0 at top: legendBoxRect.maxY = row0Y + rowH*0.5 + boxPad = plotRect.maxY - edgeInset
                    let row0Y = plotRect.maxY - legendStyle.edgeInset - boxPad - legendStyle.rowHeight * 0.5
                    cgRowY = row0Y - CGFloat(i) * legendStyle.rowHeight
                }
                // Right-anchor: shift block left by actual max label width so text stays inside plot.
                let blockW = legendStyle.symbolWidth + legendStyle.symbolLabelGap + maxMeasuredW
                cgOriginX = isLeft
                    ? plotRect.minX + legendStyle.edgeInset
                    : plotRect.maxX - legendStyle.edgeInset - blockW
            }

            return LegendRow(
                seriesIndex:        i,
                originalLabel:      s.label,
                style:              legendStyle,
                cgRowY:             cgRowY,
                cgOriginX:          cgOriginX,
                measuredLabelWidth: measuredW
            )
        }

        // Final box clamp: shift all rows uniformly so the full legendBoxRect stays inside plotRect.
        // This corrects free-position origins near edges (where the box extends beyond the boundary)
        // and acts as a safety net for anchor mode. Applied after all per-row positions are set.
        return clampRowsToPlotRect(rawRows, plotRect: plotRect)
    }

    /// Computes dx/dy needed to keep the bounding box of `rows` inside `plotRect`, then offsets
    /// every row by that amount. Uses the same box formula as `legendBoxRect`.
    private static func clampRowsToPlotRect(_ rows: [LegendRow], plotRect: CGRect) -> [LegendRow] {
        guard !rows.isEmpty else { return rows }
        let style = rows[0].style
        // `rows` is non-empty, so the legend box geometry must be computable here.
        let rawBox = style.boxRect(for: rows)!

        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if rawBox.maxX > plotRect.maxX { dx = plotRect.maxX - rawBox.maxX }
        if rawBox.minX + dx < plotRect.minX { dx = plotRect.minX - rawBox.minX }
        if rawBox.maxY > plotRect.maxY { dy = plotRect.maxY - rawBox.maxY }
        if rawBox.minY + dy < plotRect.minY { dy = plotRect.minY - rawBox.minY }

        guard dx != 0 || dy != 0 else { return rows }
        return rows.map {
            LegendRow(
                seriesIndex:        $0.seriesIndex,
                originalLabel:      $0.originalLabel,
                style:              $0.style,
                cgRowY:             $0.cgRowY + dy,
                cgOriginX:          $0.cgOriginX + dx,
                measuredLabelWidth: $0.measuredLabelWidth
            )
        }
    }

    /// Measures label text width in renderer coordinates using the same font as drawLegend.
    private static func measureLabelWidth(_ text: String, fontSize: CGFloat = 18, fontName: String = "TimesNewRomanPSMT") -> CGFloat {
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font]
        let attrStr = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrStr)
        let w = CTLineGetBoundsWithOptions(line, []).width
        return w > 0 ? w : LegendStyle.default(fontSize: fontSize, fontName: fontName).estimatedLabelWidth
    }

    static func pointLabelGeometry(
        center: CGPoint,
        plotRect: CGRect,
        dotHitRadius: CGFloat = 7.0,
        dotDrawRadius: CGFloat = 3.5,
        labelWidth: CGFloat = 50,
        labelHeight: CGFloat = 20,
        gap: CGFloat = 4
    ) -> PointLabelGeometry {
        let pointDotHitRect = CGRect(
            x: center.x - dotHitRadius,
            y: center.y - dotHitRadius,
            width: dotHitRadius * 2,
            height: dotHitRadius * 2
        )
        let nearRight = center.x + dotDrawRadius + gap + labelWidth > plotRect.maxX
        let nearTop = center.y + labelHeight * 0.5 > plotRect.maxY

        if nearRight {
            return PointLabelGeometry(
                placement: .left,
                pointDotHitRect: pointDotHitRect,
                pointLabelHitRect: CGRect(
                    x: center.x - dotDrawRadius - gap - labelWidth,
                    y: center.y - labelHeight / 2,
                    width: labelWidth,
                    height: labelHeight
                ),
                drawAnchor: CGPoint(x: center.x - dotDrawRadius - gap, y: center.y)
            )
        }

        if nearTop {
            return PointLabelGeometry(
                placement: .below,
                pointDotHitRect: pointDotHitRect,
                pointLabelHitRect: CGRect(
                    x: center.x - labelWidth / 2,
                    y: center.y - dotDrawRadius - gap - labelHeight,
                    width: labelWidth,
                    height: labelHeight
                ),
                drawAnchor: CGPoint(x: center.x, y: center.y - dotDrawRadius - gap - labelHeight)
            )
        }

        return PointLabelGeometry(
            placement: .right,
            pointDotHitRect: pointDotHitRect,
            pointLabelHitRect: CGRect(
                x: center.x + dotDrawRadius + gap,
                y: center.y - labelHeight / 2,
                width: labelWidth,
                height: labelHeight
            ),
            drawAnchor: CGPoint(x: center.x + dotDrawRadius + gap, y: center.y)
        )
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
        let context = CoordinateContext(
            rendererSize: CGSize(width: rendererWidth, height: rendererHeight),
            displayRect: fitted
        )
        return context.rendererToScreen(cgRect)
    }
}

// MARK: - Series hit-test

extension WorkbenchPlotLayout {

    /// Finds the series closest to `location` within `radius` screen points.
    /// Uses axis extents derived from the payload data (matches renderer behavior for charts
    /// without fixedXMin/fixedXMax, i.e. all 3ω stacked charts).
    /// Returns the sampleID of the nearest hit series and its mid-polyline screen y.
    /// radius: nil = always return nearest series in the plot area (no distance limit).
    func hitTestSeries(
        location: CGPoint,
        fittedRect: CGRect,
        payload: WorkbenchPlotPayload,
        radius: CGFloat? = nil
    ) -> (sampleID: String, screenY: CGFloat)? {
        let series = payload.series
        guard !series.isEmpty else { return nil }
        guard !series.flatMap(\.x).isEmpty else { return nil }
        let context = CoordinateContext(rendererSize: rendererSize, displayRect: fittedRect)

        let xMin = axisXMin, xMax = axisXMax
        let yMin = axisYMin, yMax = axisYMax
        let xSpan = xMax - xMin
        let ySpan = yMax - yMin
        guard xSpan > 0, ySpan > 0 else { return nil }

        func dataToScreen(_ x: Double, _ y: Double) -> CGPoint {
            let cgX = plotRect.minX + CGFloat((x - xMin) / xSpan) * plotRect.width
            let cgY = plotRect.minY + CGFloat((y - yMin) / ySpan) * plotRect.height
            return context.rendererToScreen(CGPoint(x: cgX, y: cgY))
        }

        func screenDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            hypot(a.x - b.x, a.y - b.y)
        }

        func screenDistanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lenSq = dx * dx + dy * dy
            if lenSq == 0 { return screenDistance(p, a) }
            let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
            return screenDistance(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
        }

        var best: (sampleID: String, screenY: CGFloat, dist: CGFloat)?
        for s in series {
            guard let sid = s.sampleID else { continue }
            guard s.x.count == s.y.count, !s.x.isEmpty else { continue }
            guard s.x.allSatisfy(\.isFinite), s.y.allSatisfy(\.isFinite) else {
                continue
            }

            let pts = zip(s.x, s.y).map { dataToScreen($0, $1) }

            var minDist: CGFloat = .infinity
            if pts.count == 1 {
                minDist = screenDistance(location, pts[0])
            } else {
                for i in 0..<pts.count - 1 {
                    let d = screenDistanceToSegment(location, pts[i], pts[i + 1])
                    if d < minDist { minDist = d }
                }
            }

            if let r = radius, minDist > r { continue }

            let midScreenY = pts[pts.count / 2].y
            if best == nil || minDist < best!.dist ||
               (abs(minDist - best!.dist) < 0.5 && abs(location.y - midScreenY) < abs(location.y - best!.screenY)) {
                best = (sid, midScreenY, minDist)
            }
        }

        let result = best.map { ($0.sampleID, $0.screenY) }
        return result
    }

    private static func _dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func _distToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 { return _dist(p, a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        return _dist(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }
}
