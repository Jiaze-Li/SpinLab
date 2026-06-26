import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// Pure CoreGraphics PNG renderer for the dual-axis render path (Plot System-owned).
/// No SwiftUI or AppKit. Parallel to WorkbenchChartRenderer; must not extend it.
/// Left-axis series are drawn with solid lines; right-axis series with dashed lines.
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
        style: WorkbenchChartStyle = .init()
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
            style: style
        )
        return try renderPNG(
            payload: payload,
            validLeftSeries: validLeft,
            validRightSeries: validRight,
            layout: layout,
            options: options,
            style: style
        )
    }

    func renderPNG(
        payload: DualAxisPlotPayload,
        validLeftSeries: [DualAxisPlotSeries],
        validRightSeries: [DualAxisPlotSeries],
        layout: DualAxisPlotLayout,
        options: DualAxisPlotLayout.Options = .init(),
        style: WorkbenchChartStyle = .init()
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
            style: style
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
        style: WorkbenchChartStyle
    ) {
        let w = layout.rendererSize.width
        let h = layout.rendererSize.height
        let black    = CGColor(red: 0,   green: 0,   blue: 0,   alpha: 1)
        let darkGray = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        let dimGray  = CGColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)

        // White background
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Title
        if !payload.title.isEmpty {
            drawCentered(ctx, text: payload.title, at: layout.titleCenter,
                         size: style.titleFontSize, bold: style.titleBold, color: black, style: style)
        }

        // Plot box border
        ctx.setStrokeColor(darkGray)
        ctx.setLineWidth(1.2)
        ctx.stroke(layout.plotRect)

        // X ticks
        drawXTicks(ctx: ctx, layout: layout, style: style, color: darkGray, labelColor: dimGray)

        // Left Y ticks
        drawLeftYTicks(ctx: ctx, layout: layout, style: style, color: darkGray, labelColor: dimGray)

        // Right Y ticks
        drawRightYTicks(ctx: ctx, layout: layout, style: style, color: darkGray, labelColor: dimGray)

        // X label
        if !payload.xLabel.isEmpty {
            drawCentered(ctx, text: payload.xLabel, at: layout.xLabelCenter,
                         size: style.axisTitleFontSize, bold: false, color: black, style: style)
        }

        // Left Y label (rotated counter-clockwise)
        if !payload.leftYLabel.isEmpty {
            drawRotated(ctx, text: payload.leftYLabel, at: layout.leftYLabelCenter,
                        clockwise: false, size: style.axisTitleFontSize, color: black, style: style)
        }

        // Right Y label (rotated clockwise)
        if !payload.rightYLabel.isEmpty {
            drawRotated(ctx, text: payload.rightYLabel, at: layout.rightYLabelCenter,
                        clockwise: true, size: style.axisTitleFontSize, color: black, style: style)
        }

        // Series (clipped to plotRect)
        for (i, series) in validLeftSeries.enumerated() {
            let color = Self.palette[i % Self.palette.count]
            drawSeries(ctx, series: series,
                       yMin: layout.axisLeftYMin, yMax: layout.axisLeftYMax,
                       layout: layout, color: color, dashed: false)
        }
        for (i, series) in validRightSeries.enumerated() {
            let color = Self.palette[(i + validLeftSeries.count) % Self.palette.count]
            drawSeries(ctx, series: series,
                       yMin: layout.axisRightYMin, yMax: layout.axisRightYMax,
                       layout: layout, color: color, dashed: true)
        }

        // Legend
        let allLeft  = validLeftSeries.enumerated().map { (i, s) in (s, Self.palette[i % Self.palette.count], false) }
        let allRight = validRightSeries.enumerated().map { (i, s) in
            (s, Self.palette[(i + validLeftSeries.count) % Self.palette.count], true)
        }
        let legendEntries = allLeft + allRight
        if !legendEntries.isEmpty {
            drawLegend(ctx, entries: legendEntries, layout: layout, style: style)
        }
    }

    // MARK: - Ticks

    private func drawXTicks(
        ctx: CGContext,
        layout: DualAxisPlotLayout,
        style: WorkbenchChartStyle,
        color: CGColor,
        labelColor: CGColor
    ) {
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

    private func drawLeftYTicks(
        ctx: CGContext,
        layout: DualAxisPlotLayout,
        style: WorkbenchChartStyle,
        color: CGColor,
        labelColor: CGColor
    ) {
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

    private func drawRightYTicks(
        ctx: CGContext,
        layout: DualAxisPlotLayout,
        style: WorkbenchChartStyle,
        color: CGColor,
        labelColor: CGColor
    ) {
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
        dashed: Bool
    ) {
        let points: [CGPoint] = zip(series.x, series.y).compactMap { (x, y) in
            guard x.isFinite, y.isFinite else { return nil }
            return cgPoint(x: x, y: y, yMin: yMin, yMax: yMax, layout: layout)
        }
        guard !points.isEmpty else { return }

        ctx.saveGState()
        ctx.clip(to: layout.plotRect.insetBy(dx: -1, dy: -1))

        let lw = CGFloat(series.lineWidth)

        if series.renderMode == .line || series.renderMode == .lineAndScatter {
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lw)
            if dashed {
                let phase: CGFloat = 0
                let lengths: [CGFloat] = [6, 3]
                ctx.setLineDash(phase: phase, lengths: lengths)
            } else {
                ctx.setLineDash(phase: 0, lengths: [])
            }
            ctx.move(to: points[0])
            for p in points.dropFirst() { ctx.addLine(to: p) }
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }

        if series.renderMode == .scatter || series.renderMode == .lineAndScatter {
            ctx.setFillColor(color)
            let r: CGFloat = max(2.5, lw * 1.2)
            for p in points {
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
        }

        ctx.restoreGState()
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
        entries: [(series: DualAxisPlotSeries, color: CGColor, dashed: Bool)],
        layout: DualAxisPlotLayout,
        style: WorkbenchChartStyle
    ) {
        let rowH: CGFloat = style.legendFontSize + 8
        let symW: CGFloat = 22
        let symGap: CGFloat = 6
        let hPad: CGFloat = 8
        let vPad: CGFloat = 6

        let maxLabelW = entries.map {
            PlotTextMeasurer.measuredWidth($0.series.label, fontSize: style.legendFontSize, fontName: style.fontName)
        }.max() ?? 60

        let boxW = hPad + symW + symGap + maxLabelW + hPad
        let boxH = vPad + rowH * CGFloat(entries.count) + vPad

        let boxX = layout.plotRect.maxX - boxW - 8
        let boxY = layout.plotRect.maxY - boxH - 8

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
            if entry.dashed {
                ctx.setLineDash(phase: 0, lengths: [5, 2.5])
            } else {
                ctx.setLineDash(phase: 0, lengths: [])
            }
            ctx.move(to: CGPoint(x: symStartX, y: midY))
            ctx.addLine(to: CGPoint(x: symStartX + symW, y: midY))
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])

            ctx.setFillColor(entry.color)
            let r: CGFloat = 3
            ctx.fillEllipse(in: CGRect(x: symStartX + symW * 0.5 - r, y: midY - r, width: r * 2, height: r * 2))

            let labelX = symStartX + symW + symGap
            drawLeftAligned(ctx, text: entry.series.label,
                            leftEdge: CGPoint(x: labelX, y: midY),
                            size: style.legendFontSize, color: labelColor, style: style)
        }
    }

    // MARK: - CoreText primitives

    private func makeLine(
        _ text: String, size: CGFloat, bold: Bool, color: CGColor, style: WorkbenchChartStyle
    ) -> CTLine {
        let fontName = bold ? style.boldFontName : style.fontName
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName:            font,
            kCTForegroundColorAttributeName: color,
        ]
        let attrStr = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attrs as CFDictionary)!
        return CTLineCreateWithAttributedString(attrStr)
    }

    private func drawCentered(_ ctx: CGContext, text: String, at center: CGPoint,
                               size: CGFloat, bold: Bool, color: CGColor, style: WorkbenchChartStyle) {
        let line   = makeLine(text, size: size, bold: bold, color: color, style: style)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(
            x: center.x - bounds.width / 2 - bounds.minX,
            y: center.y - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, ctx)
    }

    private func drawLeftAligned(_ ctx: CGContext, text: String, leftEdge: CGPoint,
                                  size: CGFloat, color: CGColor, style: WorkbenchChartStyle) {
        let line   = makeLine(text, size: size, bold: false, color: color, style: style)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(
            x: leftEdge.x - bounds.minX,
            y: leftEdge.y - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, ctx)
    }

    private func drawRightAligned(_ ctx: CGContext, text: String, rightEdge: CGPoint,
                                   size: CGFloat, color: CGColor, style: WorkbenchChartStyle) {
        let line   = makeLine(text, size: size, bold: false, color: color, style: style)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(
            x: rightEdge.x - bounds.width - bounds.minX,
            y: rightEdge.y - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, ctx)
    }

    private func drawRotated(_ ctx: CGContext, text: String, at center: CGPoint,
                              clockwise: Bool, size: CGFloat, color: CGColor, style: WorkbenchChartStyle) {
        let line   = makeLine(text, size: size, bold: false, color: color, style: style)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: clockwise ? -.pi / 2 : .pi / 2)
        ctx.textPosition = CGPoint(
            x: -bounds.width / 2 - bounds.minX,
            y: -bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: - Color palette

    private static let palette: [CGColor] = [
        CGColor(red: 0.18, green: 0.38, blue: 0.75, alpha: 1), // blue
        CGColor(red: 0.76, green: 0.18, blue: 0.18, alpha: 1), // red
        CGColor(red: 0.12, green: 0.58, blue: 0.22, alpha: 1), // green
        CGColor(red: 0.80, green: 0.48, blue: 0.00, alpha: 1), // orange
        CGColor(red: 0.48, green: 0.10, blue: 0.68, alpha: 1), // purple
        CGColor(red: 0.10, green: 0.60, blue: 0.65, alpha: 1), // teal
    ]
}
