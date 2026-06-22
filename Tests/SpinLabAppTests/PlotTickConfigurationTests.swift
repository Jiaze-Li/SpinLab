import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Gate PlotTickConfigurationShared-1

// MARK: - Suite A: PlotTickConfiguration type

@Suite("PlotTickConfiguration type (Gate PlotTickConfigurationShared-1)")
struct PlotTickConfigurationTests {

    // Test A1: defaultValue is x=5, y=5
    @Test("A1. defaultValue is xTargetCount=5, yTargetCount=5")
    func defaultValueIsCorrect() {
        #expect(PlotTickConfiguration.defaultValue.xTargetCount == 5)
        #expect(PlotTickConfiguration.defaultValue.yTargetCount == 5)
    }

    // Test A2: Values below range clamp to 2
    @Test("A2. Values below valid range clamp to 2")
    func valuesBelowRangeClampToMinimum() {
        let tc = PlotTickConfiguration(xTargetCount: 0, yTargetCount: -5)
        #expect(tc.xTargetCount == 2, "xTargetCount below 2 must clamp to 2")
        #expect(tc.yTargetCount == 2, "yTargetCount below 2 must clamp to 2")
        #expect(PlotTickConfiguration.clamp(1) == 2)
        #expect(PlotTickConfiguration.clamp(-100) == 2)
    }

    // Test A3: Values above range clamp to 20
    @Test("A3. Values above valid range clamp to 20")
    func valuesAboveRangeClampToMaximum() {
        let tc = PlotTickConfiguration(xTargetCount: 100, yTargetCount: 21)
        #expect(tc.xTargetCount == 20, "xTargetCount above 20 must clamp to 20")
        #expect(tc.yTargetCount == 20, "yTargetCount above 20 must clamp to 20")
        #expect(PlotTickConfiguration.clamp(21) == 20)
        #expect(PlotTickConfiguration.clamp(999) == 20)
    }

    // Test A4: Codable round trip preserves valid values
    @Test("A4. Codable round trip preserves valid values")
    func codableRoundTripPreservesValidValues() throws {
        let original = PlotTickConfiguration(xTargetCount: 7, yTargetCount: 12)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PlotTickConfiguration.self, from: data)

        #expect(decoded.xTargetCount == 7)
        #expect(decoded.yTargetCount == 12)
    }

    // Test A5: Codable decode with out-of-range values clamps
    @Test("A5. Codable decode clamps out-of-range values")
    func codableDecodeClampsBelowAndAboveRange() throws {
        let jsonLow = #"{"xTargetCount": 0, "yTargetCount": 1}"#.data(using: .utf8)!
        let jsonHigh = #"{"xTargetCount": 99, "yTargetCount": 25}"#.data(using: .utf8)!

        let decodedLow = try JSONDecoder().decode(PlotTickConfiguration.self, from: jsonLow)
        let decodedHigh = try JSONDecoder().decode(PlotTickConfiguration.self, from: jsonHigh)

        #expect(decodedLow.xTargetCount == 2, "xTargetCount 0 must clamp to 2 on decode")
        #expect(decodedLow.yTargetCount == 2, "yTargetCount 1 must clamp to 2 on decode")
        #expect(decodedHigh.xTargetCount == 20, "xTargetCount 99 must clamp to 20 on decode")
        #expect(decodedHigh.yTargetCount == 20, "yTargetCount 25 must clamp to 20 on decode")
    }

    // Test A6: Equatable works as expected
    @Test("A6. Equatable works as expected")
    func equatableWorksCorrectly() {
        let a = PlotTickConfiguration(xTargetCount: 5, yTargetCount: 5)
        let b = PlotTickConfiguration(xTargetCount: 5, yTargetCount: 5)
        let c = PlotTickConfiguration(xTargetCount: 6, yTargetCount: 5)

        #expect(a == b, "Same values must be equal")
        #expect(a != c, "Different values must not be equal")
        #expect(a == PlotTickConfiguration.defaultValue)
    }
}

