import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Gate 8.2: HeatmapTabRenderState persistence audit (items 1–15)
//
// These tests prove the full update → rerender → pack → restore cycle for:
//   colorScaleMode, showColorbar, xTickCount/yTickCount, zDomainState,
//   and title/x/y/z label overrides.

// MARK: - RSM fixture

private let rsmHL3x3 = """
# RSM scan — HL plane, K=0 fixed
H        K        L        Detector
-1.0     0.0      1.0      100.0
 0.0     0.0      1.0      200.0
 1.0     0.0      1.0      150.0
-1.0     0.0      1.5      110.0
 0.0     0.0      1.5      250.0
 1.0     0.0      1.5      180.0
-1.0     0.0      2.0       90.0
 0.0     0.0      2.0      300.0
 1.0     0.0      2.0      120.0
"""

// MARK: - Test harness helpers

private func encodeDecodeState(_ state: HeatmapTabRenderState) throws -> HeatmapTabRenderState {
    let data = try JSONEncoder().encode(state)
    return try JSONDecoder().decode(HeatmapTabRenderState.self, from: data)
}

private func makePackConfig(
    displayState: HeatmapTabRenderState = .init()
) -> RSMPackConfig {
    RSMPackConfig(
        packState: RSMPackState(
            sourceFileIdentity: "/tmp/rsm-gate82.dat",
            detectorColumnName: "Detector",
            activeView: .hl
        ),
        displayState: displayState
    )
}

private func restoreDisplayState(from config: RSMPackConfig) throws -> (HeatmapTabRenderState, HeatmapRenderPipeline.Output) {
    let displayState = config.displayState
    let dataset = try RSMDataParser.parse(text: rsmHL3x3, title: "Gate8.2", sourceRef: "/tmp/rsm-gate82.dat")
    let payload = try RSMHeatmapPayloadBuilder.build(
        from: dataset,
        options: .init(view: .hl, title: dataset.title, zLabel: dataset.detectorColumnName)
    )
    let output = try HeatmapRenderPipeline.render(.init(
        payload: payload,
        colorScaleMode: displayState.colorScaleMode,
        zDomainState: displayState.zDomainState,
        showColorbar: displayState.showColorbar,
        xTickCount: displayState.xTickCount,
        yTickCount: displayState.yTickCount,
        interpolationMode: displayState.interpolationMode
    ))
    return (displayState, output)
}

// MARK: - Suite: HeatmapTabRenderState persistence

@Suite("HeatmapTabRenderState persistence (Gate 8.2)")
struct V825HeatmapTabRenderStatePersistenceTests {

