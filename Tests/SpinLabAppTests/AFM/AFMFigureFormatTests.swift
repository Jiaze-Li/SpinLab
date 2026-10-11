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

    @Test("AFM workspace no longer mounts axis, tick, Z-label or axis/tick font-size controls")
    func afmControlsCleaned() throws {
        let view = try source("Sources/SpinLabApp/Features/Workbench/AFMWorkspaceView.swift")
        for dead in ["onXLabelOverride", "onYLabelOverride", "onZLabelOverride", "onXTickCountChange", "onYTickCountChange", "xLabelOverride", "zLabelOverride", "xTickCount"] {
            #expect(!view.contains(dead), "dead AFM control wiring: \(dead)")
        }
        let store = try source("Sources/SpinLabApp/Features/Workbench/AFMWorkspaceStore.swift")
        for dead in ["updateHeatmapXAxisLabel", "updateHeatmapYAxisLabel", "updateHeatmapZLabel", "updateHeatmapXTickCount", "updateHeatmapYTickCount"] {
            #expect(!store.contains(dead))
        }
        let panel = try source("Sources/SpinLabApp/Workbench/V3/Heatmap/HeatmapPlotControlsPanel.swift")
        #expect(panel.contains("showsAxisControls"))
        #expect(panel.contains("titleOnlyControls"))
        let controls = try source("Sources/SpinLabApp/Features/Workbench/AFMPlotControls.swift")
        #expect(controls.contains("Edge Crop") && controls.contains(".disabled(true)"))
    }

    @Test("Selected tray is gated on multiple-selection workflows only")
    func selectedTrayGated() throws {
        let left = try source("Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceLeftColumn.swift")
        #expect(left.contains("workbench.selectionMode(for: workflowID) == .multiple"))
        #expect(left.contains("SelectedHitsTray(workflowID: workflowID, workbench: workbench)"))
        let bar = try source("Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceActionBar.swift")
        #expect(bar.contains("Clear Selected") && bar.contains("Analyze"))
    }
}
