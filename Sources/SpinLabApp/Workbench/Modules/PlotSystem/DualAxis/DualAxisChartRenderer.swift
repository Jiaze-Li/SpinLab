import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// Pure CoreGraphics PNG renderer for the dual-axis render path (Plot System-owned).
/// No SwiftUI or AppKit. Parallel to WorkbenchChartRenderer; must not extend it.
struct DualAxisChartRenderer {

    enum RendererError: Error, LocalizedError {
        case contextCreationFailed
        case imageCreationFailed
        case destinationCreationFailed
        case finalizeFailed

        var errorDescription: String? {
            switch self {
            case .contextCreationFailed:     return "Failed to create CGContext."
            case .imageCreationFailed:       return "Failed to create CGImage."
            case .destinationCreationFailed: return "Failed to create image destination."
            case .finalizeFailed:            return "Failed to finalize PNG."
            }
        }
    }

    // MARK: - Public

    func renderPNG(
        payload: DualAxisPlotPayload,
        options: DualAxisPlotLayout.Options = .init(),
        style: WorkbenchChartStyle = .init(),
        displayState: DualAxisDisplayStateSnapshot = .default,
        legendPoint: CGPoint? = nil
    ) throws -> Data {
        let validLeft = payload.leftSeries.filter {
            $0.x.count == $0.y.count && $0.x.contains(where: \.isFinite)
        }
        let validRight = payload.rightSeries.filter {
            $0.x.count == $0.y.count && $0.x.contains(where: \.isFinite)
        }
        let layout = DualAxisPlotLayout.compute(
            payload: payload,
            validLeftSeries: validLeft,
            validRightSeries: validRight,
            options: options,
            style: style,
            displayState: displayState,
            legendPoint: legendPoint
        )
        return try renderPNG(
            payload: payload,
            validLeftSeries: validLeft,
            validRightSeries: validRight,
            layout: layout,
            options: options,
            style: style,
            displayState: displayState
        )
    }

