import Foundation
import CoreGraphics
import CoreText
import ImageIO

/// Pure CoreGraphics PNG renderer for WorkbenchPlotPayload.
/// No SwiftUI or AppKit view layer involved.
struct WorkbenchChartRenderer {

    struct Options: Sendable {
        var width: Int = 800
        var height: Int = 600
        var paddingTop: CGFloat = 64
        var paddingBottom: CGFloat = 88   // space for x tick labels + field label
        var paddingLeft: CGFloat = 96     // space for y tick labels + field label
        var paddingRight: CGFloat = 30
        /// When set, locks the x-axis range instead of auto-fitting to data extents.
        var fixedXMin: Double? = nil
        var fixedXMax: Double? = nil
        /// When set, locks the y-axis range instead of auto-fitting to data extents.
        var fixedYMin: Double? = nil
        var fixedYMax: Double? = nil
        /// Per-series hidden point-label indices, used when collecting pending labels.
        var hiddenPointLabelsBySeries: [Int: Set<Int>] = [:]
        /// Pixel-density multiplier. Logical drawing stays in width×height; output PNG is width·scale × height·scale.
        var pixelScale: CGFloat = 2.0
    }

    enum RendererError: Error, LocalizedError {
        case contextCreationFailed
        case imageCreationFailed
        case destinationCreationFailed
        case finalizeFailed

        var errorDescription: String? {
            switch self {
            case .contextCreationFailed:    return "Failed to create CGContext."
            case .imageCreationFailed:      return "Failed to create CGImage."
            case .destinationCreationFailed: return "Failed to create image destination."
            case .finalizeFailed:           return "Failed to finalize PNG."
            }
        }
    }

    // matplotlib-style default series colors (10 entries, wraps)
    private static let seriesColors: [CGColor] = [
        CGColor(red: 0.122, green: 0.467, blue: 0.706, alpha: 1), // C0 blue
        CGColor(red: 1.000, green: 0.498, blue: 0.055, alpha: 1), // C1 orange
        CGColor(red: 0.173, green: 0.627, blue: 0.173, alpha: 1), // C2 green
        CGColor(red: 0.839, green: 0.153, blue: 0.157, alpha: 1), // C3 red
        CGColor(red: 0.580, green: 0.404, blue: 0.741, alpha: 1), // C4 purple
        CGColor(red: 0.549, green: 0.337, blue: 0.294, alpha: 1), // C5 brown
        CGColor(red: 0.890, green: 0.467, blue: 0.761, alpha: 1), // C6 pink
        CGColor(red: 0.498, green: 0.498, blue: 0.498, alpha: 1), // C7 gray
        CGColor(red: 0.737, green: 0.741, blue: 0.133, alpha: 1), // C8 olive
        CGColor(red: 0.090, green: 0.745, blue: 0.812, alpha: 1), // C9 cyan
    ]

    // MARK: - Public

    func renderPNG(payload: WorkbenchPlotPayload, options: Options = .init(), style: WorkbenchChartStyle = .init(), layout: WorkbenchPlotLayout? = nil) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let scale = max(options.pixelScale, 1)
        let pixelW = Int((CGFloat(options.width) * scale).rounded())
        let pixelH = Int((CGFloat(options.height) * scale).rounded())
        guard let ctx = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { throw RendererError.contextCreationFailed }

        ctx.scaleBy(x: scale, y: scale)
        drawCanvas(in: ctx, payload: payload, options: options, style: style, externalLayout: layout)

        guard let cgImage = ctx.makeImage() else { throw RendererError.imageCreationFailed }

