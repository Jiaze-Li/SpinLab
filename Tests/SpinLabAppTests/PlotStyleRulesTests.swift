import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
@testable import SpinLabApp

/// Behavior tests for `specs/05_PLOT_RULES.md`: Arial-only, pure black/white text, no stroke/shadow,
/// identical in PNG and PDF, across Cartesian XY, DualAxis and Heatmap (AFM/RSM).
@Suite("Plot style rules (05_PLOT_RULES)")
struct PlotStyleRulesTests {

    // MARK: - Fixtures

    /// A style as an old Pack / user setting could have produced it.
    private static let legacyStyleParams: [String: String] = [
        "plotFontName": "TimesNewRomanPSMT",
        "plotBoldFontName": "TimesNewRomanPS-BoldMT",
        "titleBold": "true",
        "titleFontSize": "30",
        "axisTitleFontSize": "22",
        "tickLabelFontSize": "17",
        "legendFontSize": "16",
        "pointLabelFontSize": "15",
        "transparentBackground": "true",
    ]

    private static let mathLabel = "math:ρ_{xy}^{3ω} (μΩ·cm) σ Δ θ"

    private static func legacyStyle() -> WorkbenchChartStyle {
        WorkbenchChartStyle.from(styleParams: legacyStyleParams)
    }

    // MARK: - Bitmap helpers

    struct Bitmap {
        let width: Int, height: Int
        var rgba: [UInt8]   // premultiplied
        func pixel(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
            let i = (y * width + x) * 4
            let a = Double(rgba[i + 3]) / 255
            guard a > 0 else { return (0, 0, 0, 0) }
            return (Double(rgba[i]) / 255 / a, Double(rgba[i + 1]) / 255 / a, Double(rgba[i + 2]) / 255 / a, a)
        }
    }