    func renderPNG(
        payload: DualAxisPlotPayload,
        validLeftSeries: [DualAxisPlotSeries],
        validRightSeries: [DualAxisPlotSeries],
        layout: DualAxisPlotLayout,
        options: DualAxisPlotLayout.Options = .init(),
        style: WorkbenchChartStyle = .init(),
        displayState: DualAxisDisplayStateSnapshot = .default
    ) throws -> Data {
        let scale = max(options.pixelScale, 1)
        let pixelW = Int((layout.rendererSize.width * scale).rounded())
        let pixelH = Int((layout.rendererSize.height * scale).rounded())

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(
            data: nil, width: pixelW, height: pixelH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ) else { throw RendererError.contextCreationFailed }

        ctx.scaleBy(x: scale, y: scale)
        drawCanvas(
            ctx: ctx,
            payload: payload,
            validLeftSeries: validLeftSeries,
            validRightSeries: validRightSeries,
            layout: layout,
            style: style,
            displayState: displayState
        )

        guard let cgImage = ctx.makeImage() else { throw RendererError.imageCreationFailed }

        let buffer = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            buffer as CFMutableData, "public.png" as CFString, 1, nil
        ) else { throw RendererError.destinationCreationFailed }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { throw RendererError.finalizeFailed }
        return buffer as Data
    }

    // MARK: - Canvas

    private func drawCanvas(
        ctx: CGContext,
        payload: DualAxisPlotPayload,
        validLeftSeries: [DualAxisPlotSeries],
        validRightSeries: [DualAxisPlotSeries],
        layout: DualAxisPlotLayout,
        style: WorkbenchChartStyle,
        displayState: DualAxisDisplayStateSnapshot
    ) {
        let w = layout.rendererSize.width
        let h = layout.rendererSize.height
        let black    = CGColor(red: 0,   green: 0,   blue: 0,   alpha: 1)
        let darkGray = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        let dimGray  = CGColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)
        let leftAxisColor = axisColor(for: .leftAxisBlue, policy: displayState.axisColorPolicy, fallback: darkGray)
        let rightAxisColor = axisColor(for: .rightAxisRed, policy: displayState.axisColorPolicy, fallback: darkGray)
        let leftSeriesColor = color(for: displayState.leftSeriesStyle.colorRole ?? .leftAxisBlue)
        let rightSeriesColor = color(for: displayState.rightSeriesStyle.colorRole ?? .rightAxisRed)

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        if !payload.title.isEmpty {
            drawCentered(ctx, text: payload.title, at: layout.titleCenter,
                         size: style.titleFontSize, bold: style.titleBold, color: black, style: style)
        }

        ctx.setStrokeColor(darkGray)
        ctx.setLineWidth(1.2)
        ctx.stroke(layout.plotRect)

        drawXTicks(ctx: ctx, layout: layout, style: style, color: darkGray, labelColor: dimGray)
        drawLeftYTicks(ctx: ctx, layout: layout, style: style, color: leftAxisColor, labelColor: leftAxisColor)
        drawRightYTicks(ctx: ctx, layout: layout, style: style, color: rightAxisColor, labelColor: rightAxisColor)

        if !payload.xLabel.isEmpty {
            drawCentered(ctx, text: payload.xLabel, at: layout.xLabelCenter,
                         size: style.axisTitleFontSize, bold: false, color: black, style: style)
        }

        if !payload.leftYLabel.isEmpty {
            drawRotated(ctx, text: payload.leftYLabel, at: layout.leftYLabelCenter,
                        clockwise: false, size: style.axisTitleFontSize, color: leftAxisColor, style: style)
        }

        if !payload.rightYLabel.isEmpty {
            drawRotated(ctx, text: payload.rightYLabel, at: layout.rightYLabelCenter,
                        clockwise: true, size: style.axisTitleFontSize, color: rightAxisColor, style: style)
        }

        for series in validLeftSeries {
            drawSeries(ctx, series: series,
                       yMin: layout.axisLeftYMin, yMax: layout.axisLeftYMax,
                       layout: layout, color: leftSeriesColor,
                       familyStyle: displayState.leftSeriesStyle,
                       globalStyle: style)
        }
        for series in validRightSeries {
            drawSeries(ctx, series: series,
                       yMin: layout.axisRightYMin, yMax: layout.axisRightYMax,
                       layout: layout, color: rightSeriesColor,
                       familyStyle: displayState.rightSeriesStyle,
                       globalStyle: style)
        }

        let allLeft  = validLeftSeries.map { ($0, leftSeriesColor, displayState.leftSeriesStyle) }
        let allRight = validRightSeries.map { ($0, rightSeriesColor, displayState.rightSeriesStyle) }
        let legendEntries = allLeft + allRight
        if !legendEntries.isEmpty {
            drawLegend(ctx, entries: legendEntries, layout: layout, style: style)
        }
    }

    // MARK: - Ticks

    private func drawXTicks(ctx: CGContext, layout: DualAxisPlotLayout, style: WorkbenchChartStyle, color: CGColor, labelColor: CGColor) {
        let tickLen: CGFloat = 6
        ctx.setStrokeColor(color)
        ctx.setLineWidth(0.8)
        for tick in layout.xTicks {
            let tp = tick.tickPoint
            ctx.move(to: tp)
            ctx.addLine(to: CGPoint(x: tp.x, y: tp.y - tickLen))
            ctx.strokePath()
            drawCentered(ctx, text: tick.label,
                         at: CGPoint(x: tick.labelPoint.x, y: tick.labelPoint.y - style.tickLabelFontSize * 0.5),
                         size: style.tickLabelFontSize, bold: false, color: labelColor, style: style)
        }
    }

    private func drawLeftYTicks(ctx: CGContext, layout: DualAxisPlotLayout, style: WorkbenchChartStyle, color: CGColor, labelColor: CGColor) {
        let tickLen: CGFloat = 6
        ctx.setStrokeColor(color)
        ctx.setLineWidth(0.8)
        for tick in layout.leftYTicks {
            let tp = tick.tickPoint
            ctx.move(to: tp)
            ctx.addLine(to: CGPoint(x: tp.x - tickLen, y: tp.y))
            ctx.strokePath()
            drawRightAligned(ctx, text: tick.label,
                             rightEdge: tick.labelPoint,
                             size: style.tickLabelFontSize, color: labelColor, style: style)
        }
    }

    private func drawRightYTicks(ctx: CGContext, layout: DualAxisPlotLayout, style: WorkbenchChartStyle, color: CGColor, labelColor: CGColor) {
        let tickLen: CGFloat = 6
        ctx.setStrokeColor(color)
        ctx.setLineWidth(0.8)
        for tick in layout.rightYTicks {
            let tp = tick.tickPoint
            ctx.move(to: tp)
            ctx.addLine(to: CGPoint(x: tp.x + tickLen, y: tp.y))
            ctx.strokePath()
            drawLeftAligned(ctx, text: tick.label,
                            leftEdge: tick.labelPoint,
                            size: style.tickLabelFontSize, color: labelColor, style: style)
        }
    }

    // MARK: - Series

    private func drawSeries(
        _ ctx: CGContext,
        series: DualAxisPlotSeries,
        yMin: Double,
        yMax: Double,
        layout: DualAxisPlotLayout,
        color: CGColor,
        familyStyle: DualAxisSeriesVisualStyle,
        globalStyle: WorkbenchChartStyle
    ) {
        let points: [CGPoint] = zip(series.x, series.y).compactMap { (x, y) in
            guard x.isFinite, y.isFinite else { return nil }
            return cgPoint(x: x, y: y, yMin: yMin, yMax: yMax, layout: layout)
        }
        guard !points.isEmpty else { return }

        ctx.saveGState()
        ctx.clip(to: layout.plotRect.insetBy(dx: -1, dy: -1))

        let renderMode = familyStyle.renderMode ?? series.renderMode
        let lw = CGFloat(familyStyle.lineWidth ?? globalStyle.lineWidth ?? series.lineWidth)
        let radius = CGFloat(familyStyle.pointRadius ?? globalStyle.pointRadius ?? max(2.5, Double(lw) * 1.2))

        if renderMode == .line || renderMode == .lineAndScatter {
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lw)
            switch familyStyle.linePattern {
            case .solid:  ctx.setLineDash(phase: 0, lengths: [])
            case .dashed: ctx.setLineDash(phase: 0, lengths: [6, 3])
            }
            ctx.move(to: points[0])
            for p in points.dropFirst() { ctx.addLine(to: p) }
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }

        if renderMode == .scatter || renderMode == .lineAndScatter {
            for p in points {
                drawMarker(ctx, center: p, radius: radius, color: color, style: familyStyle)
            }
        }

        ctx.restoreGState()
    }

    private func drawMarker(_ ctx: CGContext, center: CGPoint, radius: CGFloat, color: CGColor, style: DualAxisSeriesVisualStyle) {
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(1.4)
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        switch (style.markerShape, style.markerFill) {
        case (.circle, .filled): ctx.fillEllipse(in: rect)
        case (.circle, .open):   ctx.strokeEllipse(in: rect)
        case (.square, .filled): ctx.fill(rect)
        case (.square, .open):   ctx.stroke(rect)
        }
    }

    private func cgPoint(x: Double, y: Double, yMin: Double, yMax: Double, layout: DualAxisPlotLayout) -> CGPoint {
        let xRange = layout.axisXMax - layout.axisXMin
        let yRange = yMax - yMin
        let cgX = xRange > 0
            ? layout.plotRect.minX + CGFloat((x - layout.axisXMin) / xRange) * layout.plotRect.width
            : layout.plotRect.midX
        let cgY = yRange > 0
            ? layout.plotRect.minY + CGFloat((y - yMin) / yRange) * layout.plotRect.height
            : layout.plotRect.midY
        return CGPoint(x: cgX, y: cgY)
    }

    // MARK: - Legend

    private func drawLegend(
        _ ctx: CGContext,
        entries: [(series: DualAxisPlotSeries, color: CGColor, style: DualAxisSeriesVisualStyle)],
        layout: DualAxisPlotLayout,
        style: WorkbenchChartStyle
    ) {
        let rowH: CGFloat = style.legendFontSize + 8
        let symW: CGFloat = 22
        let symGap: CGFloat = 6
        let hPad: CGFloat = 8
        let vPad: CGFloat = 6

        guard let boxRect = layout.legendBoxRect, let _ = layout.legendOriginCG else { return }
        let boxX = boxRect.minX
        let boxY = boxRect.minY
        let boxW = boxRect.width
        let boxH = boxRect.height

        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 0.85)
        let border = CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)

        ctx.setFillColor(white)
        ctx.fill(CGRect(x: boxX, y: boxY, width: boxW, height: boxH))
        ctx.setStrokeColor(border)
        ctx.setLineWidth(0.6)
        ctx.stroke(CGRect(x: boxX, y: boxY, width: boxW, height: boxH))

        let labelColor = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)

        for (row, entry) in entries.reversed().enumerated() {
            let rowY = boxY + vPad + CGFloat(row) * rowH
            let midY = rowY + rowH * 0.5
            let symStartX = boxX + hPad

            ctx.setStrokeColor(entry.color)
            ctx.setLineWidth(2.0)
            switch entry.style.linePattern {
            case .solid:  ctx.setLineDash(phase: 0, lengths: [])
            case .dashed: ctx.setLineDash(phase: 0, lengths: [5, 2.5])
            }
            ctx.move(to: CGPoint(x: symStartX, y: midY))
            ctx.addLine(to: CGPoint(x: symStartX + symW, y: midY))
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])

            drawMarker(ctx, center: CGPoint(x: symStartX + symW * 0.5, y: midY), radius: 3, color: entry.color, style: entry.style)

            let labelX = symStartX + symW + symGap
            drawLeftAligned(ctx, text: entry.series.label,
                            leftEdge: CGPoint(x: labelX, y: midY),
                            size: style.legendFontSize, color: labelColor, style: style)
        }
    }

    // MARK: - CoreText primitives

    private func makeLine(_ text: String, size: CGFloat, bold: Bool, color: CGColor, style: WorkbenchChartStyle) -> CTLine {
        // Route "math:"-prefixed labels through the same MathMarkupRenderer used by the
        // single-axis WorkbenchChartRenderer, so dual-axis labels/legend never show the literal
        // "math:" prefix or raw _{...}/^{...} markup (see WorkbenchChartRenderer's *Markup helpers).
        if MathMarkupRenderer.isMathLabel(text) {
            return MathMarkupRenderer.makeLine(
                text: MathMarkupRenderer.extractMathMarkup(text),
                size: size,
                color: color,
                style: style
            )
        }
        let fontName = bold ? style.boldFontName : style.fontName
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
        ]
        let attrStr = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attrs as CFDictionary)!
        return CTLineCreateWithAttributedString(attrStr)
    }

    private func drawCentered(_ ctx: CGContext, text: String, at center: CGPoint, size: CGFloat, bold: Bool, color: CGColor, style: WorkbenchChartStyle) {
        let line = makeLine(text, size: size, bold: bold, color: color, style: style)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(x: center.x - bounds.width / 2 - bounds.minX, y: center.y - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, ctx)
    }

    private func drawLeftAligned(_ ctx: CGContext, text: String, leftEdge: CGPoint, size: CGFloat, color: CGColor, style: WorkbenchChartStyle) {
        let line = makeLine(text, size: size, bold: false, color: color, style: style)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(x: leftEdge.x - bounds.minX, y: leftEdge.y - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, ctx)
    }

    private func drawRightAligned(_ ctx: CGContext, text: String, rightEdge: CGPoint, size: CGFloat, color: CGColor, style: WorkbenchChartStyle) {
        let line = makeLine(text, size: size, bold: false, color: color, style: style)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(x: rightEdge.x - bounds.width - bounds.minX, y: rightEdge.y - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, ctx)
    }

    private func drawRotated(_ ctx: CGContext, text: String, at center: CGPoint, clockwise: Bool, size: CGFloat, color: CGColor, style: WorkbenchChartStyle) {
        let line = makeLine(text, size: size, bold: false, color: color, style: style)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: clockwise ? -.pi / 2 : .pi / 2)
        ctx.textPosition = CGPoint(x: -bounds.width / 2 - bounds.minX, y: -bounds.height / 2 - bounds.minY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: - Colors

    private func axisColor(for role: DualAxisColorRole, policy: DualAxisAxisColorPolicy, fallback: CGColor) -> CGColor {
        switch policy {
        case .templatePaired: return color(for: role)
        case .monochrome:    return fallback
        }
    }

    private func color(for role: DualAxisColorRole) -> CGColor {
        switch role {
        case .leftAxisBlue: return CGColor(red: 0.18, green: 0.38, blue: 0.75, alpha: 1)
        case .rightAxisRed: return CGColor(red: 0.76, green: 0.18, blue: 0.18, alpha: 1)
        case .black:        return CGColor(red: 0,    green: 0,    blue: 0,    alpha: 1)
        case .gray:         return CGColor(red: 0.3,  green: 0.3,  blue: 0.3,  alpha: 1)
        case .green:        return CGColor(red: 0.12, green: 0.58, blue: 0.22, alpha: 1)
        case .orange:       return CGColor(red: 0.80, green: 0.48, blue: 0.00, alpha: 1)
        case .purple:       return CGColor(red: 0.48, green: 0.10, blue: 0.68, alpha: 1)
        case .teal:         return CGColor(red: 0.10, green: 0.60, blue: 0.65, alpha: 1)
        }
    }
}