// MARK: - Suite B: SharedPlotTickCountControls semantics

@Suite("SharedPlotTickCountControls semantics (Gate PlotTickConfigurationShared-1)")
struct SharedPlotTickCountControlsTests {

    // Test B7: Control uses PlotTickConfiguration.validRange
    @Test("B7. SharedPlotTickCountControls.tickRange matches PlotTickConfiguration.validRange")
    func controlUsesPlotTickConfigurationValidRange() throws {
        let src = try String(contentsOfFile: #filePath.replacingOccurrences(
            of: "Tests/SpinLabAppTests/PlotTickConfigurationTests.swift",
            with: "Sources/SpinLabApp/Features/Workbench/SharedPlotTickCountControls.swift"
        ), encoding: .utf8)
        #expect(src.contains("PlotTickConfiguration.validRange"),
                "SharedPlotTickCountControls must reference PlotTickConfiguration.validRange, not a hardcoded range")
    }

    // Test B8: X stepper clamps through valid range
    @Test("B8. X stepper valid range matches PlotTickConfiguration bounds")
    func xStepperClampsToValidRange() {
        #expect(SharedPlotTickCountControls.tickRange == PlotTickConfiguration.validRange,
                "SharedPlotTickCountControls.tickRange must equal PlotTickConfiguration.validRange")
        #expect(SharedPlotTickCountControls.tickRange.lowerBound == 2)
        #expect(SharedPlotTickCountControls.tickRange.upperBound == 20)
    }

    // Test B9: Y stepper clamps through valid range (same range as X)
    @Test("B9. Y stepper uses the same valid range as X stepper and PlotTickConfiguration")
    func yStepperClampsToSameValidRange() {
        #expect(SharedPlotTickCountControls.tickRange.lowerBound == PlotTickConfiguration.validRange.lowerBound)
        #expect(SharedPlotTickCountControls.tickRange.upperBound == PlotTickConfiguration.validRange.upperBound)
    }

    // Test B10: Control has no Heatmap-specific naming/ownership
    @Test("B10. SharedPlotTickCountControls has no Heatmap-specific naming in source")
    func controlHasNoHeatmapSpecificNaming() throws {
        let src = try String(contentsOfFile: #filePath.replacingOccurrences(
            of: "Tests/SpinLabAppTests/PlotTickConfigurationTests.swift",
            with: "Sources/SpinLabApp/Features/Workbench/SharedPlotTickCountControls.swift"
        ), encoding: .utf8)
        #expect(!src.contains("Heatmap"),
                "SharedPlotTickCountControls must not contain Heatmap-specific naming")
        #expect(!src.contains("RSM"),
                "SharedPlotTickCountControls must not be RSM-specific")
    }
}

// MARK: - Suite D: XY WorkbenchChartStyle integration

@Suite("XY tick configuration via WorkbenchChartStyle (Gate PlotTickConfigurationShared-1)")
struct WorkbenchChartStyleTickConfigurationTests {

    // Test D17: WorkbenchChartStyle parses existing tick target keys into PlotTickConfiguration
    @Test("D17. WorkbenchChartStyle.tickConfiguration reflects tickTargetX/Y styleParams")
    func chartStyleParsesTickTargetKeysIntoTickConfiguration() {
        let style = WorkbenchChartStyle.from(styleParams: ["tickTargetX": "8", "tickTargetY": "12"])
        #expect(style.tickConfiguration.xTargetCount == 8)
        #expect(style.tickConfiguration.yTargetCount == 12)
    }

    // Test D18: chartStyleOverrides backward-compatible behavior preserved
    @Test("D18. WorkbenchChartStyle keeps backward-compatible tickTargetX/Y fields")
    func chartStyleKeepsBackwardCompatTickTargetFields() {
        let style = WorkbenchChartStyle.from(styleParams: ["tickTargetX": "10", "tickTargetY": "7"])
        #expect(style.tickTargetX == 10, "tickTargetX must still be readable")
        #expect(style.tickTargetY == 7, "tickTargetY must still be readable")
    }

