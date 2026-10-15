import Foundation
import Testing
@testable import SpinLabApp

@Suite("AFM V1 closure")
struct AFMV1ClosureTests {

    private func decodeConfig(_ json: String) throws -> AFMProcessingConfiguration {
        try JSONDecoder().decode(AFMProcessingConfiguration.self, from: Data(json.utf8))
    }

    @Test("legacy planeLevelEnabled=true decodes to Surface Level Plane")
    func legacyPlaneTrue() throws {
        let c = try decodeConfig(#"{"activeChannelID":"a","planeLevelEnabled":true,"lineFlattenOrder":"order1","zeroReference":"mean"}"#)
        #expect(c.surfaceLevel == .plane)
        #expect(c.lineFlattenOrder == .order1)
        #expect(c.zeroReference == .mean)
    }

    @Test("legacy planeLevelEnabled=false and missing key decode to Off")
    func legacyPlaneFalseOrMissing() throws {
        #expect(try decodeConfig(#"{"activeChannelID":"a","planeLevelEnabled":false}"#).surfaceLevel == .off)
        #expect(try decodeConfig(#"{"activeChannelID":"a"}"#).surfaceLevel == .off)
    }

    @Test("new surfaceLevel key wins and round-trips without the legacy key")
    func newKeyRoundTrip() throws {
        var c = AFMProcessingConfiguration(activeChannelID: "a")
        c.surfaceLevel = .plane
        let data = try JSONEncoder().encode(c)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("planeLevelEnabled"))
        #expect(try JSONDecoder().decode(AFMProcessingConfiguration.self, from: data) == c)
        let both = try decodeConfig(#"{"activeChannelID":"a","surfaceLevel":"off","planeLevelEnabled":true}"#)
        #expect(both.surfaceLevel == .off)
    }

    @Test("repeated Surface Level switching never accumulates: result depends only on the final setting")
    func switchingIsNonCompounding() {
        let xs = (0..<8).map(Double.init), ys = (0..<8).map(Double.init)
        let values = ys.map { y in xs.map { x in 3 + 0.5 * x - 0.25 * y + (x == 3 && y == 4 ? 2 : 0) } }
        let channel = CanonicalAFMChannel(
            id: "c", sourceIndex: 0, sourceLabel: "HeightRetrace", semanticTypeRaw: "Height",
            displayLabel: "Height", values: values, canonicalUnit: "nm", sourceUnit: "m",
            provenance: AFMChannelProvenance(planefit: nil, planefitOrder: nil, flattenOrder: nil, planefitOffset: nil, planefitXSlope: nil, planefitYSlope: nil)
        )
        func run(_ level: AFMSurfaceLevel) -> [[Double]] {
            var cfg = AFMProcessingConfiguration(activeChannelID: "c"); cfg.surfaceLevel = level
            return AFMProcessingPipeline.process(channel: channel, xCoordinates: xs, yCoordinates: ys, configuration: cfg).values
        }
        let first = run(.plane)
        for level in [AFMSurfaceLevel.off, .plane, .off, .plane] { _ = run(level) }
        #expect(run(.plane) == first)
        #expect(run(.off) == values)
        #expect(channel.values == values)
    }

    @Test("auto scale bar picks a 1/2/5 length within 25% of the scan")
    func autoLength() {
        #expect(AFMScaleBarSetting.autoLengthMicrometers(scanWidthMicrometers: 10) == 2)
        #expect(AFMScaleBarSetting.autoLengthMicrometers(scanWidthMicrometers: 20) == 5)
        #expect(AFMScaleBarSetting.autoLengthMicrometers(scanWidthMicrometers: 1) == 0.2)
        #expect(AFMScaleBarSetting.label(forMicrometers: 0.2) == "200 nm")
        #expect(AFMScaleBarSetting.label(forMicrometers: 2) == "2 μm")
    }

    @Test("scale bar pixel length equals physical length / real scan width × drawn grid width")
    func scaleBarMatchesPhysicalScale() throws {
        // 10 µm scan: 100 columns at 0.1 µm pitch → coordinates 0…9.9, drawn width 10 µm.
        let n = 100
        let xs = (0..<n).map { Double($0) * 0.1 }, ys = (0..<n).map { Double($0) * 0.1 }
        let grid = HeatmapGrid(xValues: xs, yValues: ys, zMatrix: ys.map { _ in xs.map { $0 } })
        let rect = CGRect(x: 10, y: 10, width: 500, height: 500)
        let overlay = AFMScaleBarSetting(mode: .manual, manualLengthMicrometers: 2).overlay(scanWidthMicrometers: AFMHeatmapPayloadBuilder.scanWidthMicrometers(xs)!)
        let resolved = try #require(HeatmapPlotLayout.resolveScaleBar(overlay, grid: grid, gridRect: rect))
        #expect(abs(Double(resolved.lengthInPoints) - 100) < 1e-6)   // 2 μm of 10 µm × 500 pt
        #expect(resolved.label == "2 μm")
    }

    @Test("off, oversized and non-positive scale bars produce no overlay")
    func scaleBarSuppressed() {
        #expect(AFMScaleBarSetting(mode: .off).overlay(scanWidthMicrometers: 10) == nil)
        #expect(AFMScaleBarSetting(mode: .manual, manualLengthMicrometers: 50).overlay(scanWidthMicrometers: 10) == nil)
        #expect(AFMScaleBarSetting(mode: .manual, manualLengthMicrometers: 0).overlay(scanWidthMicrometers: 10) == nil)
    }

    @Test("old pack state without scaleBar decodes to Auto")
    func oldPackStateDefaults() throws {
        let state = try JSONDecoder().decode(AFMPackState.self, from: Data(#"{"processingConfiguration":{"activeChannelID":"a","planeLevelEnabled":true}}"#.utf8))
        #expect(state.scaleBar.mode == .auto)
        #expect(state.processingConfiguration.surfaceLevel == .plane)
    }

    @Test("AFM defaults: P5–P99 percentile range and warm Gwyddion palette")
    @MainActor func afmDefaults() {
        let store = AFMWorkspaceStore(workflowID: "afm")
        #expect(store.heatmapDisplayState.zDomainState.mode == .percentile)
        #expect(store.heatmapDisplayState.zDomainState.percentilePreset == .p5_99)
        #expect(AFMHeatmapPayloadBuilder.Options(workflowID: "afm").colormapKey == "gwyddionWarm")
    }
}