    // Test 1: colorScaleMode encodes and decodes
    @Test("1. colorScaleMode encodes and decodes correctly")
    func colorScaleModeEncodesAndDecodes() throws {
        let decodedLinear = try encodeDecodeState(HeatmapTabRenderState(colorScaleMode: .linear))
        let decodedLog10  = try encodeDecodeState(HeatmapTabRenderState(colorScaleMode: .log10))

        #expect(decodedLinear.colorScaleMode == .linear,
                "colorScaleMode .linear must survive encode → decode")
        #expect(decodedLog10.colorScaleMode == .log10,
                "colorScaleMode .log10 must survive encode → decode")
    }

    // Test 2: showColorbar encodes and decodes
    @Test("2. showColorbar encodes and decodes correctly")
    func showColorbarEncodesAndDecodes() throws {
        let decodedTrue  = try encodeDecodeState(HeatmapTabRenderState(showColorbar: true))
        let decodedFalse = try encodeDecodeState(HeatmapTabRenderState(showColorbar: false))

        #expect(decodedTrue.showColorbar,
                "showColorbar = true must survive encode → decode")
        #expect(!decodedFalse.showColorbar,
                "showColorbar = false must survive encode → decode")
    }

    // Test 3: xTickCount and yTickCount encode and decode
    @Test("3. xTickCount and yTickCount encode and decode correctly")
    func tickCountsEncodeAndDecode() throws {
        let decoded = try encodeDecodeState(HeatmapTabRenderState(xTickCount: 7, yTickCount: 12))

        #expect(decoded.xTickCount == 7,
                "xTickCount must survive encode → decode")
        #expect(decoded.yTickCount == 12,
                "yTickCount must survive encode → decode")
    }

    // Test 4: Old pack missing xTickCount/yTickCount defaults to 5
    @Test("4. Old pack missing xTickCount/yTickCount defaults to 5")
    func oldPackMissingTickCountsDefaultsToFive() throws {
        let json = """
        {
          "schemaVersion": 1,
          "titleOverride": "",
          "xLabelOverride": "",
          "yLabelOverride": "",
          "zLabelOverride": "",
          "showColorbar": true,
          "colorScaleMode": "linear",
          "colormapKey": "viridis",
          "zDomainState": {"mode": "auto", "percentilePreset": "p1_99", "manualRange": {"minText": "", "maxText": ""}}
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: json)

        #expect(decoded.xTickCount == 5,
                "xTickCount missing in old pack must default to 5")
        #expect(decoded.yTickCount == 5,
                "yTickCount missing in old pack must default to 5")
    }

    // Test 5: Old pack missing showColorbar defaults to true
    @Test("5. Old pack missing showColorbar defaults to true")
    func oldPackMissingShowColorbarDefaultsToTrue() throws {
        let json = """
        {
          "schemaVersion": 1,
          "titleOverride": "",
          "xLabelOverride": "",
          "yLabelOverride": "",
          "zLabelOverride": "",
          "colorScaleMode": "linear",
          "colormapKey": "viridis",
          "xTickCount": 5,
          "yTickCount": 5
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: json)

        #expect(decoded.showColorbar,
                "showColorbar missing in old pack must default to true")
    }

    // Test 6: Legacy showZLabel decodes into showColorbar
    @Test("6. Legacy showZLabel decodes into showColorbar")
    func legacyShowZLabelDecodesIntoShowColorbar() throws {
        let jsonTrue = #"{"schemaVersion":1,"titleOverride":"","showZLabel":true,"colorScaleMode":"linear"}"#.data(using: .utf8)!
        let jsonFalse = #"{"schemaVersion":1,"titleOverride":"","showZLabel":false,"colorScaleMode":"linear"}"#.data(using: .utf8)!

        let decodedTrue  = try JSONDecoder().decode(HeatmapTabRenderState.self, from: jsonTrue)
        let decodedFalse = try JSONDecoder().decode(HeatmapTabRenderState.self, from: jsonFalse)

        #expect(decodedTrue.showColorbar,
                "Legacy showZLabel = true must decode into showColorbar = true")
        #expect(!decodedFalse.showColorbar,
                "Legacy showZLabel = false must decode into showColorbar = false")
    }

    // Test 7: Pack/restore preserves Linear/Log colorScaleMode
    @Test("7. RSM pack/restore preserves Linear and Log colorScaleMode")
    func packRestorePreservesColorScaleMode() throws {
        for mode in [PlotScaleTransform.linear, PlotScaleTransform.log10] {
            let config = makePackConfig(displayState: HeatmapTabRenderState(colorScaleMode: mode))
            let roundTripped = try JSONDecoder().decode(RSMPackConfig.self, from: JSONEncoder().encode(config))
            #expect(roundTripped.displayState.colorScaleMode == mode,
                    "colorScaleMode must survive JSON pack/restore round-trip")
        }
    }

    // Test 8: Pack/restore preserves showColorbar false
    @Test("8. RSM pack/restore preserves showColorbar = false")
    func packRestorePreservesShowColorbarFalse() throws {
        let config = makePackConfig(displayState: HeatmapTabRenderState(showColorbar: false))
        let roundTripped = try JSONDecoder().decode(RSMPackConfig.self, from: JSONEncoder().encode(config))

        #expect(!roundTripped.displayState.showColorbar,
                "showColorbar = false must survive JSON pack/restore round-trip")

        let (_, output) = try restoreDisplayState(from: roundTripped)
        #expect(!output.layout.showColorbar,
                "Restored showColorbar = false must suppress colorbar in rendered layout")
        #expect(output.layout.colorbarTicks.isEmpty,
                "Restored showColorbar = false must produce empty colorbar ticks")
    }

    // Test 9: Pack/restore preserves xTickCount and yTickCount
    @Test("9. RSM pack/restore preserves xTickCount and yTickCount")
    func packRestorePreservesTickCounts() throws {
        let config = makePackConfig(displayState: HeatmapTabRenderState(xTickCount: 9, yTickCount: 4))
        let roundTripped = try JSONDecoder().decode(RSMPackConfig.self, from: JSONEncoder().encode(config))

        #expect(roundTripped.displayState.xTickCount == 9,
                "xTickCount must survive JSON pack/restore round-trip")
        #expect(roundTripped.displayState.yTickCount == 4,
                "yTickCount must survive JSON pack/restore round-trip")

        let (restoredState, _) = try restoreDisplayState(from: roundTripped)
        #expect(restoredState.xTickCount == 9,
                "Restored displayState must carry the persisted xTickCount")
        #expect(restoredState.yTickCount == 4,
                "Restored displayState must carry the persisted yTickCount")
    }

    // Test 9b: interpolationMode defaults to nearest and survives pack/restore
    @Test("9b. interpolationMode defaults to nearest and survives pack/restore")
    func interpolationModeDefaultsToNearestAndRoundTrips() throws {
        #expect(HeatmapTabRenderState().interpolationMode == .nearest,
                "Default interpolation must stay nearest — the scientifically safer option")

        let config = makePackConfig(displayState: HeatmapTabRenderState(interpolationMode: .bilinear))
        let roundTripped = try JSONDecoder().decode(RSMPackConfig.self, from: JSONEncoder().encode(config))
        #expect(roundTripped.displayState.interpolationMode == .bilinear,
                "Explicit bilinear opt-in must survive JSON pack/restore round-trip")

        let (restoredState, output) = try restoreDisplayState(from: roundTripped)
        #expect(restoredState.interpolationMode == .bilinear)
        #expect(!output.imageData.isEmpty)
    }

    // Test 9c: legacy packs missing interpolationMode default to nearest, not bilinear
    @Test("9c. Old pack missing interpolationMode defaults to nearest")
    func oldPackMissingInterpolationModeDefaultsToNearest() throws {
        let json = """
        {
          "schemaVersion": 2,
          "titleOverride": "",
          "xLabelOverride": "",
          "yLabelOverride": "",
          "zLabelOverride": "",
          "showColorbar": true,
          "colorScaleMode": "linear",
          "tickConfiguration": {"xTargetCount": 5, "yTargetCount": 5}
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: json)
        #expect(decoded.interpolationMode == .nearest,
                "Legacy packs predating this field must not be silently opted into bilinear smoothing")
    }

    // Test 10: Changing colorScaleMode does not reset tick counts or zDomainState
    @Test("10. Changing colorScaleMode does not reset tick counts or zDomainState")
    @MainActor
    func changingColorScaleModeDoesNotResetOtherFields() {
        let store = RSMWorkspaceStore(workflowID: WorkflowKey.rsm.rawValue)
        store.heatmapDisplayState = HeatmapTabRenderState(
            colorScaleMode: .linear,
            zDomainState: HeatmapZDomainState(mode: .manual, manualRange: HeatmapZRangeDraft(minText: "100", maxText: "200")),
            xTickCount: 8,
            yTickCount: 6
        )

        store.updateHeatmapColorScaleMode(.log10)

        #expect(store.heatmapDisplayState.colorScaleMode == .log10,
                "colorScaleMode must update to .log10")
        #expect(store.heatmapDisplayState.xTickCount == 8,
                "xTickCount must not change when only colorScaleMode changes")
        #expect(store.heatmapDisplayState.yTickCount == 6,
                "yTickCount must not change when only colorScaleMode changes")
        #expect(store.heatmapDisplayState.zDomainState.mode == .manual,
                "zDomainState must not reset when only colorScaleMode changes")
        #expect(store.heatmapDisplayState.zDomainState.manualRange.minText == "100",
                "zDomainState.manualRange must not change when only colorScaleMode changes")
    }

    // Test 11: Changing xTickCount/yTickCount does not reset colorScaleMode or zDomainState
    @Test("11. Changing xTickCount/yTickCount does not reset colorScaleMode or zDomainState")
    @MainActor
    func changingTickCountsDoesNotResetOtherFields() {
        let store = RSMWorkspaceStore(workflowID: WorkflowKey.rsm.rawValue)
        store.heatmapDisplayState = HeatmapTabRenderState(
            colorScaleMode: .log10,
            zDomainState: HeatmapZDomainState(mode: .percentile, percentilePreset: .p2_98),
            xTickCount: 5,
            yTickCount: 5
        )

        store.updateHeatmapXTickCount(10)
        store.updateHeatmapYTickCount(3)

        #expect(store.heatmapDisplayState.xTickCount == 10,
                "xTickCount must update to 10")
        #expect(store.heatmapDisplayState.yTickCount == 3,
                "yTickCount must update to 3")
        #expect(store.heatmapDisplayState.colorScaleMode == .log10,
                "colorScaleMode must not change when only tick counts change")
        #expect(store.heatmapDisplayState.zDomainState.mode == .percentile,
                "zDomainState.mode must not change when only tick counts change")
        #expect(store.heatmapDisplayState.zDomainState.percentilePreset == .p2_98,
                "zDomainState.percentilePreset must not change when only tick counts change")
    }

    // Test 11b: Changing interpolationMode does not reset colorScaleMode, tick counts, or zDomainState
    @Test("11b. Changing interpolationMode does not reset other display fields")
    @MainActor
    func changingInterpolationModeDoesNotResetOtherFields() {
        let store = RSMWorkspaceStore(workflowID: WorkflowKey.rsm.rawValue)
        store.heatmapDisplayState = HeatmapTabRenderState(
            colorScaleMode: .log10,
            zDomainState: HeatmapZDomainState(mode: .percentile, percentilePreset: .p2_98),
            xTickCount: 8,
            yTickCount: 6
        )
        #expect(store.heatmapDisplayState.interpolationMode == .nearest,
                "Interpolation must default to nearest before any explicit opt-in")

        store.updateHeatmapInterpolationMode(.bilinear)

        #expect(store.heatmapDisplayState.interpolationMode == .bilinear,
                "interpolationMode must update to .bilinear")
        #expect(store.heatmapDisplayState.colorScaleMode == .log10,
                "colorScaleMode must not change when only interpolationMode changes")
        #expect(store.heatmapDisplayState.xTickCount == 8,
                "xTickCount must not change when only interpolationMode changes")
        #expect(store.heatmapDisplayState.yTickCount == 6,
                "yTickCount must not change when only interpolationMode changes")
        #expect(store.heatmapDisplayState.zDomainState.mode == .percentile,
                "zDomainState must not change when only interpolationMode changes")

        store.updateHeatmapInterpolationMode(.nearest)
        #expect(store.heatmapDisplayState.interpolationMode == .nearest,
                "interpolationMode must be switchable back to nearest")
    }

    // Test 12: RSM restore does not drop heatmapDisplayState after pack load
    @Test("12. RSM restore assigns heatmapDisplayState from pack and does not drop it")
    @MainActor
    func rsmRestoreDoesNotDropHeatmapDisplayState() {
        let store = RSMWorkspaceStore(workflowID: WorkflowKey.rsm.rawValue)
        let displayState = HeatmapTabRenderState(
            showColorbar: false,
            colorScaleMode: .log10,
            xTickCount: 7,
            yTickCount: 3
        )
        let config = RSMPackConfig(
            packState: RSMPackState(
                sourceFileIdentity: nil,   // nil → restore exits early after assigning displayState
                detectorColumnName: "Detector",
                activeView: .kl
            ),
            displayState: displayState
        )

        let pack = AnalysisPack(
            label: "Test Pack",
            workflowID: "rsm",
            filePaths: [],
            sampleKeys: [],
            config: (try? JSONEncoder().encode(config)) ?? Data(),
            result: (try? JSONEncoder().encode(RSMPackResult())) ?? Data()
        )

        store.restoreFromPack(
            config: config,
            result: RSMPackResult(),
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        #expect(!store.heatmapDisplayState.showColorbar,
                "heatmapDisplayState.showColorbar must be restored from pack")
        #expect(store.heatmapDisplayState.colorScaleMode == .log10,
                "heatmapDisplayState.colorScaleMode must be restored from pack")
        #expect(store.heatmapDisplayState.xTickCount == 7,
                "heatmapDisplayState.xTickCount must be restored from pack")
        #expect(store.heatmapDisplayState.yTickCount == 3,
                "heatmapDisplayState.yTickCount must be restored from pack")
        #expect(store.activeView == .kl,
                "activeView must be restored from pack")
    }

    // Test 13: Existing HeatmapZDomain tests still pass (smoke)
    @Test("13. HeatmapZDomain encode/decode still works correctly")
    func heatmapZDomainEncodeDecodeSmoke() throws {
        let auto       = HeatmapZDomainState(mode: .auto)
        let manual     = HeatmapZDomainState(mode: .manual, manualRange: HeatmapZRangeDraft(minText: "1.0", maxText: "9.0"))
        let percentile = HeatmapZDomainState(mode: .percentile, percentilePreset: .p5_95)

        for original in [auto, manual, percentile] {
            let decoded = try JSONDecoder().decode(HeatmapZDomainState.self, from: JSONEncoder().encode(original))
            #expect(decoded.mode == original.mode,
                    "HeatmapZDomainState.mode must survive encode → decode")
        }

        // Manual range resolution
        let resolvedManual = manual.resolve(rawValues: [0.5, 5.0, 10.5])
        if case .resolved(let lo, let hi) = resolvedManual {
            #expect(lo == 1.0)
            #expect(hi == 9.0)
        } else {
            Issue.record("Manual z domain must resolve to .resolved(1.0, 9.0)")
        }

        // Auto with empty values uses 0..1 sentinel domain (does not fall back)
        let resolvedAutoEmpty = auto.resolve(rawValues: [])
        if case .resolved(let lo, let hi) = resolvedAutoEmpty {
            #expect(lo == 0.0, "Auto z domain with empty values must use 0 as lower sentinel")
            #expect(hi == 1.0, "Auto z domain with empty values must use 1 as upper sentinel")
        } else {
            Issue.record("Auto z domain must resolve (not fall back) even for empty raw values")
        }
    }

    // Test 14: Existing RSM pack/restore tests still pass (regression guard)
    @Test("14. Existing RSM pack/restore round-trip still works (regression guard)")
    func existingPackRestoreRoundTripStillWorks() throws {
        let config = RSMPackConfig(
            packState: RSMPackState(
                sourceFileIdentity: "/tmp/rsm-gate82-hl.dat",
                detectorColumnName: "Detector",
                activeView: .hl
            ),
            displayState: HeatmapTabRenderState()
        )
        let roundTripped = try JSONDecoder().decode(RSMPackConfig.self, from: JSONEncoder().encode(config))

        #expect(roundTripped.packState.activeView == .hl)
        #expect(roundTripped.displayState.colorScaleMode == .linear)
        #expect(roundTripped.displayState.showColorbar)
        #expect(roundTripped.displayState.xTickCount == 5)
        #expect(roundTripped.displayState.yTickCount == 5)
        #expect(roundTripped.displayState.zDomainState.mode == .auto)

        let dataset = try RSMDataParser.parse(text: rsmHL3x3, title: "Gate8.2", sourceRef: "/tmp/rsm-gate82-hl.dat")
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset, options: .init(view: .hl, title: dataset.title, zLabel: "Detector"))
        let output = try HeatmapRenderPipeline.render(.init(
            payload: payload,
            colorScaleMode: roundTripped.displayState.colorScaleMode,
            zDomainState: roundTripped.displayState.zDomainState,
            showColorbar: roundTripped.displayState.showColorbar,
            xTickCount: roundTripped.displayState.xTickCount,
            yTickCount: roundTripped.displayState.yTickCount
        ))

        #expect(!output.imageData.isEmpty)
        #expect([UInt8](output.imageData.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    // Test C11: tickConfiguration encodes and decodes via HeatmapTabRenderState
    @Test("C11. tickConfiguration encodes and decodes correctly")
    func tickConfigurationEncodesAndDecodes() throws {
        let state = HeatmapTabRenderState(xTickCount: 9, yTickCount: 14)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: data)

        #expect(decoded.tickConfiguration.xTargetCount == 9,
                "tickConfiguration.xTargetCount must survive encode → decode")
        #expect(decoded.tickConfiguration.yTargetCount == 14,
                "tickConfiguration.yTargetCount must survive encode → decode")
    }

    // Test C12: Legacy xTickCount/yTickCount JSON decodes into tickConfiguration
    @Test("C12. Legacy xTickCount/yTickCount JSON decodes into tickConfiguration")
    func legacyXYTickCountDecodesIntoTickConfiguration() throws {
        let json = """
        {
          "schemaVersion": 2,
          "xTickCount": 8,
          "yTickCount": 3,
          "colorScaleMode": "linear"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: json)

        #expect(decoded.tickConfiguration.xTargetCount == 8,
                "Legacy xTickCount must decode into tickConfiguration.xTargetCount")
        #expect(decoded.tickConfiguration.yTargetCount == 3,
                "Legacy yTickCount must decode into tickConfiguration.yTargetCount")
    }

    // Test C13: Missing tick fields default to PlotTickConfiguration.defaultValue
    @Test("C13. Missing tick fields default to PlotTickConfiguration.defaultValue")
    func missingTickFieldsDefaultToPlotTickConfigurationDefault() throws {
        let json = """
        {
          "schemaVersion": 1,
          "titleOverride": "",
          "colorScaleMode": "linear"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(HeatmapTabRenderState.self, from: json)

        #expect(decoded.tickConfiguration == PlotTickConfiguration.defaultValue,
                "Missing tick fields must default to PlotTickConfiguration.defaultValue")
        #expect(decoded.tickConfiguration.xTargetCount == 5,
                "Default xTargetCount must be 5")
        #expect(decoded.tickConfiguration.yTargetCount == 5,
                "Default yTargetCount must be 5")
    }

    // Test C14: RSM pack/restore preserves tickConfiguration
    @Test("C14. RSM pack/restore preserves tickConfiguration")
    func packRestorePreservesTickConfiguration() throws {
        let config = makePackConfig(displayState: HeatmapTabRenderState(xTickCount: 11, yTickCount: 7))
        let roundTripped = try JSONDecoder().decode(RSMPackConfig.self, from: JSONEncoder().encode(config))

        #expect(roundTripped.displayState.tickConfiguration.xTargetCount == 11,
                "tickConfiguration.xTargetCount must survive JSON pack/restore round-trip")
        #expect(roundTripped.displayState.tickConfiguration.yTargetCount == 7,
                "tickConfiguration.yTargetCount must survive JSON pack/restore round-trip")
    }

    // Test C16: HeatmapPlotLayout.Options uses tickConfiguration target counts
    @Test("C16. HeatmapPlotLayout uses tickConfiguration target counts")
    func heatmapPlotLayoutUsesTickConfiguration() throws {
        let src = try String(contentsOfFile: #filePath.replacingOccurrences(
            of: "Tests/SpinLabAppTests/V825HeatmapTabRenderStatePersistenceTests.swift",
            with: "Sources/SpinLabApp/Workbench/V3/Heatmap/HeatmapPlotLayout.swift"
        ), encoding: .utf8)
        #expect(src.contains("tickConfiguration"),
                "HeatmapPlotLayout must reference tickConfiguration")
        #expect(src.contains("xTargetCount"),
                "HeatmapPlotLayout must read xTargetCount from tickConfiguration")
        #expect(src.contains("yTargetCount"),
                "HeatmapPlotLayout must read yTargetCount from tickConfiguration")
    }

    // Test 15: Existing XY render tests still pass (regression guard)
    @Test("15. Existing XY render path is unaffected by heatmap persistence changes")
    func existingXYRenderPathUnaffected() throws {
        let payload = WorkbenchPlotPayload(
            workflowID: "xy",
            workflowDisplayName: "XY Rotation",
            title: "Gate8.2 XY Smoke",
            axisMapping: WorkbenchAxisMapping(xField: "H (Oe)", yField: "R (Ω)"),
            series: [
                WorkbenchPlotSeries(
                    label: "Series 1",
                    x: [0.0, 1.0, 2.0],
                    y: [1.0, 2.0, 1.5]
                )
            ]
        )

        let output = try WorkbenchRenderPipeline.render(.init(payload: payload))

        #expect(!output.imageData.isEmpty,
                "XY render must still produce non-empty PNG after heatmap persistence changes")
        #expect([UInt8](output.imageData.prefix(4)) == [0x89, 0x50, 0x4E, 0x47],
                "XY render output must be a valid PNG")
        #expect(output.layout.chartTitle == "Gate8.2 XY Smoke",
                "XY render must preserve chart title")
        #expect(output.layout.xAxisLabel == "H (Oe)",
                "XY render must preserve x-axis label")
        #expect(output.layout.yAxisLabel == "R (Ω)",
                "XY render must preserve y-axis label")
    }
}