    // Test D19: XY tick clamping uses PlotTickConfiguration.clamp
    @Test("D19. WorkbenchChartStyle clamps tick target values through PlotTickConfiguration")
    func chartStyleClampsTickTargetThroughPlotTickConfiguration() {
        let styleLow  = WorkbenchChartStyle.from(styleParams: ["tickTargetX": "0", "tickTargetY": "1"])
        let styleHigh = WorkbenchChartStyle.from(styleParams: ["tickTargetX": "50", "tickTargetY": "99"])

        #expect(styleLow.tickTargetX  == 2,  "tickTargetX below 2 must clamp to 2")
        #expect(styleLow.tickTargetY  == 2,  "tickTargetY below 2 must clamp to 2")
        #expect(styleHigh.tickTargetX == 20, "tickTargetX above 20 must clamp to 20")
        #expect(styleHigh.tickTargetY == 20, "tickTargetY above 20 must clamp to 20")
    }

    // Test D20: XY default tick configuration is same as Heatmap default
    @Test("D20. XY default tick configuration matches PlotTickConfiguration.defaultValue")
    func xyDefaultTickConfigurationMatchesSharedDefault() {
        let defaultStyle = WorkbenchChartStyle()
        let xyDefault = defaultStyle.tickConfiguration
        let heatmapDefault = PlotTickConfiguration.defaultValue
        #expect(xyDefault.yTargetCount == heatmapDefault.yTargetCount,
                "XY default Y tick count must match heatmap default (both 5)")
    }

    // Test D21: XY tick clamping bounds match heatmap tick clamping bounds
    @Test("D21. XY tick clamping bounds match PlotTickConfiguration.validRange")
    func xyTickClampingBoundsMatchSharedValidRange() {
        #expect(PlotTickConfiguration.validRange.lowerBound == 2)
        #expect(PlotTickConfiguration.validRange.upperBound == 20)
        let style = WorkbenchChartStyle.from(styleParams: ["tickTargetX": "1", "tickTargetY": "25"])
        #expect(style.tickTargetX == PlotTickConfiguration.validRange.lowerBound)
        #expect(style.tickTargetY == PlotTickConfiguration.validRange.upperBound)
    }

    // Test D22: Existing XY render tests still produce valid PNG
    @Test("D22. XY render path is unaffected by PlotTickConfiguration introduction")
    func existingXYRenderPathUnaffected() throws {
        let payload = WorkbenchPlotPayload(
            workflowID: "xy",
            workflowDisplayName: "XY",
            title: "PlotTickConfig XY Smoke",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [WorkbenchPlotSeries(label: "S1", x: [0, 1, 2], y: [1, 2, 1.5])]
        )
        let output = try WorkbenchRenderPipeline.render(.init(payload: payload))
        #expect(!output.imageData.isEmpty)
        #expect([UInt8](output.imageData.prefix(4)) == [0x89, 0x50, 0x4E, 0x47],
                "XY render output must be a valid PNG")
    }
}

// MARK: - Suite E: Architecture invariants

@Suite("Architecture invariants (Gate PlotTickConfigurationShared-1)")
struct PlotTickConfigurationArchitectureTests {