        let buffer = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            buffer as CFMutableData, "public.png" as CFString, 1, nil
        ) else { throw RendererError.destinationCreationFailed }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { throw RendererError.finalizeFailed }
        return buffer as Data
    }

    /// Renders the same `drawCanvas(...)` path as `renderPNG` into a vector PDF context.
    /// Logical drawing stays in width×height points — PDF is resolution-independent,
    /// so `options.pixelScale` does not apply here.
    func renderPDF(payload: WorkbenchPlotPayload, options: Options = .init(), style: WorkbenchChartStyle = .init(), layout: WorkbenchPlotLayout? = nil) throws -> Data {
        let w = CGFloat(options.width)
        let h = CGFloat(options.height)
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            throw RendererError.destinationCreationFailed
        }
        var mediaBox = CGRect(x: 0, y: 0, width: w, height: h)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw RendererError.contextCreationFailed
        }
        ctx.beginPDFPage(nil)
        drawCanvas(in: ctx, payload: payload, options: options, style: style, externalLayout: layout)
        ctx.endPDFPage()
        ctx.closePDF()
        return pdfData as Data
    }

    // MARK: - Shared options resolution (pure function)

    /// Returns base options unchanged.
    /// Axis spacing (paddingLeft, requiredLeftPadding) is owned exclusively by PlotAxisLayoutPlan.compute.
    func resolvedOptions(payload: WorkbenchPlotPayload, base: Options, style: WorkbenchChartStyle = .init()) -> Options {
        return base
    }

    // MARK: - Canvas layout

    private func drawCanvas(in ctx: CGContext, payload: WorkbenchPlotPayload, options: Options, style: WorkbenchChartStyle, externalLayout: WorkbenchPlotLayout? = nil) {
        let opts = resolvedOptions(payload: payload, base: options, style: style)
        let w = CGFloat(opts.width)
        let h = CGFloat(opts.height)

        // White background
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Use the pipeline-provided layout when available so PNG and canvas share the same
        // legend geometry. Fall back to local computation only when called standalone.
        let layout: WorkbenchPlotLayout
        if let externalLayout {
            layout = externalLayout
        } else {
            var legendNormalizedPoint: CGPoint? = nil
            if let lxStr = payload.styleParams["legendX"], let lyStr = payload.styleParams["legendY"],
               let lx = Double(lxStr), let ly = Double(lyStr) {
                legendNormalizedPoint = CGPoint(x: lx, y: ly)
            }
            layout = WorkbenchPlotLayout.compute(
                options: opts, payload: payload, legendPoint: legendNormalizedPoint, style: style
            )
        }

        // Title — payload.title (and layout.chartTitle) retain their resolved text
        // regardless of showTitle; only the visual draw is gated here.
        if layout.showTitle {
            let title = payload.title.isEmpty ? payload.workflowDisplayName : payload.title
            drawCentered(ctx, text: title,
                         at: layout.titleCenter,
                         size: style.titleFontSize, bold: style.titleBold,
                         color: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                         style: style)
        }

        let allX = payload.series.flatMap(\.x)
        let allY = payload.series.flatMap(\.y)

        guard !allX.isEmpty else {
            ctx.setStrokeColor(CGColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1))
            ctx.setLineWidth(1)
            ctx.stroke(layout.plotRect)
            drawCentered(ctx, text: "No Data",
                         at: CGPoint(x: layout.plotRect.midX, y: layout.plotRect.midY),
                         size: 12, bold: false,
                         color: CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1),
                         style: style)
            return
        }

        // Data extents with 5% x-padding and 8% y-padding so points/labels don't touch the axes
        let xRaw = options.fixedXMin ?? allX.min()!
        let xRawMax = options.fixedXMax ?? allX.max()!
        let yRaw = options.fixedYMin ?? allY.min()!
        let yRawMax = options.fixedYMax ?? allY.max()!
        let xRawSpan = xRawMax == xRaw ? 1.0 : xRawMax - xRaw
        let yRawSpan = yRawMax == yRaw ? 1.0 : yRawMax - yRaw
        let xMin = options.fixedXMin != nil ? xRaw : xRaw - xRawSpan * 0.05
        let xMax = options.fixedXMax != nil ? xRawMax : xRawMax + xRawSpan * 0.05
        let yMin = options.fixedYMin != nil ? yRaw : yRaw - yRawSpan * 0.05
        let yMax = options.fixedYMax != nil ? yRawMax : yRawMax + yRawSpan * 0.05
        let xSpan = xMax - xMin
        let ySpan = yMax - yMin

        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(
                x: layout.plotRect.minX + CGFloat((x - xMin) / xSpan) * layout.plotRect.width,
                y: layout.plotRect.minY + CGFloat((y - yMin) / ySpan) * layout.plotRect.height
            )
        }

        // Grid lines aligned with ticks (opt-in via styleParams["showGrid"] = "true")
        if payload.styleParams["showGrid"] == "true" {
            drawGrid(ctx, plotRect: layout.plotRect,
                     xTicks: layout.xTicks, yTicks: layout.yTicks,
                     xMin: xMin, xSpan: xSpan, yMin: yMin, ySpan: ySpan)
        }

        // Auxiliary vertical line (e.g. x=180 for XY Rotation)
        if let auxXStr = payload.styleParams["auxVerticalX"], let auxX = Double(auxXStr),
           auxX > xMin, auxX < xMax {
            let screenX = layout.plotRect.minX + CGFloat((auxX - xMin) / xSpan) * layout.plotRect.width
            ctx.setStrokeColor(CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1))
            ctx.setLineWidth(1.0)
            ctx.setLineDash(phase: 0, lengths: [5, 4])
            ctx.move(to: CGPoint(x: screenX, y: layout.plotRect.minY))
            ctx.addLine(to: CGPoint(x: screenX, y: layout.plotRect.maxY))
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }

        // Axis box
        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.setLineWidth(1.2)
        ctx.stroke(layout.plotRect)

        // Series lines/scatter — dots and lines clipped to plot area;
        // point labels collected here and drawn after restoreGState so they are never clipped.
        var pendingLabels: [(text: String, center: CGPoint, color: CGColor)] = []

        ctx.saveGState()
        ctx.clip(to: layout.plotRect)
        for (i, series) in payload.series.enumerated() {
            guard series.x.count == series.y.count, !series.x.isEmpty else { continue }
            let color = Self.seriesColors[i % Self.seriesColors.count]
            let drawDots = series.renderMode == .scatter || series.renderMode == .lineAndScatter
            let drawLine = series.renderMode == .line    || series.renderMode == .lineAndScatter

            if drawLine, series.x.count >= 2 {
                ctx.setStrokeColor(color)
                ctx.setLineWidth(CGFloat(series.lineWidth))
                ctx.beginPath()
                ctx.move(to: pt(series.x[0], series.y[0]))
                for k in 1..<series.x.count {
                    ctx.addLine(to: pt(series.x[k], series.y[k]))
                }
                ctx.strokePath()
            }
            if drawDots {
                let r = CGFloat(style.pointRadius ?? 3.5)
                ctx.setFillColor(color)
                for k in 0..<series.x.count {
                    let center = pt(series.x[k], series.y[k])
                    ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r,
                                               width: r * 2, height: r * 2))
                    if k < series.pointLabels.count {
                        let hidden = options.hiddenPointLabelsBySeries[i]
                        if hidden?.contains(k) != true {
                            pendingLabels.append((series.pointLabels[k], center, color))
                        }
                    }
                }
            }
        }
        drawOverlays(
            in: ctx,
            payload: payload,
            baseSeriesCount: payload.series.count,
            plotRect: layout.plotRect,
            style: style,
            pointToScreen: pt
        )
        ctx.restoreGState()

        // Draw point labels outside clip — smart positioning to avoid edge cutoff
        let labelFont = style.pointLabelFontSize
        let r = CGFloat(style.pointRadius ?? 3.5)
        let gap: CGFloat = 4
        let approxLabelW: CGFloat = 50
        let approxLabelH: CGFloat = 20
        let labelColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        for (text, center, _) in pendingLabels {
            let geometry = WorkbenchPlotLayout.pointLabelGeometry(
                center: center,
                plotRect: layout.plotRect,
                dotHitRadius: 7.0,
                dotDrawRadius: r,
                labelWidth: approxLabelW,
                labelHeight: approxLabelH,
                gap: gap
            )
            switch geometry.placement {
            case .left:
                drawRightAligned(ctx, text: text, rightEdge: geometry.drawAnchor,
                                 size: labelFont, bold: false, color: labelColor, style: style)
            case .below:
                drawCentered(ctx, text: text, at: geometry.drawAnchor,
                             size: labelFont, bold: false, color: labelColor,
                             style: style)
            case .right:
                drawLeftAligned(ctx, text: text, leftEdge: geometry.drawAnchor,
                                size: labelFont, bold: false, color: labelColor,
                                style: style)
            }
        }

        // Tick marks + numeric labels on both axes
        drawAxisTicks(ctx, plotRect: layout.plotRect, options: opts, style: style,
                      xTicks: layout.xTicks,
                      yTicks: layout.yTicks)

        // Axis field name labels (markup: _X renders X as subscript)
        let axisColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        drawCenteredMarkup(ctx, text: payload.axisMapping.xField,
                           at: layout.xLabelCenter, size: style.axisTitleFontSize, color: axisColor, style: style)
        drawRotated90Markup(ctx, text: payload.axisMapping.yField,
                            at: layout.yLabelCenter, size: style.axisTitleFontSize, color: axisColor, style: style)

        // Legend — box rect from layout (single source of truth, no local duplication)
        if let boxRect = layout.legendBoxRect {
            drawLegend(ctx, rows: layout.legendRows, boxRect: boxRect, series: payload.series, style: style)
        }
    }

    private func drawOverlays(
        in ctx: CGContext,
        payload: WorkbenchPlotPayload,
        baseSeriesCount: Int,
        plotRect: CGRect,
        style: WorkbenchChartStyle,
        pointToScreen pt: (Double, Double) -> CGPoint
    ) {
        guard !payload.seriesOverlays.isEmpty, baseSeriesCount > 0 else { return }
        let baseIdentities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: payload.series)
        let baseLookup = Dictionary(uniqueKeysWithValues: baseIdentities.enumerated().map { index, identity in
            (identity.identityKey, index)
        })
        for overlay in payload.seriesOverlays {
            guard let parentIndex = baseLookup[overlay.parentSeriesIdentityKey] else { continue }
            let color = Self.seriesColors[parentIndex % Self.seriesColors.count]
            let series = overlay.displaySeries ?? overlay.series
            guard series.x.count == series.y.count, !series.x.isEmpty else { continue }
            let drawDots = series.renderMode == .scatter || series.renderMode == .lineAndScatter
            let drawLine = series.renderMode == .line || series.renderMode == .lineAndScatter
            if drawLine, series.x.count >= 2 {
                ctx.setStrokeColor(color)
                ctx.setLineWidth(CGFloat(series.lineWidth))
                ctx.beginPath()
                ctx.move(to: pt(series.x[0], series.y[0]))
                for k in 1..<series.x.count {
                    ctx.addLine(to: pt(series.x[k], series.y[k]))
                }
                ctx.strokePath()
            }
            if drawDots {
                let r = CGFloat(style.pointRadius ?? 3.5)
                ctx.setFillColor(color)
                for k in 0..<series.x.count {
                    let center = pt(series.x[k], series.y[k])
                    ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                }
            }
        }
    }

    func measureTextWidth(_ text: String, size: CGFloat, bold: Bool = false, style: WorkbenchChartStyle = .init()) -> CGFloat {
        PlotTextMeasurer.measuredWidth(
            text,
            fontSize: size,
            fontName: style.fontName,
            bold: bold,
            boldFontName: style.boldFontName
        )
    }

    func formatTick(_ value: Double, step: Double) -> String {
        PlotAxisSpacingCalculator.formatTick(value, step: step)
    }

    func resolvedXTicks(
        min: Double,
        max: Double,
        plotRect: CGRect,
        style: WorkbenchChartStyle = .init()
    ) -> (ticks: [Double], step: Double, targetCount: Int) {
        PlotAxisSpacingCalculator.resolvedXTicks(min: min, max: max, plotRect: plotRect, style: style)
    }

    // MARK: - Axis tick marks + numeric labels

    private func drawAxisTicks(
        _ ctx: CGContext, plotRect: CGRect, options: Options, style: WorkbenchChartStyle,
        xTicks: [PlotAxisTick],
        yTicks: [PlotAxisTick]
    ) {
        let tickLen: CGFloat = 5
        let tickColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let labelColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let labelSize = style.tickLabelFontSize

        ctx.setStrokeColor(tickColor)
        ctx.setLineWidth(0.8)

        // X-axis ticks (bottom, inward)
        for tick in xTicks {
            let cx = tick.tickPoint.x
            ctx.move(to: CGPoint(x: cx, y: plotRect.minY))
            ctx.addLine(to: CGPoint(x: cx, y: plotRect.minY + tickLen))
            ctx.strokePath()
            drawCentered(ctx, text: tick.label,
                         at: tick.labelPoint,
                         size: labelSize, bold: false, color: labelColor, style: style)
        }

        // Y-axis ticks (left, inward)
        for tick in yTicks {
            let cy = tick.tickPoint.y
            ctx.move(to: CGPoint(x: plotRect.minX, y: cy))
            ctx.addLine(to: CGPoint(x: plotRect.minX + tickLen, y: cy))
            ctx.strokePath()
            drawRightAligned(ctx, text: tick.label,
                             rightEdge: tick.labelPoint,
                             size: labelSize, bold: false, color: labelColor, style: style)
        }
    }

    // MARK: - Grid (tick-aligned)

    private func drawGrid(
        _ ctx: CGContext, plotRect: CGRect,
        xTicks: [PlotAxisTick], yTicks: [PlotAxisTick],
        xMin: Double, xSpan: Double, yMin: Double, ySpan: Double
    ) {
        ctx.setStrokeColor(CGColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1))
        ctx.setLineWidth(0.5)
        ctx.setLineDash(phase: 0, lengths: [3, 3])
        for tick in yTicks {
            let y = tick.tickPoint.y
            ctx.move(to: CGPoint(x: plotRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: plotRect.maxX, y: y))
        }
        for tick in xTicks {
            let x = tick.tickPoint.x
            ctx.move(to: CGPoint(x: x, y: plotRect.minY))
            ctx.addLine(to: CGPoint(x: x, y: plotRect.maxY))
        }
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
    }

    // MARK: - Legend

    /// Draws legend using pre-computed row positions from WorkbenchPlotLayout.
    /// All position math lives in WorkbenchPlotLayout — no duplication here.
    private func drawLegend(_ ctx: CGContext,
                             rows: [WorkbenchPlotLayout.LegendRow],
                             boxRect: CGRect,
                             series: [WorkbenchPlotSeries],
                             style: WorkbenchChartStyle) {
        guard !rows.isEmpty else { return }
        let labelColor = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        let fontSize = style.legendFontSize
        let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: series)
        let seriesLookup = Dictionary(uniqueKeysWithValues: zip(identities, series).map { identity, series in
            (identity.identityKey, (identity.originalIndex, series))
        })

        // White fill + light border
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
        ctx.fill(boxRect)
        ctx.setStrokeColor(CGColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1))
        ctx.setLineWidth(0.8)
        ctx.stroke(boxRect)

        for row in rows {
            guard let (seriesIndex, s) = seriesLookup[row.identityKey] else { continue }
            let color = Self.seriesColors[seriesIndex % Self.seriesColors.count]
            let showDot  = s.renderMode == .scatter || s.renderMode == .lineAndScatter
            let showLine = s.renderMode == .line    || s.renderMode == .lineAndScatter

            if showLine {
                ctx.setStrokeColor(color)
                ctx.setLineWidth(max(CGFloat(s.lineWidth), 3.0))
                ctx.strokeLineSegments(between: [row.lineStart, row.lineEnd])
            }
            if showDot {
                let mid = CGPoint(x: (row.lineStart.x + row.lineEnd.x) / 2,
                                  y: (row.lineStart.y + row.lineEnd.y) / 2)
                let r: CGFloat = 4.0
                ctx.setFillColor(color)
                ctx.fillEllipse(in: CGRect(x: mid.x - r, y: mid.y - r,
                                           width: r * 2, height: r * 2))
            }
            drawLeftAlignedMarkup(ctx, text: s.label, leftEdge: row.labelAnchor,
                            size: fontSize, color: labelColor, style: style)
        }
    }

    // MARK: - CoreText text drawing (no AppKit)

    private func drawCentered(_ ctx: CGContext, text: String, at center: CGPoint,
                               size: CGFloat, bold: Bool, color: CGColor, style: WorkbenchChartStyle) {
        let line = makeLine(text: text, size: size, bold: bold, color: color, style: style)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(
            x: center.x - bounds.width / 2 - bounds.minX,
            y: center.y - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, ctx)
    }

    private func drawLeftAligned(_ ctx: CGContext, text: String, leftEdge: CGPoint,
                                  size: CGFloat, bold: Bool, color: CGColor, style: WorkbenchChartStyle) {
        let line = makeLine(text: text, size: size, bold: bold, color: color, style: style)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(
            x: leftEdge.x - bounds.minX,
            y: leftEdge.y - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, ctx)
    }

    private func drawLeftAlignedMarkup(_ ctx: CGContext, text: String, leftEdge: CGPoint,
                                        size: CGFloat, color: CGColor, style: WorkbenchChartStyle) {
        if MathMarkupRenderer.isMathLabel(text) {
            let line = makeMarkupLine(
                text: MathMarkupRenderer.extractMathMarkup(text),
                size: size,
                color: color,
                style: style
            )
            let bounds = CTLineGetBoundsWithOptions(line, [])
            ctx.textPosition = CGPoint(
                x: leftEdge.x - bounds.minX,
                y: leftEdge.y - bounds.height / 2 - bounds.minY
            )
            CTLineDraw(line, ctx)
            return
        }

        drawLeftAligned(
            ctx,
            text: text,
            leftEdge: leftEdge,
            size: size,
            bold: false,
            color: color,
            style: style
        )
    }

    private func drawRightAligned(_ ctx: CGContext, text: String, rightEdge: CGPoint,
                                   size: CGFloat, bold: Bool, color: CGColor, style: WorkbenchChartStyle) {
        let line = makeLine(text: text, size: size, bold: bold, color: color, style: style)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(
            x: rightEdge.x - bounds.width - bounds.minX,
            y: rightEdge.y - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, ctx)
    }

    private func drawRotated90(_ ctx: CGContext, text: String, at center: CGPoint,
                                size: CGFloat, color: CGColor, style: WorkbenchChartStyle) {
        let line = makeLine(text: text, size: size, bold: false, color: color, style: style)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: .pi / 2)
        ctx.textPosition = CGPoint(
            x: -bounds.width / 2 - bounds.minX,
            y: -bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private func makeMarkupLine(text: String, size: CGFloat, color: CGColor, style: WorkbenchChartStyle) -> CTLine {
        MathMarkupRenderer.makeLine(text: text, size: size, color: color, style: style)
    }

    private func drawCenteredMarkup(_ ctx: CGContext, text: String, at center: CGPoint,
                                    size: CGFloat, color: CGColor, style: WorkbenchChartStyle) {
        if MathMarkupRenderer.isMathLabel(text) {
            let line = makeMarkupLine(
                text: MathMarkupRenderer.extractMathMarkup(text),
                size: size,
                color: color,
                style: style
            )
            let bounds = CTLineGetBoundsWithOptions(line, [])
            ctx.textPosition = CGPoint(
                x: center.x - bounds.width / 2 - bounds.minX,
                y: center.y - bounds.height / 2 - bounds.minY
            )
            CTLineDraw(line, ctx)
            return
        }
        let line = makeLine(text: text, size: size, bold: false, color: color, style: style)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(
            x: center.x - bounds.width / 2 - bounds.minX,
            y: center.y - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, ctx)
    }

    private func drawRotated90Markup(_ ctx: CGContext, text: String, at center: CGPoint,
                                     size: CGFloat, color: CGColor, style: WorkbenchChartStyle) {
        if MathMarkupRenderer.isMathLabel(text) {
            let line = makeMarkupLine(
                text: MathMarkupRenderer.extractMathMarkup(text),
                size: size,
                color: color,
                style: style
            )
            let bounds = CTLineGetBoundsWithOptions(line, [])
            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: .pi / 2)
            ctx.textPosition = CGPoint(
                x: -bounds.width / 2 - bounds.minX,
                y: -bounds.height / 2 - bounds.minY
            )
            CTLineDraw(line, ctx)
            ctx.restoreGState()
            return
        }
        let line = makeLine(text: text, size: size, bold: false, color: color, style: style)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: .pi / 2)
        ctx.textPosition = CGPoint(
            x: -bounds.width / 2 - bounds.minX,
            y: -bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private func makeLine(text: String, size: CGFloat, bold: Bool, color: CGColor, style: WorkbenchChartStyle) -> CTLine {
        let font = style.ctFont(size: size, bold: bold)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
        ]
        let attrStr = CFAttributedStringCreate(
            kCFAllocatorDefault, text as CFString, attrs as CFDictionary
        )!
        return CTLineCreateWithAttributedString(attrStr)
    }
}