    private static func bitmap(from image: CGImage) -> Bitmap {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { buf in
            let ctx = CGContext(
                data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return Bitmap(width: w, height: h, rgba: data)
    }

    private static func decodePNG(_ data: Data) throws -> Bitmap {
        let src = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let img = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        return bitmap(from: img)
    }

    /// Rasterizes page 1 of a PDF at 1 pt = `scale` px on a transparent canvas.
    private static func rasterizePDF(_ data: Data, size: CGSize, scale: CGFloat = 1) throws -> Bitmap {
        let provider = try #require(CGDataProvider(data: data as CFData))
        let doc = try #require(CGPDFDocument(provider))
        let page = try #require(doc.page(at: 1))
        let w = Int(size.width * scale), h = Int(size.height * scale)
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.scaleBy(x: scale, y: scale)
            ctx.drawPDFPage(page)
        }
        return Bitmap(width: w, height: h, rgba: buf)
    }

    /// Zones (CG point space, y-up) where figure *text* lives: everything beyond `margin` pt of the
    /// framed areas (plot box / heatmap grid / colorbar). Tick marks, axis lines, curves, markers and
    /// the colormap gradient sit inside the margin and are therefore not inspected.
    private static func textZones(canvas: CGSize, frame: CGRect, rightFrame: CGRect? = nil, margin: CGFloat = 10) -> [CGRect] {
        let r = rightFrame ?? frame
        let top = max(frame.maxY, r.maxY), bottom = min(frame.minY, r.minY)
        return [
            CGRect(x: 0, y: 0, width: frame.minX - margin, height: canvas.height),
            CGRect(x: r.maxX + margin, y: 0, width: canvas.width - r.maxX - margin, height: canvas.height),
            CGRect(x: 0, y: 0, width: canvas.width, height: bottom - margin),
            CGRect(x: 0, y: top + 2, width: canvas.width, height: canvas.height - top - 2),
        ].filter { $0.width > 0 && $0.height > 0 }
    }

    private static func forEachPixel(_ bm: Bitmap, scale: CGFloat, in zones: [CGRect],
                                     _ body: (Int, Int, (r: Double, g: Double, b: Double, a: Double)) -> Void) {
        for py in 0..<bm.height {
            let cgY = (CGFloat(bm.height - 1 - py) + 0.5) / scale
            for px in 0..<bm.width {
                let pt = CGPoint(x: (CGFloat(px) + 0.5) / scale, y: cgY)
                guard zones.contains(where: { $0.contains(pt) }) else { continue }
                let p = bm.pixel(px, py)
                if p.a > 0.04 { body(px, py, p) }
            }
        }
    }

    /// Visible text pixels in `zones` that are not black (after un-premultiplying alpha).
    private static func nonBlackPixels(_ bm: Bitmap, scale: CGFloat, in zones: [CGRect]) -> (count: Int, sample: String) {
        var count = 0
        var sample = ""
        forEachPixel(bm, scale: scale, in: zones) { px, py, p in
            if max(p.r, p.g, p.b) > 0.04 {
                count += 1
                if sample.isEmpty { sample = "(\(px),\(py)) rgb=\(p.r),\(p.g),\(p.b) a=\(p.a)" }
            }
        }
        return (count, sample)
    }

    /// Solid ink present in `zones` — guards against a vacuous "no text" pass.
    private static func inkPixels(_ bm: Bitmap, scale: CGFloat, in zones: [CGRect]) -> Int {
        var n = 0
        forEachPixel(bm, scale: scale, in: zones) { _, _, p in if p.a > 0.5 { n += 1 } }
        return n
    }

    // MARK: - CTLine inspection

    private struct LineInfo { var families: Set<String>; var fontNames: Set<String>; var colors: [[CGFloat]]; var hasStrokeOrShadow: Bool }

    private static func inspect(_ line: CTLine) -> LineInfo {
        var info = LineInfo(families: [], fontNames: [], colors: [], hasStrokeOrShadow: false)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        for run in runs {
            let attrs = CTRunGetAttributes(run) as! [CFString: Any]
            let font = attrs[kCTFontAttributeName] as! CTFont
            info.families.insert(CTFontCopyFamilyName(font) as String)
            info.fontNames.insert(CTFontCopyPostScriptName(font) as String)
            if let c = attrs[kCTForegroundColorAttributeName] {
                let cg = c as! CGColor
                info.colors.append(cg.components ?? [])
            }
            if attrs[kCTStrokeWidthAttributeName] != nil || attrs[kCTStrokeColorAttributeName] != nil
                || attrs.keys.contains(where: { ($0 as String).lowercased().contains("shadow") }) {
                info.hasStrokeOrShadow = true
            }
        }
        return info
    }

    private static func isPureBlack(_ c: [CGFloat]) -> Bool {
        c.count >= 3 && c[0] == 0 && c[1] == 0 && c[2] == 0 && (c.count < 4 || c[3] == 1)
    }
    private static func isPureWhite(_ c: [CGFloat]) -> Bool {
        c.count >= 3 && c[0] == 1 && c[1] == 1 && c[2] == 1 && (c.count < 4 || c[3] == 1)
    }

    // MARK: - Font + color policy (unit level)

    @Test("Arial is installed on the host (precondition for font assertions)")
    func arialInstalled() {
        #expect(PlotTextPolicy.isArialInstalled)
    }

    @Test("Defaults and legacy font names all resolve to Arial; Arial Regular/Bold/Italic coexist")
    func fontResolution() {
        #expect(WorkbenchChartStyle().fontName == "ArialMT")
        #expect(WorkbenchChartStyle().boldFontName == "Arial-BoldMT")
        for legacy in ["TimesNewRomanPSMT", "Helvetica", "Menlo-Regular", "NoSuchFont", "", ".SFNS-Regular"] {
            let f = PlotTextPolicy.font(name: legacy, size: 14)
            #expect(CTFontCopyFamilyName(f) as String == "Arial", "legacy \(legacy)")
            let b = PlotTextPolicy.font(name: legacy, size: 14, bold: true)
            #expect(CTFontCopyPostScriptName(b) as String == "Arial-BoldMT", "legacy bold \(legacy)")
        }
        #expect(PlotTextPolicy.resolvedFontName("ArialMT", bold: true) == "Arial-BoldMT")
        for ok in ["ArialMT", "Arial-BoldMT", "Arial-ItalicMT", "Arial-BoldItalicMT"] {
            #expect(CTFontCopyPostScriptName(PlotTextPolicy.font(name: ok, size: 12)) as String == ok)
        }
    }

    @Test("Style parsing, direct assignment and Codable decode of legacy fonts never produce non-Arial text")
    func legacyStyleCompatibility() throws {
        let parsed = Self.legacyStyle()
        #expect(parsed.fontName == "ArialMT" && parsed.boldFontName == "Arial-BoldMT")
        // User font sizes are preserved verbatim.
        #expect(parsed.titleFontSize == 30 && parsed.axisTitleFontSize == 22 && parsed.tickLabelFontSize == 17)
        #expect(parsed.legendFontSize == 16 && parsed.pointLabelFontSize == 15 && parsed.titleBold)

        // An old encoded style that still carries Times New Roman.
        var old = WorkbenchChartStyle()
        old.fontName = "TimesNewRomanPSMT"
        old.boldFontName = "TimesNewRomanPS-BoldMT"
        let decoded = try JSONDecoder().decode(WorkbenchChartStyle.self, from: JSONEncoder().encode(old))
        #expect(decoded.fontName == "TimesNewRomanPSMT")   // stored value preserved for compatibility…
        for style in [old, decoded] {
            for bold in [false, true] {
                let info = Self.inspect(style.makeTextLine("Résistance 12.5", size: 20, bold: bold, color: PlotTextPolicy.black))
                #expect(info.families == ["Arial"])           // …but the rendered face is Arial.
            }
            #expect(CTFontCopyFamilyName(style.ctFont(size: 10)) as String == "Arial")
        }
    }

    @Test("Text colors are snapped to opaque pure black or pure white")
    func textColorSnapping() {
        let gray = CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        let darkGray = CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        let curve = CGColor(srgbRed: 0.12, green: 0.47, blue: 0.71, alpha: 1)
        let translucentBlack = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5)
        let translucentWhite = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.5)
        let deviceGray = CGColor(gray: 0.3, alpha: 1)
        for c in [gray, darkGray, curve, translucentBlack, translucentWhite, deviceGray, PlotTextPolicy.black] {
            #expect(Self.isPureBlack(PlotTextPolicy.resolvedTextColor(c).components ?? []))
        }
        #expect(Self.isPureWhite(PlotTextPolicy.resolvedTextColor(PlotTextPolicy.white).components ?? []))
        #expect(Self.isPureWhite(PlotTextPolicy.resolvedTextColor(CGColor(gray: 1, alpha: 1)).components ?? []))