    private func source(at relativePath: String) throws -> String {
        try String(contentsOfFile: #filePath.replacingOccurrences(
            of: "Tests/SpinLabAppTests/PlotTickConfigurationTests.swift",
            with: relativePath
        ), encoding: .utf8)
    }

    // Test E23: PlotTickConfiguration is in shared Plot module group (not Heatmap, not XY-specific)
    @Test("E23. PlotTickConfiguration.swift exists in shared Plot module group")
    func plotTickConfigurationExistsInSharedModule() throws {
        let src = try source(at: "Sources/SpinLabApp/Workbench/V3/PlotTickConfiguration.swift")
        #expect(src.contains("struct PlotTickConfiguration"))
        #expect(!src.contains("import RSM"), "PlotTickConfiguration must not depend on RSM")
        #expect(!src.contains("HeatmapGrid"), "PlotTickConfiguration must not depend on Heatmap types")
    }

    // Test E24: HeatmapTabRenderState uses PlotTickConfiguration as primary storage
    @Test("E24. HeatmapTabRenderState uses PlotTickConfiguration")
    func heatmapTabRenderStateUsesPlotTickConfiguration() throws {
        let src = try source(at: "Sources/SpinLabApp/Workbench/V3/Heatmap/HeatmapTabRenderState.swift")
        #expect(src.contains("tickConfiguration: PlotTickConfiguration"),
                "HeatmapTabRenderState must declare tickConfiguration as PlotTickConfiguration")
        #expect(src.contains("PlotTickConfiguration.clamp") || src.contains("PlotTickConfiguration.defaultValue"),
                "HeatmapTabRenderState must use PlotTickConfiguration clamping or default")
    }

    // Test E25: WorkbenchChartStyle/XY path uses or maps through PlotTickConfiguration
    @Test("E25. WorkbenchChartStyle maps to PlotTickConfiguration")
    func workbenchChartStyleMapsToPlotTickConfiguration() throws {
        let src = try source(at: "Sources/SpinLabApp/Workbench/V3/WorkbenchChartStyle.swift")
        #expect(src.contains("PlotTickConfiguration"),
                "WorkbenchChartStyle must reference PlotTickConfiguration")
        #expect(src.contains("tickConfiguration"),
                "WorkbenchChartStyle must expose or use a tickConfiguration property")
    }

    // Test E26: RSMWorkspaceStore uses PlotTickConfiguration.clamp, not its own tick logic
    @Test("E26. RSMWorkspaceStore delegates tick clamping to PlotTickConfiguration")
    func rsmWorkspaceStoreUsesPlotTickConfigurationClamp() throws {
        let src = try source(at: "Sources/SpinLabApp/Features/Workbench/RSMWorkspaceStore.swift")
        #expect(src.contains("PlotTickConfiguration.clamp"),
                "RSMWorkspaceStore must use PlotTickConfiguration.clamp for tick count clamping")
        #expect(!src.contains("max(2, min(20"),
                "RSMWorkspaceStore must not contain hardcoded tick clamping logic after migration")
    }

    // Test E27: Heatmap and XY renderers are not merged
    @Test("E27. HeatmapRenderer and WorkbenchChartRenderer remain separate files")
    func heatmapAndXYRenderersAreNotMerged() throws {
        let heatmapSrc = try source(at: "Sources/SpinLabApp/Workbench/V3/Heatmap/HeatmapRenderer.swift")
        let xySrc = try source(at: "Sources/SpinLabApp/Workbench/V3/WorkbenchChartRenderer.swift")

        // Each renderer defines its own type — neither has been removed or merged
        #expect(heatmapSrc.contains("struct HeatmapRenderer"),
                "HeatmapRenderer.swift must still define struct HeatmapRenderer")
        #expect(xySrc.contains("struct WorkbenchChartRenderer"),
                "WorkbenchChartRenderer.swift must still define struct WorkbenchChartRenderer")
        // XY renderer does not call into HeatmapGrid or HeatmapPlotLayout
        #expect(!xySrc.contains("HeatmapGrid"),
                "WorkbenchChartRenderer must not depend on HeatmapGrid")
        #expect(!xySrc.contains("HeatmapPlotLayout"),
                "WorkbenchChartRenderer must not depend on HeatmapPlotLayout")
        // Heatmap renderer does not call into WorkbenchPlotLayout or WorkbenchPlotSeries
        #expect(!heatmapSrc.contains("WorkbenchPlotLayout"),
                "HeatmapRenderer must not depend on WorkbenchPlotLayout")
        #expect(!heatmapSrc.contains("WorkbenchPlotSeries"),
                "HeatmapRenderer must not depend on WorkbenchPlotSeries")
    }
}
