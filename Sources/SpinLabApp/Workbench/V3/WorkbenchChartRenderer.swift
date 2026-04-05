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

    // matplotlib-style default series colors (6 entries, wraps)
    private static let seriesColors: [CGColor] = [
        CGColor(red: 0.122, green: 0.467, blue: 0.706, alpha: 1), // C0 blue
        CGColor(red: 1.000, green: 0.498, blue: 0.055, alpha: 1), // C1 orange
        CGColor(red: 0.173, green: 0.627, blue: 0.173, alpha: 1), // C2 green
        CGColor(red: 0.839, green: 0.153, blue: 0.157, alpha: 1), // C3 red
        CGColor(red: 0.580, green: 0.404, blue: 0.741, alpha: 1), // C4 purple
        CGColor(red: 0.549, green: 0.337, blue: 0.294, alpha: 1), // C5 brown
    ]

    // MARK: - Public

    func renderPNG(payload: WorkbenchPlotPayload, options: Options = .init()) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(
            data: nil,
            width: options.width,
            height: options.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { throw RendererError.contextCreationFailed }

        drawCanvas(in: ctx, payload: payload, options: options)

        guard let cgImage = ctx.makeImage() else { throw RendererError.imageCreationFailed }

        let buffer = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            buffer as CFMutableData, "public.png" as CFString, 1, nil
        ) else { throw RendererError.destinationCreationFailed }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { throw RendererError.finalizeFailed }
        return buffer as Data
    }

    // MARK: - Canvas layout

    private func drawCanvas(in ctx: CGContext, payload: WorkbenchPlotPayload, options: Options) {
        let w = CGFloat(options.width)
        let h = CGFloat(options.height)
        let plotRect = CGRect(
            x: options.paddingLeft,
            y: options.paddingBottom,
            width: w - options.paddingLeft - options.paddingRight,
            height: h - options.paddingTop - options.paddingBottom
        )

        // White background
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Title
        let title = payload.title.isEmpty ? payload.workflowDisplayName : payload.title
        drawCentered(ctx, text: title,
                     at: CGPoint(x: w / 2, y: h - options.paddingTop * 0.45),
                     size: 21, bold: true,
                     color: CGColor(red: 0, green: 0, blue: 0, alpha: 1))

        let allX = payload.series.flatMap(\.x)
        let allY = payload.series.flatMap(\.y)

        guard !allX.isEmpty else {
            ctx.setStrokeColor(CGColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1))
            ctx.setLineWidth(1)
            ctx.stroke(plotRect)
            drawCentered(ctx, text: "No Data",
                         at: CGPoint(x: plotRect.midX, y: plotRect.midY),
                         size: 12, bold: false,
                         color: CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1))
            return
        }

        // Data extents
        let xMin = allX.min()!, xMax = allX.max()!
        let yMin = allY.min()!, yMax = allY.max()!
        let xSpan = xMax == xMin ? 1.0 : xMax - xMin
        let ySpan = yMax == yMin ? 1.0 : yMax - yMin

        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(
                x: plotRect.minX + CGFloat((x - xMin) / xSpan) * plotRect.width,
                y: plotRect.minY + CGFloat((y - yMin) / ySpan) * plotRect.height
            )
        }

        let (xTicks, xStep) = niceTicks(min: xMin, max: xMax, targetCount: 5)
        let (yTicks, yStep) = niceTicks(min: yMin, max: yMax, targetCount: 5)

        // Grid lines aligned with ticks (opt-in via styleParams["showGrid"] = "true")
        if payload.styleParams["showGrid"] == "true" {
            drawGrid(ctx, plotRect: plotRect,
                     xTicks: xTicks, yTicks: yTicks,
                     xMin: xMin, xSpan: xSpan, yMin: yMin, ySpan: ySpan)
        }

        // Axis box
        ctx.setStrokeColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        ctx.setLineWidth(1.2)
        ctx.stroke(plotRect)

        // Series lines — clipped to plot area
        ctx.saveGState()
        ctx.clip(to: plotRect)
        for (i, series) in payload.series.enumerated() {
            guard series.x.count == series.y.count, series.x.count >= 2 else { continue }
            ctx.setStrokeColor(Self.seriesColors[i % Self.seriesColors.count])
            ctx.setLineWidth(1.5)
            ctx.beginPath()
            ctx.move(to: pt(series.x[0], series.y[0]))
            for k in 1..<series.x.count {
                ctx.addLine(to: pt(series.x[k], series.y[k]))
            }
            ctx.strokePath()
        }
        ctx.restoreGState()

        // Tick marks + numeric labels on both axes
        drawAxisTicks(ctx, plotRect: plotRect, options: options,
                      xTicks: xTicks, xStep: xStep,
                      yTicks: yTicks, yStep: yStep,
                      xMin: xMin, xSpan: xSpan, yMin: yMin, ySpan: ySpan)

        // Axis field name labels (markup: _X renders X as subscript)
        let axisColor = CGColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1)
        drawCenteredMarkup(ctx, text: payload.axisMapping.xField,
                           at: CGPoint(x: w / 2, y: options.paddingBottom * 0.58),
                           size: 18, color: axisColor)
        drawRotated90Markup(ctx, text: payload.axisMapping.yField,
                            at: CGPoint(x: options.paddingLeft * 0.20, y: h / 2),
                            size: 18, color: axisColor)

        // Legend — normalized point takes priority over anchor string
        let legendAnchor = payload.styleParams["legendAnchor"] ?? "top-right"
        var legendNormalizedPoint: CGPoint? = nil
        if let lxStr = payload.styleParams["legendX"], let lyStr = payload.styleParams["legendY"],
           let lx = Double(lxStr), let ly = Double(lyStr) {
            legendNormalizedPoint = CGPoint(x: lx, y: ly)
        }
        drawLegend(ctx, series: payload.series, plotRect: plotRect,
                   anchor: legendAnchor, normalizedPoint: legendNormalizedPoint)
    }

    // MARK: - Tick computation

    /// Returns (ticks, step) where ticks are "nice" values within [min, max].
    private func niceTicks(min: Double, max: Double, targetCount: Int = 5) -> (ticks: [Double], step: Double) {
        guard max > min, targetCount > 0 else { return ([min, max], max - min) }
        let range = max - min
        let roughStep = range / Double(targetCount)
        let magnitude = pow(10.0, floor(log10(abs(roughStep))))
        let normalized = roughStep / magnitude
        let niceNorm: Double
        if normalized < 1.5      { niceNorm = 1 }
        else if normalized < 3.5 { niceNorm = 2 }
        else if normalized < 7.5 { niceNorm = 5 }
        else                     { niceNorm = 10 }
        let step = niceNorm * magnitude
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

    private func formatTick(_ value: Double, step: Double) -> String {
        if abs(value) < step * 1e-9 { return "0" }
        // k-notation for large steps
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
        return String(format: "%.2e", value)
    }

    // MARK: - Axis tick marks + numeric labels

    private func drawAxisTicks(
        _ ctx: CGContext, plotRect: CGRect, options: Options,
        xTicks: [Double], xStep: Double,
        yTicks: [Double], yStep: Double,
        xMin: Double, xSpan: Double,
        yMin: Double, ySpan: Double
    ) {
        let tickLen: CGFloat = 5
        let labelGap: CGFloat = 5
        let tickColor = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        let labelColor = CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        let labelSize: CGFloat = 11

        ctx.setStrokeColor(tickColor)
        ctx.setLineWidth(0.8)

        // X-axis ticks (bottom, inward)
        for tick in xTicks {
            let cx = plotRect.minX + CGFloat((tick - xMin) / xSpan) * plotRect.width
            ctx.move(to: CGPoint(x: cx, y: plotRect.minY))
            ctx.addLine(to: CGPoint(x: cx, y: plotRect.minY + tickLen))
            ctx.strokePath()
            let label = formatTick(tick, step: xStep)
            let labelY = plotRect.minY - labelGap - 6
            drawCentered(ctx, text: label,
                         at: CGPoint(x: cx, y: labelY),
                         size: labelSize, bold: false, color: labelColor)
        }

        // Y-axis ticks (left, inward)
        for tick in yTicks {
            let cy = plotRect.minY + CGFloat((tick - yMin) / ySpan) * plotRect.height
            ctx.move(to: CGPoint(x: plotRect.minX, y: cy))
            ctx.addLine(to: CGPoint(x: plotRect.minX + tickLen, y: cy))
            ctx.strokePath()
            let label = formatTick(tick, step: yStep)
            let labelX = plotRect.minX - labelGap
            drawRightAligned(ctx, text: label,
                             rightEdge: CGPoint(x: labelX, y: cy),
                             size: labelSize, bold: false, color: labelColor)
        }
    }

    // MARK: - Grid (tick-aligned)

    private func drawGrid(
        _ ctx: CGContext, plotRect: CGRect,
        xTicks: [Double], yTicks: [Double],
        xMin: Double, xSpan: Double, yMin: Double, ySpan: Double
    ) {
        ctx.setStrokeColor(CGColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1))
        ctx.setLineWidth(0.5)
        ctx.setLineDash(phase: 0, lengths: [3, 3])
        for tick in yTicks {
            let y = plotRect.minY + CGFloat((tick - yMin) / ySpan) * plotRect.height
            ctx.move(to: CGPoint(x: plotRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: plotRect.maxX, y: y))
        }
        for tick in xTicks {
            let x = plotRect.minX + CGFloat((tick - xMin) / xSpan) * plotRect.width
            ctx.move(to: CGPoint(x: x, y: plotRect.minY))
            ctx.addLine(to: CGPoint(x: x, y: plotRect.maxY))
        }
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
    }

    // MARK: - Legend

    /// anchor: "top-right" (default), "top-left", "bottom-right", "bottom-left"
    /// normalizedPoint: when set, overrides anchor; (0,0)=bottom-left, (1,1)=top-right of plotRect.
    private func drawLegend(_ ctx: CGContext, series: [WorkbenchPlotSeries],
                             plotRect: CGRect, anchor: String = "top-right",
                             normalizedPoint: CGPoint? = nil) {
        let lineLen: CGFloat = 18
        let rowH: CGFloat = 15
        let gap: CGFloat = 4
        let margin: CGFloat = 6
        let labelColor = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)

        for (i, s) in series.enumerated() {
            let color = Self.seriesColors[i % Self.seriesColors.count]
            ctx.setStrokeColor(color)
            ctx.setLineWidth(1.5)

            if let np = normalizedPoint {
                // Free-position mode: (cx,cy) normalized in plotRect; cy=1=top, cy=0=bottom.
                // CG Y increases upward: originY = minY + cy*height places block correctly.
                // Rows grow downward in screen space = decreasing CG y.
                let cx = min(max(np.x, 0), 1)
                let cy = min(max(np.y, 0), 1)
                let originX = plotRect.minX + cx * plotRect.width
                let originY = plotRect.minY + cy * plotRect.height
                let y = originY - CGFloat(i) * rowH - rowH * 0.4
                ctx.strokeLineSegments(between: [
                    CGPoint(x: originX, y: y),
                    CGPoint(x: originX + lineLen, y: y)
                ])
                drawLeftAligned(ctx, text: s.label,
                                leftEdge: CGPoint(x: originX + lineLen + gap, y: y),
                                size: 9, bold: false, color: labelColor)
            } else {
                // Anchor mode (existing behavior)
                let isLeft   = anchor == "top-left"  || anchor == "bottom-left"
                let isBottom = anchor == "bottom-right" || anchor == "bottom-left"
                let rowIndex = CGFloat(i + 1)
                let y: CGFloat
                if isBottom {
                    y = plotRect.minY + rowIndex * rowH - rowH * 0.6
                } else {
                    y = plotRect.maxY - rowIndex * rowH + rowH * 0.4
                }
                if isLeft {
                    let leftX = plotRect.minX + margin
                    ctx.strokeLineSegments(between: [
                        CGPoint(x: leftX, y: y),
                        CGPoint(x: leftX + lineLen, y: y)
                    ])
                    drawLeftAligned(ctx, text: s.label,
                                    leftEdge: CGPoint(x: leftX + lineLen + gap, y: y),
                                    size: 9, bold: false, color: labelColor)
                } else {
                    let rightX = plotRect.maxX - margin
                    ctx.strokeLineSegments(between: [
                        CGPoint(x: rightX - lineLen, y: y),
                        CGPoint(x: rightX, y: y)
                    ])
                    drawRightAligned(ctx, text: s.label,
                                     rightEdge: CGPoint(x: rightX - lineLen - gap, y: y),
                                     size: 9, bold: false, color: labelColor)
                }
            }
        }
    }

    // MARK: - CoreText text drawing (no AppKit)

    private func drawCentered(_ ctx: CGContext, text: String, at center: CGPoint,
                               size: CGFloat, bold: Bool, color: CGColor) {
        let line = makeLine(text: text, size: size, bold: bold, color: color)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(
            x: center.x - bounds.width / 2 - bounds.minX,
            y: center.y - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, ctx)
    }

    private func drawLeftAligned(_ ctx: CGContext, text: String, leftEdge: CGPoint,
                                  size: CGFloat, bold: Bool, color: CGColor) {
        let line = makeLine(text: text, size: size, bold: bold, color: color)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(
            x: leftEdge.x - bounds.minX,
            y: leftEdge.y - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, ctx)
    }

    private func drawRightAligned(_ ctx: CGContext, text: String, rightEdge: CGPoint,
                                   size: CGFloat, bold: Bool, color: CGColor) {
        let line = makeLine(text: text, size: size, bold: bold, color: color)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(
            x: rightEdge.x - bounds.width - bounds.minX,
            y: rightEdge.y - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, ctx)
    }

    private func drawRotated90(_ ctx: CGContext, text: String, at center: CGPoint,
                                size: CGFloat, color: CGColor) {
        let line = makeLine(text: text, size: size, bold: false, color: color)
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

    /// Renders text where `_X` notation draws X as a subscript (smaller font + lowered baseline).
    /// Falls back to plain rendering when no `_` is present.
    private func makeMarkupLine(text: String, size: CGFloat, color: CGColor) -> CTLine {
        guard text.contains("_") else { return makeLine(text: text, size: size, bold: false, color: color) }
        let font    = CTFontCreateWithName("ArialMT" as CFString, size, nil)
        let subFont = CTFontCreateWithName("ArialMT" as CFString, size * 0.65, nil)
        let baseAttrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font,
            NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): color,
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(rawValue: kCTFontAttributeName as String): subFont,
            NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): color,
            .baselineOffset: NSNumber(value: -size * 0.20),
        ]
        let result = NSMutableAttributedString()
        var scalars = text.unicodeScalars.makeIterator()
        while let scalar = scalars.next() {
            if scalar == "_", let next = scalars.next() {
                result.append(NSAttributedString(string: String(next), attributes: subAttrs))
            } else {
                result.append(NSAttributedString(string: String(scalar), attributes: baseAttrs))
            }
        }
        return CTLineCreateWithAttributedString(result)
    }

    private func drawCenteredMarkup(_ ctx: CGContext, text: String, at center: CGPoint,
                                    size: CGFloat, color: CGColor) {
        let line = makeMarkupLine(text: text, size: size, color: color)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(
            x: center.x - bounds.width / 2 - bounds.minX,
            y: center.y - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, ctx)
    }

    private func drawRotated90Markup(_ ctx: CGContext, text: String, at center: CGPoint,
                                     size: CGFloat, color: CGColor) {
        let line = makeMarkupLine(text: text, size: size, color: color)
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

    private func makeLine(text: String, size: CGFloat, bold: Bool, color: CGColor) -> CTLine {
        let fontName: CFString = bold ? "Arial-BoldMT" as CFString : "ArialMT" as CFString
        let font = CTFontCreateWithName(fontName, size, nil)
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