        let style = WorkbenchChartStyle()
        for (requested, expectWhite) in [(gray, false), (curve, false), (translucentWhite, false), (PlotTextPolicy.white, true)] {
            let info = Self.inspect(style.makeTextLine("tick", size: 12, color: requested))
            #expect(!info.colors.isEmpty)
            #expect(info.colors.allSatisfy { expectWhite ? Self.isPureWhite($0) : Self.isPureBlack($0) })
            #expect(!info.hasStrokeOrShadow)
        }
    }

    @Test("Math markup: sub/superscripts and Greek letters stay Arial, black/white, without font fallback")
    func mathMarkupIsArial() {
        let style = Self.legacyStyle()
        let gray = CGColor(srgbRed: 0.4, green: 0.4, blue: 0.4, alpha: 1)
        for text in [
            "ρ_{xy}^{3ω} (μΩ·cm)", "σ_{xx} Δθ", "R_{3ω}", "α^2 + β_i", "plain _x", "B^{−1} (T^{−1})",
        ] {
            let info = Self.inspect(MathMarkupRenderer.makeLine(text: text, size: 22, color: gray, style: style))
            #expect(info.families == ["Arial"], "\(text) -> \(info.fontNames)")
            #expect(info.colors.allSatisfy(Self.isPureBlack), "\(text)")
            #expect(!info.hasStrokeOrShadow)
        }
        let white = Self.inspect(MathMarkupRenderer.makeLine(text: "σ_{xx}", size: 22, color: PlotTextPolicy.white, style: style))
        #expect(white.colors.allSatisfy(Self.isPureWhite))
    }

    @Test("Text measurement uses the same Arial metrics as drawing")
    func measurementMatchesArial() {
        let legacyWidth = PlotTextMeasurer.measuredWidth("Magnetic field 123", fontSize: 20, fontName: "TimesNewRomanPSMT")
        let arialWidth = PlotTextMeasurer.measuredWidth("Magnetic field 123", fontSize: 20, fontName: "ArialMT")
        #expect(legacyWidth == arialWidth && arialWidth > 0)
        let mathLegacy = MathMarkupRenderer.measuredWidth(text: "σ_{xx}", size: 20, fontName: "TimesNewRomanPSMT")
        let mathArial = MathMarkupRenderer.measuredWidth(text: "σ_{xx}", size: 20, fontName: "ArialMT")
        #expect(mathLegacy == mathArial)
    }

    // MARK: - Cartesian XY (rendered)

    private func xyPayload() -> WorkbenchPlotPayload {
        let xs = (0...12).map(Double.init)
        let s1 = WorkbenchPlotSeries(label: "Sample σ_{xx}", x: xs, y: xs.map { $0 * $0 / 10 },
                                      renderMode: .lineAndScatter,
                                      pointLabels: xs.map { "p\(Int($0))" })
        let s2 = WorkbenchPlotSeries(label: "Fit", x: xs, y: xs.map { 12 - $0 }, renderMode: .line)
        return WorkbenchPlotPayload(
            workflowID: "xy", workflowDisplayName: "XY", title: "Title ρ_{xy}",
            axisMapping: .init(xField: Self.mathLabel, yField: Self.mathLabel),
            series: [s1, s2], styleParams: Self.legacyStyleParams
        )
    }

    @Test("XY: PNG with legacy font settings has only black text outside the plot area")
    func xyPNGText() throws {
        let payload = xyPayload()
        let style = Self.legacyStyle()
        let opts = WorkbenchChartRenderer.Options()
        let layout = WorkbenchPlotLayout.compute(options: opts, payload: payload, legendPoint: nil, style: style)
        let png = try WorkbenchChartRenderer().renderPNG(payload: payload, options: opts, style: style, layout: layout)
        let bm = try Self.decodePNG(png)
        #expect(bm.pixel(2, 2).a == 0)   // transparent background kept
        let zones = Self.textZones(canvas: layout.rendererSize, frame: layout.plotRect)
        #expect(Self.inkPixels(bm, scale: opts.pixelScale, in: zones) > 500)
        let bad = Self.nonBlackPixels(bm, scale: opts.pixelScale, in: zones)
        #expect(bad.count == 0, "non-black text pixel \(bad.sample)")
    }

    @Test("XY: PDF raster matches the same text rules and embeds only Arial fonts")
    func xyPDFText() throws {
        let payload = xyPayload()
        let style = Self.legacyStyle()
        let opts = WorkbenchChartRenderer.Options()
        let layout = WorkbenchPlotLayout.compute(options: opts, payload: payload, legendPoint: nil, style: style)
        let pdf = try WorkbenchChartRenderer().renderPDF(payload: payload, options: opts, style: style, layout: layout)
        try Self.assertOnlyArialFonts(inPDF: pdf)
        let bm = try Self.rasterizePDF(pdf, size: CGSize(width: opts.width, height: opts.height))
        let zones = Self.textZones(canvas: layout.rendererSize, frame: layout.plotRect)
        #expect(Self.inkPixels(bm, scale: 1, in: zones) > 500)
        let bad = Self.nonBlackPixels(bm, scale: 1, in: zones)
        #expect(bad.count == 0, "non-black text pixel \(bad.sample)")
    }

    @Test("XY: opaque background still white, and default style also yields Arial text only")
    func xyOpaqueDefault() throws {
        var payload = xyPayload()
        payload.styleParams = [:]
        let opts = WorkbenchChartRenderer.Options()
        let png = try WorkbenchChartRenderer().renderPNG(payload: payload, options: opts, style: WorkbenchChartStyle())
        let bm = try Self.decodePNG(png)
        let corner = bm.pixel(2, 2)
        #expect(corner.a == 1 && corner.r == 1 && corner.g == 1 && corner.b == 1)
        let pdf = try WorkbenchChartRenderer().renderPDF(payload: payload, options: opts, style: WorkbenchChartStyle())
        try Self.assertOnlyArialFonts(inPDF: pdf)
    }

    // MARK: - DualAxis (rendered)

    private func dualPayload() -> DualAxisPlotPayload {
        let xs = (0...10).map(Double.init)
        return DualAxisPlotPayload(
            workflowID: "dual", workflowDisplayName: "Dual", title: "Dual ρ",
            xLabel: Self.mathLabel, leftYLabel: "math:R_{xx} (Ω)", rightYLabel: "math:T (K)",
            leftSeries: [DualAxisPlotSeries(label: "Left σ_{xx}", x: xs, y: xs.map { $0 * 2 })],
            rightSeries: [DualAxisPlotSeries(label: "Right", x: xs, y: xs.map { 300 - $0 * 5 })]
        )
    }

    @Test("DualAxis: axis-colored labels are black; PNG and PDF follow the text rules")
    func dualAxisText() throws {
        let payload = dualPayload()
        let style = Self.legacyStyle()
        let options = DualAxisPlotLayout.Options()
        let layout = DualAxisPlotLayout.compute(payload: payload, options: options, style: style)
        let renderer = DualAxisChartRenderer()
        let png = try renderer.renderPNG(payload: payload, options: options, style: style)
        let bm = try Self.decodePNG(png)
        #expect(bm.pixel(2, 2).a == 0)
        let zones = Self.textZones(canvas: layout.rendererSize, frame: layout.plotRect)
        #expect(Self.inkPixels(bm, scale: options.pixelScale, in: zones) > 500)
        let bad = Self.nonBlackPixels(bm, scale: options.pixelScale, in: zones)
        #expect(bad.count == 0, "non-black text pixel \(bad.sample)")

        let pdf = try renderer.renderPDF(
            payload: payload, validLeftSeries: payload.leftSeries, validRightSeries: payload.rightSeries,
            layout: layout, options: options, style: style
        )
        try Self.assertOnlyArialFonts(inPDF: pdf)
        let pbm = try Self.rasterizePDF(pdf, size: layout.rendererSize)
        let pbad = Self.nonBlackPixels(pbm, scale: 1, in: zones)
        #expect(pbad.count == 0, "PDF non-black text pixel \(pbad.sample)")
    }

    // MARK: - Heatmap / AFM (rendered)

    private func heatmapPayload(scaleBar: HeatmapScaleBarOverlay? = nil, uniform: Bool = false) -> HeatmapPlotPayload {
        let n = 24
        let xs = (0..<n).map { Double($0) * 0.1 }
        let z = (0..<n).map { r in (0..<n).map { c in uniform ? 0.5 : Double(r * n + c) / Double(n * n) } }
        return HeatmapPlotPayload(
            workflowID: "afm", title: "Height ρ_{xy}", xLabel: "math:x (μm)", yLabel: "math:y (μm)",
            zLabel: "math:Height (nm) σ", grid: HeatmapGrid(xValues: xs, yValues: xs, zMatrix: z),
            colormapKey: "viridis", scaleBarOverlay: scaleBar
        )
    }

    @Test("Heatmap: titles, ticks, axis names and colorbar labels are black; PNG and PDF")
    func heatmapText() throws {
        let payload = heatmapPayload()
        let style = Self.legacyStyle()
        let layout = HeatmapPlotLayout.compute(payload: payload, chartStyle: style)
        let renderer = HeatmapRenderer()
        let png = try renderer.renderPNG(payload: payload, chartStyle: style)
        let bm = try Self.decodePNG(png)
        #expect(bm.pixel(1, 1).a == 0)
        // The grid and the colorbar gradient are data/colormap, exempt from the text-color rule.
        let zones = Self.textZones(canvas: layout.rendererSize, frame: layout.gridRect, rightFrame: layout.colorbarRect)
        #expect(Self.inkPixels(bm, scale: 2, in: zones) > 500)
        let bad = Self.nonBlackPixels(bm, scale: 2, in: zones)
        #expect(bad.count == 0, "non-black text pixel \(bad.sample)")

        let pdf = try renderer.renderPDF(payload: payload, chartStyle: style)
        try Self.assertOnlyArialFonts(inPDF: pdf)
        let pbm = try Self.rasterizePDF(pdf, size: layout.rendererSize)
        let pbad = Self.nonBlackPixels(pbm, scale: 1, in: zones)
        #expect(pbad.count == 0, "PDF non-black text pixel \(pbad.sample)")
    }

    @Test("Heatmap colorbar still renders the colormap gradient (data colors untouched)")
    func heatmapColorbarGradientIntact() throws {
        let payload = heatmapPayload()
        let layout = HeatmapPlotLayout.compute(payload: payload, chartStyle: WorkbenchChartStyle())
        let bm = try Self.decodePNG(try HeatmapRenderer().renderPNG(payload: payload))
        let cb = layout.colorbarRect
        func colorAt(_ frac: CGFloat) -> (r: Double, g: Double, b: Double, a: Double) {
            let cgY = (cb.minY + frac * cb.height) * 2
            return bm.pixel(Int(cb.midX * 2), bm.height - 1 - Int(cgY))
        }
        let lo = colorAt(0.04), hi = colorAt(0.96)
        // viridis: dark purple at one end, yellow at the other — saturated, not gray/black text.
        #expect(abs(lo.r - hi.r) + abs(lo.g - hi.g) + abs(lo.b - hi.b) > 0.8)
        #expect(max(lo.r, lo.g, lo.b) - min(lo.r, lo.g, lo.b) > 0.1)
        #expect(max(hi.r, hi.g, hi.b) - min(hi.r, hi.g, hi.b) > 0.3)
    }

    /// Scale bar text on a uniform-color field: every pixel the bar adds must lie on the segment
    /// between the field color and pure white (white bar) or pure black (black bar) — i.e. the label is
    /// plain black/white, not gray, not tinted, with no contrasting stroke around the glyphs.
    @Test("Scale bar: label and bar are pure white (or pure black) in PNG and PDF")
    func scaleBarColors() throws {
        for (colorChoice, target) in [(HeatmapScaleBarColor.white, 1.0), (.black, 0.0)] {
            let bar = HeatmapScaleBarOverlay(lengthInPoints: 90, label: "5 μm", color: colorChoice)
            let with = heatmapPayload(scaleBar: bar, uniform: true)
            let without = heatmapPayload(scaleBar: nil, uniform: true)
            let style = WorkbenchChartStyle()
            let layout = HeatmapPlotLayout.compute(payload: with, chartStyle: style)
            let r = HeatmapRenderer()
            let pngWith = try Self.decodePNG(try r.renderPNG(payload: with, chartStyle: style))
            let pngWithout = try Self.decodePNG(try r.renderPNG(payload: without, chartStyle: style))
            let pdfWith = try Self.rasterizePDF(try r.renderPDF(payload: with, chartStyle: style), size: layout.rendererSize)
            let pdfWithout = try Self.rasterizePDF(try r.renderPDF(payload: without, chartStyle: style), size: layout.rendererSize)
            try Self.assertOnlyArialFonts(inPDF: try r.renderPDF(payload: with, chartStyle: style))

            let g = layout.gridRect
            let yBar = g.minY + 0.042 * g.height
            // Label zone: above the bar's contrast outline, so only glyph pixels can differ here.
            let labelZone = CGRect(x: g.minX, y: yBar + 10, width: g.width * 0.6, height: 90)
            for (a, b, scale, name) in [(pngWith, pngWithout, CGFloat(2), "PNG"), (pdfWith, pdfWithout, CGFloat(1), "PDF")] {
                var changed = 0, offLine = 0
                Self.forEachPixel(a, scale: scale, in: [labelZone]) { x, y, p in
                    let q = b.pixel(x, y)
                    guard abs(p.r - q.r) + abs(p.g - q.g) + abs(p.b - q.b) > 0.04 else { return }
                    changed += 1
                    // p = field + t·(T − field) for one scalar t ⇒ same t on every channel.
                    let ts = [(p.r - q.r) / (target - q.r), (p.g - q.g) / (target - q.g), (p.b - q.b) / (target - q.b)]
                        .filter { $0.isFinite }
                    if let lo = ts.min(), let hi = ts.max(), hi - lo > 0.12 { offLine += 1 }
                }
                #expect(changed > 150, "\(name) \(colorChoice): label drawn (\(changed) px)")
                #expect(offLine == 0, "\(name) \(colorChoice): \(offLine) off-palette (gray/tinted/stroked) label pixels")
            }
        }
    }

    // MARK: - RSM / AFM payload parity

    @Test("Heatmap with default style (no legacy settings) embeds only Arial in PDF")
    func heatmapDefaultPDFFonts() throws {
        try Self.assertOnlyArialFonts(inPDF: try HeatmapRenderer().renderPDF(payload: heatmapPayload()))
    }

    // MARK: - PDF font inspection

    /// Every embedded font in the PDF must be an Arial face (subset prefix allowed).
    private static func assertOnlyArialFonts(inPDF data: Data, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let text = String(decoding: data, as: UTF8.self)   // font dictionaries are plain ASCII objects
        var names: [String] = []
        var rest = text[...]
        while let r = rest.range(of: "/FontName") {
            rest = rest[r.upperBound...]
            let line = rest.prefix(80)
            if let slash = line.firstIndex(of: "/") {
                let tail = line[line.index(after: slash)...]
                names.append(String(tail.prefix { !" \n\r>/".contains($0) }))
            }
        }
        #expect(!names.isEmpty, "PDF embeds at least one font", sourceLocation: sourceLocation)
        for n in names {
            #expect(n.contains("Arial"), "PDF font \(n) is not Arial", sourceLocation: sourceLocation)
            #expect(!n.contains("Times"), "PDF font \(n)", sourceLocation: sourceLocation)
        }
    }
}
