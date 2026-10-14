import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SpinLabApp

@Suite("AFM V1 final acceptance fixes")
struct AFMFinalAcceptanceTests {

    // MARK: Helpers

    private func fixtureData(waveName: String = "WaveName") -> Data {
        let n = 8
        let plane = (0..<n).map { y in (0..<n).map { x in Float(1e-7) + Float(y * n + x) * 1e-9 } }
        return IBWFixtureBuilder.build(
            waveName: waveName, nX: n, nY: n,
            channels: [IBWFixtureBuilder.Channel(label: "HeightRetrace", semanticType: "Height", values: plane)],
            xScale: 1e-7, yScale: 1e-7
        )
    }

    private func writeFixture(named name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("afm-final-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try fixtureData().write(to: url)
        return url
    }

    @MainActor
    private func hit(_ url: URL) -> WorkbenchSelectedHitsSnapshot {
        let h = WorkflowMeasurementSearchHit(
            sidecarPath: "\(url.path).spinlab.json", measurementFilePath: url.path, sourceFilePath: url.path,
            workflowID: "afm", workflowDisplayName: "AFM", workflowCanonicalID: "afm",
            batchID: "B", sampleKey: "B|b|S|001", sampleSubstrate: "S",
            conditions: [:], channels: [], appliedAt: .distantPast
        )
        return WorkbenchSelectedHitsSnapshot(
            workflowID: "afm", queryText: "", selectedIDs: [h.id], selectedHits: [h],
            sourceHitCount: 1, selectionSource: .canonicalSnapshot
        )
    }

    @MainActor
    private func analyze(_ store: AFMWorkspaceStore, _ url: URL) async {
        store.runAnalysis(selectedHitsSnapshot: hit(url))
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, store.isAnalyzing || store.renderedImageData == nil || store.cachedInputFiles.first != url.path {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func firstPixelAlpha(_ png: Data) -> UInt8? {
        guard let src = CGImageSourceCreateWithData(png as CFData, nil),
              let full = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let image = full.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)) else { return nil }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1), byTiling: false)
        return pixel[3]
    }

    // MARK: Tests

    @Test("scale bar label uses the real Greek mu")
    func scaleBarLabelUsesGreekMu() {
        let label = AFMScaleBarSetting.label(forMicrometers: 2)
        #expect(label == "2 \u{03BC}m")
        #expect(!label.contains("\u{00B5}"))
    }

    @Test("default title is the source file name without extension")
    func defaultTitleIsFileStem() throws {
        let output = try AFMInputAdapter.build(from: fixtureData(waveName: "WaveName"), sourceRef: "/tmp/dir/LNO22_CONTACT_0000_AFM.ibw")
        #expect(output.dataset.title == "LNO22_CONTACT_0000_AFM")
    }

    @Test("Transparent Background yields an alpha PNG; default stays opaque white")
    func transparentBackgroundPNG() throws {
        let xs = (0..<10).map(Double.init)
        let payload = HeatmapPlotPayload(
            workflowID: "afm", title: "T", xLabel: "", yLabel: "", zLabel: "",
            grid: HeatmapGrid(xValues: xs, yValues: xs, zMatrix: xs.map { y in xs.map { x in x + y } }),
            hideSpatialAxes: true
        )
        let opaque = try HeatmapRenderPipeline.render(.init(payload: payload)).imageData
        let transparent = try HeatmapRenderPipeline.render(.init(
            payload: payload,
            chartStyle: WorkbenchChartStyle.from(styleParams: ["transparentBackground": "true"])
        )).imageData
        #expect(firstPixelAlpha(opaque) == 255)
        #expect(firstPixelAlpha(transparent) == 0)
        #expect(WorkbenchChartStyle.isGlobalPlotDefaultKey("transparentBackground"))
    }

    @MainActor
    @Test("AFM settings survive switching to another file; typed title does not leak to the new file")
    func settingsPersistAcrossFiles() async throws {
        let first = try writeFixture(named: "FileA.ibw")
        let second = try writeFixture(named: "FileB.ibw")
        let store = AFMWorkspaceStore(workflowID: "afm")

        await analyze(store, first)
        #expect(store.parsedDataset?.title == "FileA")

        store.updateSurfaceLevel(.robustPlane)
        store.updateLineFlattenOrder(.order2)
        store.updateZeroReference(.minimum)
        store.updateScaleBar(AFMScaleBarSetting(mode: .manual, manualLengthMicrometers: 0.5, color: .black))
        store.updateHeatmapShowColorbar(false)
        store.updateHeatmapZDomainState(HeatmapZDomainState(mode: .percentile, percentilePreset: .p1_99))
        store.updateHeatmapTitle("My custom title")

        await analyze(store, second)

        #expect(store.parsedDataset?.title == "FileB")
        #expect(store.processingConfiguration.surfaceLevel == .robustPlane)
        #expect(store.processingConfiguration.lineFlattenOrder == .order2)
        #expect(store.processingConfiguration.zeroReference == .minimum)
        #expect(store.scaleBar == AFMScaleBarSetting(mode: .manual, manualLengthMicrometers: 0.5, color: .black))
        #expect(store.heatmapDisplayState.showColorbar == false)
        #expect(store.heatmapDisplayState.zDomainState == HeatmapZDomainState(mode: .percentile, percentilePreset: .p1_99))
        #expect(store.heatmapDisplayState.titleOverride.isEmpty, "a typed title belongs to its own file")
    }

    @MainActor
    @Test("a typed title survives control-driven redraws of the same file")
    func typedTitleSurvivesRedraw() async throws {
        let url = try writeFixture(named: "FileC.ibw")
        let store = AFMWorkspaceStore(workflowID: "afm")
        await analyze(store, url)
        store.updateHeatmapTitle("Keep me")
        store.updateSurfaceLevel(.plane)
        await analyze(store, url)
        #expect(store.heatmapDisplayState.titleOverride == "Keep me")
    }
}
