import Foundation
import CoreGraphics
import CoreText
import ImageIO

/// Pure CoreGraphics heatmap renderer (Plot System-owned).
/// No SwiftUI or AppKit. Parallel to WorkbenchChartRenderer; must not extend it.
struct HeatmapRenderer {

    enum RendererError: Error, LocalizedError {
        case invalidGrid
        case contextCreationFailed
        case imageCreationFailed
        case destinationCreationFailed
        case finalizeFailed

        var errorDescription: String? {
            switch self {
            case .invalidGrid:              return "HeatmapGrid dimensions are inconsistent."
            case .contextCreationFailed:    return "Failed to create CGContext."
            case .imageCreationFailed:      return "Failed to create CGImage."
            case .destinationCreationFailed: return "Failed to create image destination."
            case .finalizeFailed:           return "Failed to finalize PNG."
            }
        }
    }

    // MARK: - Public

    func renderPNG(
        payload: HeatmapPlotPayload,
        colorScaleMode: PlotScaleTransform = .linear,
        options: HeatmapPlotLayout.Options = .init(),
        showColorbar: Bool = true,
        showTitle: Bool = true,
        chartStyle: WorkbenchChartStyle = .init(),
        colorbarTickStyle: HeatmapColorbarTickStyle = .standard
    ) throws -> Data {
        guard payload.grid.isValid else { throw RendererError.invalidGrid }

        let layout = HeatmapPlotLayout.compute(
            payload: payload,
            options: options,
            colorScaleMode: colorScaleMode,
            chartStyle: chartStyle,
            showColorbar: showColorbar,
            showTitle: showTitle,
            colorbarTickStyle: colorbarTickStyle
        )
        let colorScale = HeatmapColorScale(
            zMin:       layout.zMin,
            zMax:       layout.zMax,
            mode:       colorScaleMode,
            colormapKey: payload.colormapKey ?? "viridis"
        )

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let scale = max(options.pixelScale, 1)
        let pixelW = Int((layout.rendererSize.width * scale).rounded())
        let pixelH = Int((layout.rendererSize.height * scale).rounded())

        guard let ctx = CGContext(
            data: nil, width: pixelW, height: pixelH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ) else { throw RendererError.contextCreationFailed }

        ctx.scaleBy(x: scale, y: scale)
        drawCanvas(ctx: ctx, payload: payload, layout: layout, colorScale: colorScale, chartStyle: chartStyle, colorbarTickStyle: colorbarTickStyle)

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
    /// Every grid cell, axis tick, and colorbar strip is drawn as a real CGContext fill/stroke
    /// path — there is no raster image embedded anywhere in `drawCanvas`, so this is true
    /// vector output, not a raster heatmap wrapped in a PDF container. Large grids produce a
    /// correspondingly large number of path objects (one filled rect per cell); this is a file
    /// size tradeoff, not a fidelity compromise.
    func renderPDF(
        payload: HeatmapPlotPayload,
        colorScaleMode: PlotScaleTransform = .linear,
        options: HeatmapPlotLayout.Options = .init(),
        showColorbar: Bool = true,
        showTitle: Bool = true,
        chartStyle: WorkbenchChartStyle = .init(),
        colorbarTickStyle: HeatmapColorbarTickStyle = .standard
    ) throws -> Data {
        guard payload.grid.isValid else { throw RendererError.invalidGrid }

        let layout = HeatmapPlotLayout.compute(
            payload: payload,
            options: options,
            colorScaleMode: colorScaleMode,
            chartStyle: chartStyle,
            showColorbar: showColorbar,
            showTitle: showTitle,
            colorbarTickStyle: colorbarTickStyle
        )
        let colorScale = HeatmapColorScale(
            zMin:       layout.zMin,
            zMax:       layout.zMax,
            mode:       colorScaleMode,
            colormapKey: payload.colormapKey ?? "viridis"
        )

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            throw RendererError.destinationCreationFailed
        }
        var mediaBox = CGRect(origin: .zero, size: layout.rendererSize)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw RendererError.contextCreationFailed
        }
        ctx.beginPDFPage(nil)
        drawCanvas(ctx: ctx, payload: payload, layout: layout, colorScale: colorScale, chartStyle: chartStyle, colorbarTickStyle: colorbarTickStyle)
        ctx.endPDFPage()
        ctx.closePDF()
        return pdfData as Data
    }

    // MARK: - Canvas drawing

    private func drawCanvas(
        ctx: CGContext,
        payload: HeatmapPlotPayload,
        layout: HeatmapPlotLayout,
        colorScale: HeatmapColorScale,
        chartStyle: WorkbenchChartStyle,
        colorbarTickStyle: HeatmapColorbarTickStyle
    ) {
        let w = layout.rendererSize.width
        let h = layout.rendererSize.height
        let black    = CGColor(red: 0,   green: 0,   blue: 0,   alpha: 1)
        let darkGray = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)

        // White background
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Title — rendered only when showTitle is true. payload.title metadata is
        // never cleared; only the visual draw is gated.
        if layout.showTitle, !payload.title.isEmpty {
            drawCentered(ctx, text: payload.title, at: layout.titleCenter,
                         size: chartStyle.titleFontSize, bold: chartStyle.titleBold, color: black,
                         chartStyle: chartStyle)
        }

        // Heatmap grid cells
        drawGrid(ctx: ctx, payload: payload, layout: layout, colorScale: colorScale)

        // Grid border
        ctx.setStrokeColor(darkGray)
        ctx.setLineWidth(1.2)
        ctx.stroke(layout.gridRect)

        // Axis ticks and labels (suppressed when hideSpatialAxes is true)
        if !layout.hideSpatialAxes {
            drawXAxis(ctx: ctx, payload: payload, layout: layout, chartStyle: chartStyle)
            drawYAxis(ctx: ctx, payload: payload, layout: layout, chartStyle: chartStyle)

            // Axis name labels
            drawCentered(ctx, text: payload.xLabel,
                         at: layout.xLabelCenter, size: chartStyle.axisTitleFontSize, bold: false, color: black,
                         chartStyle: chartStyle)
            drawRotated90(ctx, text: payload.yLabel,
                          at: layout.yLabelCenter, size: chartStyle.axisTitleFontSize, color: black,
                          chartStyle: chartStyle)
        }

        // Scale bar overlay (drawn inside lower-left of grid if configured)
        if let scaleBar = layout.scaleBarOverlay {
            drawScaleBar(ctx: ctx, overlay: scaleBar, gridRect: layout.gridRect, chartStyle: chartStyle)
        }

        // Colorbar block — rendered only when showColorbar is true
        if layout.showColorbar {
            drawColorbar(ctx: ctx, layout: layout, colorScale: colorScale, chartStyle: chartStyle, colorbarTickStyle: colorbarTickStyle)

            if !payload.zLabel.isEmpty {
                let zLabel = Self.renderedZLabel(payload.zLabel, mode: colorScale.mode)
                drawRotated90(ctx, text: zLabel,
                              at: layout.colorbarLabelCenter, size: chartStyle.axisTitleFontSize, color: black,
                              chartStyle: chartStyle)
            }
        }
    }

    // MARK: - Scale bar overlay

    private func drawScaleBar(
        ctx: CGContext,
        overlay: HeatmapScaleBarOverlay,
        gridRect: CGRect,
        chartStyle: WorkbenchChartStyle
    ) {
        let x0 = gridRect.minX + 0.045 * gridRect.width
        let yBar = gridRect.minY + 0.042 * gridRect.height
        let barLen = overlay.lengthInPoints
        let barThickness: CGFloat = 5.0
        let outline: CGFloat = 1.5

        let isBlack = overlay.color == .black
        let fill = CGColor(red: isBlack ? 0 : 1, green: isBlack ? 0 : 1, blue: isBlack ? 0 : 1, alpha: 1)
        let contrast = CGColor(red: isBlack ? 1 : 0, green: isBlack ? 1 : 0, blue: isBlack ? 1 : 0, alpha: 0.85)

        ctx.saveGState()
        ctx.setLineCap(.butt)

        // Contrast outline under the bar, then the solid bar.
        ctx.setStrokeColor(contrast)
        ctx.setLineWidth(barThickness + 2 * outline)
        ctx.move(to: CGPoint(x: x0 - outline, y: yBar))
        ctx.addLine(to: CGPoint(x: x0 + barLen + outline, y: yBar))
        ctx.strokePath()
        ctx.setStrokeColor(fill)
        ctx.setLineWidth(barThickness)
        ctx.move(to: CGPoint(x: x0, y: yBar))
        ctx.addLine(to: CGPoint(x: x0 + barLen, y: yBar))
        ctx.strokePath()

        // Label centred immediately above the bar.
        let size: CGFloat = 54
        let textCenter = CGPoint(x: x0 + barLen / 2, y: yBar + barThickness / 2 + outline + 6 + size * 0.38)
        drawScaleBarLabel(ctx, text: overlay.label, at: textCenter, size: size, fill: fill, contrast: contrast)

        ctx.restoreGState()
    }

    private func drawScaleBarLabel(_ ctx: CGContext, text: String, at center: CGPoint, size: CGFloat, fill: CGColor, contrast: CGColor) {
        // Preferred font: Times New Roman Bold Italic (or system serif bold italic fallback)
        let fontCandidates = [
            "TimesNewRomanPS-BoldItalicMT",
            "TimesNewRoman-BoldItalic",
            "Georgia-BoldItalic",
            "HelveticaNeue-BoldItalic"
        ]
        var resolvedFont: CTFont?
        for candidate in fontCandidates {
            let font = CTFontCreateWithName(candidate as CFString, size, nil)
            let postscriptName = (CTFontCopyPostScriptName(font) as String)
            if postscriptName.localizedCaseInsensitiveContains("italic") ||
               postscriptName.localizedCaseInsensitiveContains("oblique") {
                resolvedFont = font
                break
            }
        }
        let font = resolvedFont ?? CTFontCreateWithName("TimesNewRomanPS-BoldItalicMT" as CFString, size, nil)

        // Pass 1: contrast outline (stroke only; positive stroke width = % of font size).
        let strokeAttrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: contrast,
            kCTStrokeWidthAttributeName: 7.0 as CFNumber,
            kCTStrokeColorAttributeName: contrast
        ]
        let strokeStr = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, strokeAttrs as CFDictionary)!
        let strokeLine = CTLineCreateWithAttributedString(strokeStr)
        let bounds = CTLineGetBoundsWithOptions(strokeLine, [])

        let origin = CGPoint(
            x: center.x - bounds.width / 2 - bounds.minX,
            y: center.y - bounds.height / 2 - bounds.minY
        )

        ctx.saveGState()
        ctx.textPosition = origin
        CTLineDraw(strokeLine, ctx)

        // Pass 2: solid fill text.
        let fillAttrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: fill
        ]
        let fillStr = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, fillAttrs as CFDictionary)!
        let fillLine = CTLineCreateWithAttributedString(fillStr)

        ctx.textPosition = origin
        CTLineDraw(fillLine, ctx)
        ctx.restoreGState()
    }

    // MARK: - Grid cells

    private func drawGrid(
        ctx: CGContext,
        payload: HeatmapPlotPayload,
        layout: HeatmapPlotLayout,
        colorScale: HeatmapColorScale
    ) {
        let grid = payload.grid
        let nX = grid.nX, nY = grid.nY
        guard nX > 0, nY > 0 else { return }

        let rect  = layout.gridRect
        let cellW = rect.width  / CGFloat(nX)
        let cellH = rect.height / CGFloat(nY)

        ctx.saveGState()
        ctx.clip(to: rect)
        for row in 0..<nY {
            let cy = rect.minY + CGFloat(row) * cellH
            for col in 0..<nX {
                let cx = rect.minX + CGFloat(col) * cellW
                let z = grid.zMatrix[row][col]
                ctx.setFillColor(colorScale.color(for: z))
                // +0.5 overlap prevents hairline gaps between adjacent cells
                ctx.fill(CGRect(x: cx, y: cy, width: cellW + 0.5, height: cellH + 0.5))
            }
        }
        ctx.restoreGState()
    }

    // MARK: - Axes

    private func drawXAxis(
        ctx: CGContext,
        payload: HeatmapPlotPayload,
        layout: HeatmapPlotLayout,
        chartStyle: WorkbenchChartStyle
    ) {
        let grid = payload.grid
        let nX   = grid.nX
        guard nX > 0 else { return }

        let rect     = layout.gridRect
        let tickLen:  CGFloat = 5
        let labelGap: CGFloat = 3
        let tickColor  = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        let labelColor = CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)

        ctx.setStrokeColor(tickColor)
        ctx.setLineWidth(0.8)

        for entry in layout.xTickEntries {
            let cx = rect.minX + (CGFloat(entry.col) + 0.5) * (rect.width / CGFloat(nX))
            ctx.move(to:    CGPoint(x: cx, y: rect.minY))
            ctx.addLine(to: CGPoint(x: cx, y: rect.minY - tickLen))
            ctx.strokePath()
            drawCentered(ctx, text: entry.label,
                         at: CGPoint(x: cx, y: rect.minY - tickLen - labelGap - 8),
                         size: chartStyle.tickLabelFontSize, bold: false, color: labelColor,
                         chartStyle: chartStyle)
        }
    }

    private func drawYAxis(
        ctx: CGContext,
        payload: HeatmapPlotPayload,
        layout: HeatmapPlotLayout,
        chartStyle: WorkbenchChartStyle
    ) {
        let grid = payload.grid
        let nY   = grid.nY
        guard nY > 0 else { return }

        let rect     = layout.gridRect
        let tickLen:  CGFloat = 5
        let labelGap: CGFloat = 4
        let tickColor  = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        let labelColor = CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)

        ctx.setStrokeColor(tickColor)
        ctx.setLineWidth(0.8)

        for entry in layout.yTickEntries {
            let cy = layout.gridRect.minY + (CGFloat(entry.row) + 0.5) * (rect.height / CGFloat(nY))
            ctx.move(to:    CGPoint(x: rect.minX, y: cy))
            ctx.addLine(to: CGPoint(x: rect.minX - tickLen, y: cy))
            ctx.strokePath()
            drawRightAligned(ctx, text: entry.label,
                             rightEdge: CGPoint(x: rect.minX - tickLen - labelGap, y: cy),
                             size: chartStyle.tickLabelFontSize, bold: false, color: labelColor,
                             fontName: chartStyle.fontName, boldFontName: chartStyle.boldFontName)
        }
    }

    // MARK: - Colorbar

    private func drawColorbar(
        ctx: CGContext,
        layout: HeatmapPlotLayout,
        colorScale: HeatmapColorScale,
        chartStyle: WorkbenchChartStyle,
        colorbarTickStyle: HeatmapColorbarTickStyle
    ) {
        let cbRect = layout.colorbarRect
        guard cbRect.height > 0, cbRect.width > 0 else { return }

        // Vertical gradient as 256 thin horizontal strips.
        // Use normalized t directly so the gradient matches log-scale tick positions.
        let nStrips = 256
        let stripH  = cbRect.height / CGFloat(nStrips)
        for i in 0..<nStrips {
            let t = Double(i) / Double(nStrips - 1)
            ctx.setFillColor(colorScale.color(forNormalized: t))
            let y = cbRect.minY + CGFloat(i) * stripH
            ctx.fill(CGRect(x: cbRect.minX, y: y, width: cbRect.width, height: stripH + 0.5))
        }

        // Border
        let darkGray = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        ctx.setStrokeColor(darkGray)
        ctx.setLineWidth(0.8)
        ctx.stroke(cbRect)

        // Tick marks and numeric labels
        let labelColor = CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        let tickLen: CGFloat = 4
        let isEndpoints: Bool
        if case .endpointsOnly = colorbarTickStyle {
            isEndpoints = true
        } else {
            isEndpoints = false
        }
        let fontSize: CGFloat = isEndpoints ? 29.0 : chartStyle.tickLabelFontSize

        for (y, label) in layout.colorbarTicks {
            ctx.setStrokeColor(darkGray)
            ctx.move(to:    CGPoint(x: cbRect.maxX, y: y))
            ctx.addLine(to: CGPoint(x: cbRect.maxX + tickLen, y: y))
            ctx.strokePath()
            drawLeftAligned(ctx, text: label,
                            leftEdge: CGPoint(x: cbRect.maxX + tickLen + 3, y: y),
                            size: fontSize, bold: false, color: labelColor,
                            fontName: chartStyle.fontName, boldFontName: chartStyle.boldFontName)
        }
    }

    // MARK: - CoreText text drawing (no AppKit)

    private func makeLine(
        text: String,
        size: CGFloat,
        bold: Bool,
        color: CGColor,
        fontName: String,
        boldFontName: String
    ) -> CTLine {
        let resolvedFontName = bold ? boldFontName : fontName
        let font = CTFontCreateWithName(resolvedFontName as CFString, size, nil)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName:            font,
            kCTForegroundColorAttributeName: color,
        ]
        let attrStr = CFAttributedStringCreate(
            kCFAllocatorDefault, text as CFString, attrs as CFDictionary
        )!
        return CTLineCreateWithAttributedString(attrStr)
    }

    private func drawCentered(_ ctx: CGContext, text: String, at center: CGPoint,
                               size: CGFloat, bold: Bool, color: CGColor,
                               chartStyle: WorkbenchChartStyle) {
        let line: CTLine
        if MathMarkupRenderer.isMathLabel(text) {
            line = MathMarkupRenderer.makeLine(
                text: MathMarkupRenderer.extractMathMarkup(text),
                size: size,
                color: color,
                style: chartStyle
            )
        } else {
            line = makeLine(
                text: text,
                size: size,
                bold: bold,
                color: color,
                fontName: chartStyle.fontName,
                boldFontName: chartStyle.boldFontName
            )
        }
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(
            x: center.x - bounds.width / 2 - bounds.minX,
            y: center.y - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, ctx)
    }

    private func drawLeftAligned(_ ctx: CGContext, text: String, leftEdge: CGPoint,
                                  size: CGFloat, bold: Bool, color: CGColor,
                                  fontName: String, boldFontName: String) {
        let line   = makeLine(text: text, size: size, bold: bold, color: color, fontName: fontName, boldFontName: boldFontName)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(
            x: leftEdge.x - bounds.minX,
            y: leftEdge.y - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, ctx)
    }

    private func drawRightAligned(_ ctx: CGContext, text: String, rightEdge: CGPoint,
                                   size: CGFloat, bold: Bool, color: CGColor,
                                   fontName: String, boldFontName: String) {
        let line   = makeLine(text: text, size: size, bold: bold, color: color, fontName: fontName, boldFontName: boldFontName)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(
            x: rightEdge.x - bounds.width - bounds.minX,
            y: rightEdge.y - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, ctx)
    }

    private func drawRotated90(_ ctx: CGContext, text: String, at center: CGPoint,
                                size: CGFloat, color: CGColor,
                                chartStyle: WorkbenchChartStyle) {
        let line: CTLine
        if MathMarkupRenderer.isMathLabel(text) {
            line = MathMarkupRenderer.makeLine(
                text: MathMarkupRenderer.extractMathMarkup(text),
                size: size,
                color: color,
                style: chartStyle
            )
        } else {
            line = makeLine(
                text: text,
                size: size,
                bold: false,
                color: color,
                fontName: chartStyle.fontName,
                boldFontName: chartStyle.boldFontName
            )
        }
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

    // MARK: - Z-axis label mode formatting

    /// Returns the colorbar label exactly as provided. Color Scale mode controls tick
    /// positioning only, not the title text.
    static func renderedZLabel(_ label: String, mode: PlotScaleTransform) -> String {
        label
    }

}
