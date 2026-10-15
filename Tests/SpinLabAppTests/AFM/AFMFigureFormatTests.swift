import CryptoKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SpinLabApp

@Suite("AFM paper-figure format")
struct AFMFigureFormatTests {

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
    }

    private func rgb(_ color: CGColor) -> (Double, Double, Double) {
        let c = color.components ?? [0, 0, 0]
        return (Double(c[0]), Double(c[1]), Double(c[2]))
    }

    private func grid(_ n: Int = 40) -> HeatmapGrid {
        let xs = (0..<n).map { Double($0) * 0.1 }
        return HeatmapGrid(xValues: xs, yValues: xs, zMatrix: xs.map { y in xs.map { x in x + y } })
    }

    // MARK: Palette

    @Test("approved palette CSV is unchanged and still equals the compiled stops")
    func approvedPaletteUntouched() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let data = try Data(contentsOf: root.appending(path: "Resources/Palettes/approved_palette.csv"))
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(sha == HeatmapColorScale.approvedGwyddionPaletteSHA256)

        let rows = String(decoding: data, as: UTF8.self).split(separator: "\n").dropFirst()
        #expect(rows.count == 256)
        for (row, stop) in zip(rows, HeatmapColorScale.gwyddionStops) {
            let v = row.split(separator: ",").compactMap { Double($0) }
            #expect(abs(v[0] - stop.r) < 1e-9 && abs(v[1] - stop.g) < 1e-9 && abs(v[2] - stop.b) < 1e-9)
        }
    }

    @Test("warm variant equals the approved palette up to t=0.80 and is only slightly warmer at the top")
    func warmVariantShape() {
        let base = HeatmapColorScale(zMin: 0, zMax: 1, transform: .linear, colormapKey: "gwyddion")
        let warm = HeatmapColorScale(zMin: 0, zMax: 1, transform: .linear, colormapKey: "gwyddionWarm")
        #expect(warm.colormap == .gwyddionWarm)
        for t in stride(from: 0.0, through: 0.80, by: 0.05) {
            #expect(rgb(base.color(forNormalized: t)) == rgb(warm.color(forNormalized: t)))
        }
        let top = rgb(warm.color(forNormalized: 1))
        #expect(top.0 == 1.0)
        #expect(top.1 < 1.0 && top.1 > 0.95)      // slight, not a strong yellow
        #expect(top.2 < top.1 && top.2 > 0.8)     // warmer: less blue than green
        // R never drops, so luminance ordering stays monotone along the ramp.
        var last = -1.0
        for i in 0...100 {
            let c = rgb(warm.color(forNormalized: Double(i) / 100))
            let luma = 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2
            #expect(luma >= last - 1e-9)
            last = luma
        }
    }

    @Test("AFM plots really render with the warm palette; height data is untouched")
    func afmUsesWarmPalette() throws {
        let g = grid()
        let before = g.zMatrix
        let payload = HeatmapPlotPayload(workflowID: "afm", title: "", xLabel: "", yLabel: "", zLabel: "", grid: g, colormapKey: AFMHeatmapPayloadBuilder.Options(workflowID: "afm").colormapKey)
        #expect(payload.colormapKey == "gwyddionWarm")
        var plain = payload
        plain.colormapKey = "gwyddion"
        let a = try HeatmapRenderPipeline.render(.init(payload: payload)).imageData
        let b = try HeatmapRenderPipeline.render(.init(payload: plain)).imageData
        #expect(a != b, "palette key must change the rendered pixels")
        #expect(payload.grid.zMatrix == before)
    }

    // MARK: Colorbar / axes

    @Test("endpoint labels carry the unit with a true minus sign, top value first in drawing order")
    func endpointUnits() {
        let e = HeatmapPlotLayout.makeEndpointsColorbarTickEntries(zMin: -0.27, zMax: 0.43, decimals: 2, unit: "nm")
        #expect(e.map(\.label) == ["−0.27 nm", "0.43 nm"])
        #expect(HeatmapPlotLayout.makeEndpointsColorbarTickEntries(zMin: 0, zMax: 1).map(\.label) == ["0.00", "1.00"])
    }

    @Test("hidden axes + endpoint colorbar: no ticks, tight left margin, label fits inside the canvas")
    func axisFreeLayout() {
        let payload = HeatmapPlotPayload(workflowID: "afm", title: "T", xLabel: "", yLabel: "", zLabel: "", grid: grid(), hideSpatialAxes: true)
        let layout = HeatmapPlotLayout.compute(payload: payload, colorbarTickStyle: .endpointsOnly(decimals: 2, unit: "nm"))
        #expect(layout.xTickEntries.isEmpty && layout.yTickEntries.isEmpty)
        #expect(layout.gridRect.minX == HeatmapPlotLayout.noTitleTopPadding)
        #expect(layout.colorbarTicks.map(\.label).allSatisfy { $0.hasSuffix(" nm") })
        let labelWidth = layout.colorbarTicks.map { HeatmapPlotLayout.measuredTextWidth($0.label, fontSize: 29, fontName: WorkbenchChartStyle().fontName, boldFontName: WorkbenchChartStyle().boldFontName) }.max() ?? 0
        #expect(layout.colorbarRect.maxX + 8 + labelWidth <= layout.rendererSize.width + 0.5, "endpoint label must not be clipped")
        // No Z title lane: colorbar sits one standard gap from the grid.
        #expect(abs(layout.colorbarRect.minX - layout.gridRect.maxX - 30 - (100.0 / 350.0 * 72.0)) < 0.5)
    }

    // MARK: Scale bar

    private func pixel(_ png: Data, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let src = CGImageSourceCreateWithData(png as CFData, nil)!
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let o = y * ctx.bytesPerRow + x * 4
        return (Int(p[o]), Int(p[o + 1]), Int(p[o + 2]))
    }

    @Test("scale bar colour choice changes the drawn bar; length stays physical")
    func scaleBarColour() throws {
        let g = grid(100)   // 10 µm wide
        func render(_ color: HeatmapScaleBarColor) throws -> (HeatmapRenderPipeline.Output, HeatmapScaleBarOverlay) {
            let overlay = try #require(AFMScaleBarSetting(mode: .manual, manualLengthMicrometers: 2, color: color).overlay(scanWidthMicrometers: 10))
            let payload = HeatmapPlotPayload(workflowID: "afm", title: "", xLabel: "", yLabel: "", zLabel: "", grid: g,
                                             colormapKey: "gwyddionWarm", scaleBarOverlay: overlay, hideSpatialAxes: true)
            return (try HeatmapRenderPipeline.render(.init(payload: payload, showColorbar: false, showTitle: false)), overlay)
        }
        let (white, _) = try render(.white)
        let (black, _) = try render(.black)
        #expect(white.imageData != black.imageData)
        for (out, expected) in [(white, 255), (black, 0)] {
            let bar = try #require(out.layout.scaleBarOverlay)
            #expect(abs(Double(bar.lengthInPoints / out.layout.gridRect.width) - 0.2) < 1e-9)
            // bar centre line in image pixels (renderer scale 2×, origin bottom-left → flip Y)
            let scale: CGFloat = 2
            let x = Int((out.layout.gridRect.minX + 0.045 * out.layout.gridRect.width + bar.lengthInPoints / 2) * scale)
            let y = Int((out.layout.rendererSize.height - (out.layout.gridRect.minY + 0.042 * out.layout.gridRect.height)) * scale)
            let p = pixel(out.imageData, x: x, y: y)
            #expect(abs(p.r - expected) < 20 && abs(p.g - expected) < 20 && abs(p.b - expected) < 20, "bar pixel \(p) vs \(expected)")
        }
    }

    @Test("old scale bar settings without colour decode as white")
    func scaleBarLegacyDecode() throws {
        let s = try JSONDecoder().decode(AFMScaleBarSetting.self, from: Data(#"{"mode":"manual","manualLengthMicrometers":3}"#.utf8))
        #expect(s.color == .white && s.mode == .manual)
        #expect(try JSONDecoder().decode(HeatmapScaleBarOverlay.self, from: Data(#"{"lengthInPoints":10,"label":"1 µm"}"#.utf8)).color == nil)
    }

    // MARK: Legacy pack

    @MainActor
    @Test("old Pack with axis labels, tick counts and Z label restores into the axis-free AFM format")
    func legacyPackRendersNewFormat() async throws {
        let n = 24
        let xs = (0..<n).map { Double($0) * 0.2 }
        let values = xs.map { y in xs.map { x in sin(x) + cos(y) } }
        let channel = CanonicalAFMChannel(
            id: "c", sourceIndex: 0, sourceLabel: "HeightTrace", semanticTypeRaw: "Height", displayLabel: "HeightTrace",
            values: values, canonicalUnit: "nm", sourceUnit: "m",
            provenance: AFMChannelProvenance(planefit: nil, planefitOrder: nil, flattenOrder: nil, planefitOffset: nil, planefitXSlope: nil, planefitYSlope: nil)
        )
        let dataset = CanonicalAFMDataset(
            sourceRef: "/x.ibw", title: "Legacy", xCoordinates: xs, yCoordinates: xs, channels: [channel],
            sourceMetadata: AFMSourceProvenance(sourceFilePath: "/x.ibw", waveName: "Legacy", sourceWidth: n, sourceHeight: n, rawNote: "")
        )
        let legacyDisplay = try JSONDecoder().decode(HeatmapTabRenderState.self, from: Data(#"{"xLabelOverride":"My X","yLabelOverride":"My Y","zLabelOverride":"My Z","xTickCount":9,"yTickCount":9,"colormapKey":"gwyddion"}"#.utf8))
        let packState = try JSONDecoder().decode(AFMPackState.self, from: Data(#"{"processingConfiguration":{"activeChannelID":"c","planeLevelEnabled":true}}"#.utf8))
        let config = AFMPackConfig(packState: packState, displayState: legacyDisplay)
        let result = AFMPackResult(canonicalDataset: dataset)
        let pack = AnalysisPack(label: "t", workflowID: "afm", filePaths: ["/x.ibw"], sampleKeys: ["k"], sourceFingerprint: "f",
                                config: try JSONEncoder().encode(config), result: try JSONEncoder().encode(result))

        func restore(_ cfg: AFMPackConfig) async throws -> Data {
            let store = AFMWorkspaceStore(workflowID: "afm")
            store.restoreFromPack(config: cfg, result: result, pack: pack, restoreSearchState: { _, _ in }, seedSelection: { _, _ in })
            for _ in 0..<300 where store.isAnalyzing || store.renderedImageData == nil { try await Task.sleep(nanoseconds: 20_000_000) }
            #expect(store.packRestoreErrorMessage == nil)
            return try #require(store.renderedImageData)
        }
        let legacyImage = try await restore(config)
        var clean = legacyDisplay
        clean.xLabelOverride = ""; clean.yLabelOverride = ""; clean.zLabelOverride = ""; clean.colormapKey = nil
        clean.xTickCount = 5; clean.yTickCount = 5
        let cleanImage = try await restore(AFMPackConfig(packState: packState, displayState: clean))
        #expect(legacyImage == cleanImage, "legacy axis/Z overrides and colormap key must not alter the AFM figure")
        #expect(packState.processingConfiguration.surfaceLevel == .plane)
    }

    // MARK: Controls / tray

    @Test("Selected tray is gated on multiple-selection workflows only")
    func selectedTrayGated() throws {
        let left = try source("Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceLeftColumn.swift")
        #expect(left.contains("workbench.selectionMode(for: workflowID) == .multiple"))
        #expect(left.contains("SelectedHitsTray(workflowID: workflowID, workbench: workbench)"))
        let bar = try source("Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceActionBar.swift")
        #expect(bar.contains("Clear Selected") && bar.contains("Analyze"))
    }
}

@Suite("AFM Z colorbar multi-tick")
struct AFMZColorbarTickTests {

    private typealias L = HeatmapPlotLayout

    private func values(_ lo: Double, _ hi: Double, gap: CGFloat = 0.06) -> [(y: CGFloat, v: Double)] {
        L.makeZHeightColorbarTickEntries(zMin: lo, zMax: hi, minNormalizedGap: gap).map {
            (y: $0.normalizedY, v: Double($0.label.replacingOccurrences(of: "−", with: "-"))!)
        }
    }

    @Test("5 evenly spaced ticks, true limits included, values linearly interpolated")
    func evenFiveTicks() {
        for (lo, hi) in [(-0.27, 0.43), (-5.1, 7.9), (0.0, 12.0), (-120.0, 80.0), (2.0, 2.9), (-0.004, 0.011), (-9.0, -1.0)] {
            let t = values(lo, hi)
            #expect(t.count == 5, "\(lo)...\(hi): \(t.map(\.v))")
            #expect(t.first!.y == 0 && t.last!.y == 1)
            for (i, e) in t.enumerated() {
                #expect(abs(Double(e.y) - Double(i) / 4) < 1e-9, "uneven position \(e.y)")
                let expected = (e.v - lo) / (hi - lo)   // label value sits at its true height
                #expect(abs(Double(e.y) - expected) < 0.03, "\(lo)...\(hi): tick \(e.v) at \(e.y)")
            }
            #expect(abs(t.first!.v - lo) < 0.006 && abs(t.last!.v - hi) < 0.006)
        }
    }

    @Test("short bars drop ticks (never overlap); tiny and zero spans stay distinct")
    func reducedAndTinySpans() {
        for gap in [CGFloat(0.26), 0.34, 0.6] {
            let t = L.makeZHeightColorbarTickEntries(zMin: -0.004, zMax: 1.2, minNormalizedGap: gap)
            #expect(t.count < 5 && t.count >= 2)
            #expect(t.first!.normalizedY == 0 && t.last!.normalizedY == 1)
            let ys = t.map(\.normalizedY)
            #expect(zip(ys, ys.dropFirst()).allSatisfy { $1 - $0 >= gap - 1e-9 || t.count == 2 })
        }
        for (lo, hi) in [(-0.0004, 0.0036), (0.0, 1e-5)] {
            let labels = L.makeZHeightColorbarTickEntries(zMin: lo, zMax: hi).map(\.label)
            #expect(Set(labels).count == labels.count, "duplicates: \(labels)")
            #expect(labels.count >= 2)
        }
        #expect(L.makeZHeightColorbarTickEntries(zMin: 1, zMax: 1).count == 1)
    }

    @Test("labels are numbers only, one decimal count, true minus sign, no negative zero")
    func labelFormat() {
        let labels = L.makeZHeightColorbarTickEntries(zMin: -0.27, zMax: 0.43).map(\.label)
        #expect(labels.allSatisfy { !$0.contains("nm") && !$0.contains("-") })
        #expect(Set(labels.map { $0.split(separator: ".").last!.count }).count == 1)
        #expect(!labels.contains { $0.hasPrefix("−0.00") })
    }

    @Test("label column: decimal points share one x, the minus hangs left of the body, widths are proportional glyph advances")
    func decimalColumnGeometry() {
        let st = WorkbenchChartStyle()
        let labels = ["12.50", "6.00", "0.00", "−3.25", "−12.50", "0.65\u{00A0}nm"]
        let col = L.zHeightLabelColumn(labels: labels, fontSize: 29, fontName: st.fontName, boldFontName: st.boldFontName)
        func w(_ t: String) -> CGFloat { L.measuredTextWidth(t, fontSize: 29, fontName: st.fontName, boldFontName: st.boldFontName) }
        #expect(col.signWidth == w("−") && col.signWidth > 0)
        for (i, l) in labels.enumerated() {
            let sp = L.splitZHeightLabel(l)
            // decimal point x = body start + integer-part width: identical for every label
            #expect(abs(col.bodyOffset(i) + w(sp.integer) - (col.signWidth + col.maxInteger)) < 1e-6, "\(l)")
            // minus ends exactly where the body starts and never leaves the column
            if !sp.sign.isEmpty {
                #expect(abs(col.signOffset(i) + w("−") - col.bodyOffset(i)) < 1e-6)
                #expect(col.signOffset(i) >= -1e-6)
            }
            #expect(col.bodyOffset(i) + w(sp.body) <= col.width + 1e-6)
        }
        // `1` of "1.00" and "−1.00" sit on the same x; unit follows the number in one run (no break).
        let pair = L.zHeightLabelColumn(labels: ["1.00", "−1.00"], fontSize: 29, fontName: st.fontName, boldFontName: st.boldFontName)
        #expect(abs(pair.bodyOffset(0) - pair.bodyOffset(1)) < 1e-6)
        #expect(L.splitZHeightLabel("0.65\u{00A0}nm").body == "0.65\u{00A0}nm")
        // no negative labels: no space reserved for a minus
        #expect(L.zHeightLabelColumn(labels: ["1.00", "2.00"], fontSize: 29, fontName: st.fontName, boldFontName: st.boldFontName).signWidth == 0)
    }

    @Test("style carries the unit once and is AFM-only")
    func styleSemantics() {
        #expect(HeatmapColorbarTickStyle.zHeightTicks(unit: "nm").colorbarUnit == "nm")
        #expect(HeatmapColorbarTickStyle.standard.colorbarUnit.isEmpty)
        #expect(!HeatmapColorbarTickStyle.standard.usesAFMColorbarTypography)
        #expect(!HeatmapColorbarTickStyle.powerOfTenFromLogValues.usesAFMColorbarTypography)
        #expect(HeatmapColorbarTickStyle.zHeightTicks(unit: "nm").usesAFMColorbarTypography)
    }

    // MARK: Real IBW render (PNG + PDF)

    private static func renderReal(_ relative: String) throws -> (out: HeatmapRenderPipeline.Output, unit: String) {
        let url = URL(fileURLWithPath: "\(AFMRealDataAcceptanceTests.root)/\(relative)")
        #expect(FileManager.default.fileExists(atPath: url.path), "REQUIRED real sample missing: \(url.path)")
        let ds = try AFMInputAdapter.load(fileURL: url).dataset
        let channel = try #require(AFMChannelResolver.resolveDefaultChannel(in: ds.channels).channel)
        let processed = AFMProcessingPipeline.process(
            channel: channel, xCoordinates: ds.xCoordinates, yCoordinates: ds.yCoordinates,
            configuration: AFMProcessingConfiguration(activeChannelID: channel.id))
        let payload = try AFMHeatmapPayloadBuilder.build(dataset: ds, processed: processed, options: .init(workflowID: "afm"))
        let out = try HeatmapRenderPipeline.render(.init(
            payload: payload, zDomainState: AFMWorkspaceStore.defaultDisplayState.zDomainState,
            showColorbar: true, showTitle: true,
            colorbarTickStyleOverride: .zHeightTicks(unit: processed.canonicalUnit)))
        return (out, processed.canonicalUnit)
    }

    @Test("real IBW: top label is one line `upper limit + nm` (no-break), other ticks numbers only, bottom keeps the lower limit",
          arguments: AFMRealDataAcceptanceTests.files)
    func topLabelCarriesUnit(relative: String) throws {
        let (out, unit) = try Self.renderReal(relative)
        let layout = out.layout
        let labels = layout.colorbarTicks.sorted { $0.y > $1.y }.map(\.label)
        let top = try #require(labels.first)
        #expect(top == String(format: "%.2f", layout.zMax) + "\u{00A0}" + unit, "top label \(top)")
        #expect(!top.contains("\n") && !top.contains(" "), "no breakable space in the top label")
        #expect(labels.dropFirst().allSatisfy { !$0.contains(unit) }, "unit only once: \(labels)")
        let bottom = try #require(labels.last)
        #expect(bottom == String(format: "%.2f", layout.zMin).replacingOccurrences(of: "-", with: "−"))
        #expect(bottom.hasPrefix("−") == (layout.zMin < 0))
        // The widest label (top, with unit) fits inside the canvas.
        let w = HeatmapPlotLayout.measuredTextWidth(top, fontSize: 29, fontName: WorkbenchChartStyle().fontName, boldFontName: WorkbenchChartStyle().boldFontName)
        #expect(layout.colorbarRect.maxX + 8 + 3 + w <= layout.rendererSize.width + 0.5)
    }

    @Test("real IBW: tick marks sit at their Z heights in the PNG, labels are black Arial ink right of the bar, unit once; PDF embeds only Arial",
          arguments: AFMRealDataAcceptanceTests.files)
    func realIBWColorbarPixelsAndFonts(relative: String) throws {
        let (out, unit) = try Self.renderReal(relative)
        let layout = out.layout
        let ticks = layout.colorbarTicks
        #expect(ticks.count == 5)
        #expect(unit == "nm")

        // Tick positions follow the Z mapping: label value ↔ normalized height.
        for t in ticks {
            let numeric = t.label.replacingOccurrences(of: "\u{00A0}" + unit, with: "").replacingOccurrences(of: "−", with: "-")
            let v = Double(numeric)!
            let half = HeatmapPlotLayout.zHeightTickWidth / 2
            let expectedY = layout.colorbarRect.minY + half + CGFloat((v - layout.zMin) / (layout.zMax - layout.zMin)) * (layout.colorbarRect.height - 2 * half)
            #expect(abs(t.y - expectedY) < layout.colorbarRect.height * 0.006, "tick \(t.label)")
        }
        let half = HeatmapPlotLayout.zHeightTickWidth / 2
        #expect(ticks.map(\.y).min()! >= layout.colorbarRect.minY + half - 1e-6)
        #expect(ticks.map(\.y).max()! <= layout.colorbarRect.maxY - half + 1e-6)

        // PNG pixels.
        let src = try #require(CGImageSourceCreateWithData(out.imageData as CFData, nil))
        let img = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px.withUnsafeMutableBytes { raw in
            let c = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let scale = CGFloat(w) / layout.rendererSize.width
        func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            let i = (y * w + x) * 4
            return (Double(px[i]) / 255, Double(px[i + 1]) / 255, Double(px[i + 2]) / 255)
        }
        let cb = layout.colorbarRect
        // Tick mark: pure black, 2 pt thick (clearly visible, not heavier than ~3 pt), at every tick row.
        let tickX = Int((cb.maxX + 3) * scale)
        for t in ticks {
            let row = h - 1 - Int(t.y * scale)
            var run = 0
            for d in -10...10 {
                let c = rgb(tickX, min(max(row + d, 0), h - 1))
                if c.0 < 0.08 && c.1 < 0.08 && c.2 < 0.08 { run += 1 }
            }
            #expect(run >= Int(HeatmapPlotLayout.zHeightTickWidth * scale) - 1 && run <= Int(3 * scale) + 1,
                    "tick \(t.label): \(run) px thick")
        }
        // Text zone: right of tick marks, vertically from above the unit to below the bar.
        let x0 = Int((cb.maxX + HeatmapPlotLayout.zHeightTickLength + 3) * scale)
        var ink = 0
        var offBlack = 0
        for y in 0..<h {
            for x in x0..<w {
                let c = rgb(x, y)
                if c.0 > 0.97 && c.1 > 0.97 && c.2 > 0.97 { continue }   // white background
                if c.0 < 0.1 && c.1 < 0.1 && c.2 < 0.1 { ink += 1 }
                // anti-aliasing of black on white is neutral gray; any color cast means colored text
                if abs(c.0 - c.1) > 0.03 || abs(c.1 - c.2) > 0.03 { offBlack += 1 }
            }
        }
        // Each label's ink is vertically centred on its own tick (±2 px).
        for t in ticks {
            let row = h - 1 - Int(t.y * scale)
            let r = Int(29 * 0.45 * scale)
            let rows = ((row - r)...(row + r)).filter { y in y >= 0 && y < h && (x0..<w).contains { rgb($0, y).0 < 0.5 } }
            let centre = Double(rows.first! + rows.last!) / 2
            #expect(abs(centre - Double(row)) <= 2.5, "label \(t.label) off its tick by \(centre - Double(row)) px")
        }
        // Decimal points: a small ink blob on the baseline, centred on one common x for every label.
        let st = WorkbenchChartStyle()
        let col = HeatmapPlotLayout.zHeightLabelColumn(labels: ticks.map(\.label), fontSize: 29, fontName: st.fontName, boldFontName: st.boldFontName)
        let dotW = HeatmapPlotLayout.measuredTextWidth(".", fontSize: 29, fontName: st.fontName, boldFontName: st.boldFontName)
        let expectedDotX = (cb.maxX + HeatmapPlotLayout.zHeightTickLength + HeatmapPlotLayout.zHeightLabelGap + col.signWidth + col.maxInteger + dotW / 2) * scale
        for t in ticks {
            let row = h - 1 - Int(t.y * scale)
            let r = Int(29 * 0.45 * scale)
            let rows = ((row - r)...(row + r)).filter { y in y >= 0 && y < h && (x0..<w).contains { rgb($0, y).0 < 0.5 } }
            let band = (rows.last! - 2)...(rows.last! - 1)
            let cols = (x0..<w).filter { x in band.contains { rgb(x, $0).0 < 0.5 } }
            var runs: [ClosedRange<Int>] = []
            for x in cols { if let l = runs.last, x == l.upperBound + 1 { runs[runs.count - 1] = l.lowerBound...x } else { runs.append(x...x) } }
            let dot = runs.first { abs(Double(($0.lowerBound + $0.upperBound)) / 2 - Double(expectedDotX)) <= 2.0 && $0.count <= Int(29 * 0.2 * scale) }
            #expect(dot != nil, "no decimal point on the common column for \(t.label); runs \(runs) expected x \(expectedDotX)")
            // The minus (when present) lies left of the first digit column and right of the tick.
            if t.label.hasPrefix("−"), let first = runs.first {
                #expect(Double(first.lowerBound) >= Double(x0) - 1)
            }
        }
        #expect(ink > 800, "label ink present: \(ink)")
        #expect(offBlack == 0, "text pixels with a color cast: \(offBlack)")
        // Single-line top label centred on the top tick: ink may rise only half a text height above
        // the bar (no separate unit row stacked higher).
        let barTopRow = h - 1 - Int(cb.maxY * scale)
        let allowed = Int(29 * 0.5 * scale) + 2
        let inkAbove = (0..<max(0, barTopRow - allowed)).filter { y in (x0..<w).contains { rgb($0, y).0 < 0.5 } }
        #expect(inkAbove.isEmpty, "text above the colorbar top: rows \(inkAbove.prefix(3))")
        let band = (barTopRow - allowed)...(barTopRow + Int(29 * 0.7 * scale))
        let bandRows = band.filter { y in (x0..<w).contains { rgb($0, y).0 < 0.5 } }
        let groups = zip(bandRows, bandRows.dropFirst()).filter { $1 - $0 > 3 }.count + 1
        #expect(!bandRows.isEmpty && groups == 1, "top label is a single text line")
        // The line extends over the unit: ink reaches further right than the bottom (number-only) label.
        func rightmost(_ rows: ClosedRange<Int>) -> Int {
            var m = 0
            for y in rows { for x in x0..<w where rgb(x, y).0 < 0.5 { m = max(m, x) } }
            return m
        }
        let bottomRow = h - 1 - Int(cb.minY * scale)
        #expect(rightmost(band) > rightmost((bottomRow - Int(29 * 0.7 * scale))...bottomRow) + Int(20 * scale), "unit follows the upper limit on the same line")
        #expect(ticks.filter { $0.label.contains(unit) }.count == 1)

        // PDF: Arial only, and the same ticks exist (non-empty fonts).
        let text = String(decoding: out.pdfData, as: UTF8.self)
        var names: [String] = []
        var rest = text[...]
        while let r = rest.range(of: "/FontName") {
            rest = rest[r.upperBound...]
            let line = rest.prefix(80)
            if let slash = line.firstIndex(of: "/") {
                names.append(String(line[line.index(after: slash)...].prefix { !" \n\r>/".contains($0) }))
            }
        }
        #expect(!names.isEmpty)
        #expect(names.allSatisfy { $0.contains("Arial") }, "PDF fonts: \(names)")
    }

    @Test("Scale bar is one opaque solid line in the label colour: no outline, shadow or second layer (PNG and PDF)")
    func scaleBarIsPlainSolid() throws {
        let n = 24
        let xs = (0..<n).map { Double($0) * 0.1 }
        let z = (0..<n).map { _ in (0..<n).map { _ in 0.5 } }
        func payload(_ bar: HeatmapScaleBarOverlay?) -> HeatmapPlotPayload {
            HeatmapPlotPayload(workflowID: "afm", title: "T", xLabel: "", yLabel: "", zLabel: "",
                               grid: HeatmapGrid(xValues: xs, yValues: xs, zMatrix: z),
                               colormapKey: "viridis", scaleBarOverlay: bar, hideSpatialAxes: true)
        }
        func decode(_ img: CGImage) -> (w: Int, h: Int, px: [UInt8]) {
            var px = [UInt8](repeating: 0, count: img.width * img.height * 4)
            px.withUnsafeMutableBytes { raw in
                CGContext(data: raw.baseAddress, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    .draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            }
            return (img.width, img.height, px)
        }
        func png(_ d: Data) throws -> (w: Int, h: Int, px: [UInt8]) {
            let src = try #require(CGImageSourceCreateWithData(d as CFData, nil))
            return decode(try #require(CGImageSourceCreateImageAtIndex(src, 0, nil)))
        }
        func pdf(_ d: Data, size: CGSize) throws -> (w: Int, h: Int, px: [UInt8]) {
            let provider = try #require(CGDataProvider(data: d as CFData))
            let doc = try #require(CGPDFDocument(provider))
            let page = try #require(doc.page(at: 1))
            let w = Int(size.width * 2), h = Int(size.height * 2)
            var px = [UInt8](repeating: 255, count: w * h * 4)
            px.withUnsafeMutableBytes { raw in
                let c = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
                c.scaleBy(x: 2, y: 2); c.drawPDFPage(page)
            }
            return (w, h, px)
        }
        for (choice, target) in [(HeatmapScaleBarColor.white, UInt8(255)), (.black, UInt8(0))] {
            let bar = HeatmapScaleBarOverlay(lengthInPoints: 90, label: "5 μm", color: choice)
            let style = WorkbenchChartStyle()
            let layout = HeatmapPlotLayout.compute(payload: payload(bar), chartStyle: style)
            let r = HeatmapRenderer()
            let g = layout.gridRect
            let x0 = g.minX + 0.045 * g.width, yBar = g.minY + 0.042 * g.height
            let shots: [(String, (w: Int, h: Int, px: [UInt8]), (w: Int, h: Int, px: [UInt8]))] = [
                ("PNG", try png(try r.renderPNG(payload: payload(bar), chartStyle: style)), try png(try r.renderPNG(payload: payload(nil), chartStyle: style))),
                ("PDF", try pdf(try r.renderPDF(payload: payload(bar), chartStyle: style), size: layout.rendererSize),
                        try pdf(try r.renderPDF(payload: payload(nil), chartStyle: style), size: layout.rendererSize)),
            ]
            for (name, a, b) in shots {
                // Rows/cols of the bar zone (CG y-up → bitmap rows), generous 6 pt margin all round.
                var changedRows = Set<Int>(), badColor = 0
                for py in 0..<a.h {
                    let cgY = (CGFloat(a.h - 1 - py) + 0.5) / 2
                    guard abs(cgY - yBar) < 8 else { continue }
                    for px in 0..<a.w {
                        let cgX = (CGFloat(px) + 0.5) / 2
                        guard cgX > x0 - 8, cgX < x0 + 90 + 8 else { continue }
                        let i = (py * a.w + px) * 4
                        if abs(Int(a.px[i]) - Int(b.px[i])) + abs(Int(a.px[i + 1]) - Int(b.px[i + 1])) + abs(Int(a.px[i + 2]) - Int(b.px[i + 2])) > 6 {
                            changedRows.insert(py)
                            // fully covered pixels must be exactly the label colour; only edge pixels may blend
                            let covered = abs(Int(a.px[i]) - Int(target)) < 3 && abs(Int(a.px[i + 1]) - Int(target)) < 3 && abs(Int(a.px[i + 2]) - Int(target)) < 3
                            if !covered {
                                // blend of field colour and target only (neutral axis): channels move toward target together
                                let d = [a.px[i] , a.px[i + 1], a.px[i + 2]].enumerated().map { (k, v) -> Double in
                                    let f = Double([b.px[i], b.px[i + 1], b.px[i + 2]][k]); let t = Double(target)
                                    return abs(t - f) < 1 ? 0 : (Double(v) - f) / (t - f) }
                                if (d.max()! - d.min()!) > 0.12 { badColor += 1 }
                            }
                        }
                    }
                }
                // 5 pt bar at 2 px/pt = 10 rows; an outline would add 2×1.5 pt = 6 more rows.
                #expect(!changedRows.isEmpty, "\(name) \(choice): bar drawn")
                #expect(changedRows.count <= 12, "\(name) \(choice): bar zone spans \(changedRows.count) rows (outline present?)")
                #expect(badColor == 0, "\(name) \(choice): \(badColor) pixels not on the field→\(target) line (stroke/shadow)")
            }
        }
    }
}
