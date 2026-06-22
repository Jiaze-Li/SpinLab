import CoreGraphics
import Foundation
import Testing
@testable import SpinLabApp

private func makeTestPayload(
    series: [WorkbenchPlotSeries]? = nil
) -> WorkbenchPlotPayload {
    let s = series ?? [WorkbenchPlotSeries(label: "A", x: [0, 1, 2], y: [10, 20, 30])]
    return WorkbenchPlotPayload(
        workflowID: "test",
        workflowDisplayName: "Test",
        title: "Test",
        axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
        series: s
    )
}

// MARK: - WorkbenchChartStyle appearance parsing

@Suite("WorkbenchChartStyle appearance parsing")
struct WorkbenchChartStyleAppearanceTests {

    @Test("lineWidth parses from styleParams")
    func lineWidthParses() {
        let style = WorkbenchChartStyle.from(styleParams: ["lineWidth": "2.5"])
        #expect(style.lineWidth == 2.5)
    }

    @Test("pointRadius parses from styleParams")
    func pointRadiusParses() {
        let style = WorkbenchChartStyle.from(styleParams: ["pointRadius": "4"])
        #expect(style.pointRadius == 4.0)
    }

    @Test("lineWidth defaults to nil (Auto)")
    func lineWidthDefaultsToNil() {
        let style = WorkbenchChartStyle()
        #expect(style.lineWidth == nil)
    }

    @Test("pointRadius defaults to nil (Auto)")
    func pointRadiusDefaultsToNil() {
        let style = WorkbenchChartStyle()
        #expect(style.pointRadius == nil)
    }

    @Test("lineWidth and pointRadius are globalPlotDefaultKeys")
    func keysAreGlobal() {
        #expect(WorkbenchChartStyle.globalPlotDefaultKeys.contains("lineWidth"))
        #expect(WorkbenchChartStyle.globalPlotDefaultKeys.contains("pointRadius"))
    }

    @Test("invalid lineWidth (zero) is rejected")
    func invalidLineWidthRejected() {
        let style = WorkbenchChartStyle.from(styleParams: ["lineWidth": "0"])
        #expect(style.lineWidth == nil)
    }

    @Test("invalid pointRadius (negative) is rejected")
    func invalidPointRadiusRejected() {
        let style = WorkbenchChartStyle.from(styleParams: ["pointRadius": "-1"])
        #expect(style.pointRadius == nil)
    }
}

// MARK: - Renderer uses style.pointRadius

@Suite("WorkbenchChartRenderer pointRadius")
struct WorkbenchChartRendererPointRadiusTests {

    private func makePayload(scatter: Bool = true) -> WorkbenchPlotPayload {
        var s = WorkbenchPlotSeries(label: "A", x: [1, 2, 3], y: [1, 4, 9])
        s.renderMode = scatter ? .scatter : .line
        return makeTestPayload(series: [s])
    }

    @Test("renders scatter without error using default pointRadius")
    func rendersDefaultRadius() throws {
        let renderer = WorkbenchChartRenderer()
        let style = WorkbenchChartStyle()
        let data = try renderer.renderPNG(payload: makePayload(), options: .init(), style: style)
        #expect(!data.isEmpty)
    }

    @Test("renders scatter without error using custom pointRadius")
    func rendersCustomRadius() throws {
        let renderer = WorkbenchChartRenderer()
        var style = WorkbenchChartStyle()
        style.pointRadius = 6.0
        let data = try renderer.renderPNG(payload: makePayload(), options: .init(), style: style)
        #expect(!data.isEmpty)
    }

    @Test("renders with lineWidth from style")
    func rendersCustomLineWidth() throws {
        let renderer = WorkbenchChartRenderer()
        var style = WorkbenchChartStyle()
        style.lineWidth = 3.0
        var s = WorkbenchPlotSeries(label: "A", x: [1, 2, 3], y: [1, 4, 9])
        s.renderMode = .line
        s.lineWidth = 3.0
        let payload = makeTestPayload(series: [s])
        let data = try renderer.renderPNG(payload: payload, options: .init(), style: style)
        #expect(!data.isEmpty)
    }
}

// MARK: - Pipeline applies lineWidth override to unlocked series

@Suite("WorkbenchRenderPipeline lineWidth override")
struct PipelineLineWidthTests {

    private func makeInput(lineWidth: String, locked: Bool = false) -> WorkbenchRenderPipeline.Input {
        var s = WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0, 1])
        s.lineWidth = 2.0
        s.renderModeLocked = locked
        return WorkbenchRenderPipeline.Input(
            payload: makeTestPayload(series: [s]),
            globalPlotDefaults: ["lineWidth": lineWidth]
        )
    }

    @Test("pipeline applies lineWidth from globalPlotDefaults to unlocked series")
    func pipelineAppliesLineWidth() throws {
        let input = makeInput(lineWidth: "3")
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(!output.imageData.isEmpty)
        #expect(output.manifestPayload.series[0].lineWidth == 3.0)
    }

    @Test("pipeline skips lineWidth override for renderModeLocked series")
    func pipelineSkipsLockedSeries() throws {
        var s = WorkbenchPlotSeries(label: "Fit", x: [0, 1], y: [0, 1])
        s.lineWidth = 1.0
        s.renderModeLocked = true
        let input = WorkbenchRenderPipeline.Input(
            payload: makeTestPayload(series: [s]),
            globalPlotDefaults: ["lineWidth": "5"]
        )
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.manifestPayload.series[0].lineWidth == 1.0)
    }
}

// MARK: - AxisRangeOverride encode/decode

@Suite("AxisRangeOverride persistence")
struct AxisRangeOverrideTests {

    @Test("encodes and decodes round-trip")
    func encodeDecodeRoundTrip() throws {
        let original = AxisRangeOverride(xMin: -5.0, xMax: 10.0, yMin: nil, yMax: 3.14)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AxisRangeOverride.self, from: data)
        #expect(decoded.xMin == -5.0)
        #expect(decoded.xMax == 10.0)
        #expect(decoded.yMin == nil)
        #expect(decoded.yMax == 3.14)
    }

    @Test("isEmpty returns true when all bounds nil")
    func isEmptyWhenAllNil() {
        let o = AxisRangeOverride()
        #expect(o.isEmpty)
    }

    @Test("isEmpty returns false when any bound is set")
    func notEmptyWhenBoundSet() {
        let o = AxisRangeOverride(xMin: 0)
        #expect(!o.isEmpty)
    }
}

// MARK: - TabRenderState encodes/decodes axisRangeOverride

@Suite("TabRenderState axisRangeOverride persistence")
struct TabRenderStateAxisRangeTests {

    @Test("TabRenderState encodes and decodes axisRangeOverride")
    func encodeDecodeTabState() throws {
        var state = TabRenderState()
        state.axisRangeOverride = AxisRangeOverride(xMin: 1, xMax: 9, yMin: -2, yMax: 5)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TabRenderState.self, from: data)
        #expect(decoded.axisRangeOverride?.xMin == 1)
        #expect(decoded.axisRangeOverride?.xMax == 9)
        #expect(decoded.axisRangeOverride?.yMin == -2)
        #expect(decoded.axisRangeOverride?.yMax == 5)
    }

    @Test("TabRenderState decodes without axisRangeOverride (backward compat)")
    func decodesWithoutAxisRange() throws {
        let json = """
        {"titleOverride":"", "xLabelOverride":"", "yLabelOverride":""}
        """
        let data = json.data(using: .utf8)!
        let state = try JSONDecoder().decode(TabRenderState.self, from: data)
        #expect(state.axisRangeOverride == nil)
    }

    @Test("axisRangeOverride cleared by clearStates (explicit reset)")
    @MainActor
    func axisRangeOverrideClearedOnSourceReset() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        manager.tabStates[.ahe] = TabRenderState(
            axisRangeOverride: AxisRangeOverride(xMin: 0, xMax: 10)
        )
        // Explicit reset via clearStates clears axisRangeOverride.
        manager.clearStates()
        #expect(manager.tabStates[.ahe]?.axisRangeOverride == nil)
    }
}

// MARK: - DisplayOverridePolicy: setOutput whitelist behaviour

private func makeSourcePayload(sourceRef: String, semanticParam: String = "A") -> WorkbenchPlotPayload {
    let s = WorkbenchPlotSeries(label: "S", x: [0, 1], y: [0, 1], sourceRef: sourceRef)
    return WorkbenchPlotPayload(
        workflowID: "test",
        workflowDisplayName: "Test",
        title: "T",
        axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
        series: [s],
        semanticParams: ["method": semanticParam]
    )
}

@Suite("DisplayOverridePolicy: setOutput preserves axisRangeOverride")
struct DisplayOverridePolicyTests {

    @Test("default policy preserves axisRangeOverride when source identity changes")
    @MainActor
    func defaultPolicyPreservesAxisRange() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        let p1 = makeSourcePayload(sourceRef: "/data/file.dat", semanticParam: "A")
        manager.setOutput(TabRenderOutput(manifestPayload: p1), for: .ahe)
        manager.updateAxisRangeOverride(AxisRangeOverride(xMin: 0, xMax: 10))

        let p2 = makeSourcePayload(sourceRef: "/data/file.dat", semanticParam: "B")
        manager.setOutput(TabRenderOutput(manifestPayload: p2), for: .ahe)

        #expect(manager.tabStates[.ahe]?.axisRangeOverride?.xMax == 10)
    }

    @Test("default policy clears text overrides when source identity changes")
    @MainActor
    func defaultPolicyClearsTextOverrides() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        let p1 = makeSourcePayload(sourceRef: "/data/file.dat", semanticParam: "A")
        manager.setOutput(TabRenderOutput(manifestPayload: p1), for: .ahe)
        manager.updateTitleOverride("My Title")
        manager.updateXLabelOverride("Custom X")

        let p2 = makeSourcePayload(sourceRef: "/data/file.dat", semanticParam: "B")
        manager.setOutput(TabRenderOutput(manifestPayload: p2), for: .ahe)

        #expect(manager.tabStates[.ahe]?.titleOverride == "")
        #expect(manager.tabStates[.ahe]?.xLabelOverride == "")
    }

    @Test("clearDisplayOverridesIfSourceChanged clears axisRangeOverride on source change")
    @MainActor
    func clearIfSourceChangedClearsAxisRange() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        let p1 = makeSourcePayload(sourceRef: "/data/file.dat", semanticParam: "A")
        manager.setOutput(TabRenderOutput(manifestPayload: p1), for: .ahe)
        manager.updateAxisRangeOverride(AxisRangeOverride(xMin: 0, xMax: 10))

        let p2 = makeSourcePayload(sourceRef: "/data/file.dat", semanticParam: "B")
        manager.setOutput(TabRenderOutput(manifestPayload: p2), for: .ahe, policy: .clearDisplayOverridesIfSourceChanged)

        #expect(manager.tabStates[.ahe]?.axisRangeOverride == nil)
    }

    @Test("clearDisplayOverridesIfSourceChanged preserves axisRangeOverride when source is same")
    @MainActor
    func clearIfSourceChangedPreservesAxisRangeWhenSameSource() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        let p1 = makeSourcePayload(sourceRef: "/data/file.dat", semanticParam: "A")
        manager.setOutput(TabRenderOutput(manifestPayload: p1), for: .ahe)
        manager.updateAxisRangeOverride(AxisRangeOverride(xMin: 0, xMax: 10))

        let p2 = makeSourcePayload(sourceRef: "/data/file.dat", semanticParam: "A")
        manager.setOutput(TabRenderOutput(manifestPayload: p2), for: .ahe, policy: .clearDisplayOverridesIfSourceChanged)

        #expect(manager.tabStates[.ahe]?.axisRangeOverride?.xMax == 10)
    }

    @Test("forceClearDisplayOverrides clears axisRangeOverride even when source is same")
    @MainActor
    func forceClearAlwaysClearsAxisRange() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        let p1 = makeSourcePayload(sourceRef: "/data/file.dat", semanticParam: "A")
        manager.setOutput(TabRenderOutput(manifestPayload: p1), for: .ahe)
        manager.updateAxisRangeOverride(AxisRangeOverride(xMin: 0, xMax: 10))

        let p2 = makeSourcePayload(sourceRef: "/data/file.dat", semanticParam: "A")
        manager.setOutput(TabRenderOutput(manifestPayload: p2), for: .ahe, policy: .forceClearDisplayOverrides)

        #expect(manager.tabStates[.ahe]?.axisRangeOverride == nil)
    }

    @Test("nil manifest payload never clears axisRangeOverride")
    @MainActor
    func nilManifestNeverClears() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        manager.updateAxisRangeOverride(AxisRangeOverride(xMin: 1, xMax: 9))

        manager.setOutput(TabRenderOutput(manifestPayload: nil), for: .ahe, policy: .forceClearDisplayOverrides)

        #expect(manager.tabStates[.ahe]?.axisRangeOverride?.xMax == 9)
    }

    @Test("xMax persists after a second setOutput with same source (style rerender)")
    @MainActor
    func xMaxPersistsAfterStyleRerender() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        let payload = makeSourcePayload(sourceRef: "/data/file.dat")
        manager.setOutput(TabRenderOutput(manifestPayload: payload), for: .ahe)
        manager.updateAxisRangeOverride(AxisRangeOverride(xMin: nil, xMax: 5))

        manager.setOutput(TabRenderOutput(manifestPayload: payload), for: .ahe)

        #expect(manager.tabStates[.ahe]?.axisRangeOverride?.xMax == 5)
    }

    @Test("editing xMax then setOutput for yMax path preserves xMax")
    @MainActor
    func xMaxPreservedWhenYMaxEdited() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        let payload = makeSourcePayload(sourceRef: "/data/file.dat")
        manager.setOutput(TabRenderOutput(manifestPayload: payload), for: .ahe)

        manager.updateAxisRangeOverride(AxisRangeOverride(xMin: nil, xMax: 5, yMin: nil, yMax: nil))
        manager.updateAxisRangeOverride(AxisRangeOverride(xMin: nil, xMax: 5, yMin: nil, yMax: 20))

        manager.setOutput(TabRenderOutput(manifestPayload: payload), for: .ahe)

        #expect(manager.tabStates[.ahe]?.axisRangeOverride?.xMax == 5)
        #expect(manager.tabStates[.ahe]?.axisRangeOverride?.yMax == 20)
    }
}

// MARK: - Renderer respects fixed Y range

@Suite("WorkbenchChartRenderer fixed Y range")
struct RendererFixedYRangeTests {

    @Test("renderer renders without error with fixed Y range")
    func rendersWithFixedY() throws {
        var opts = WorkbenchChartRenderer.Options()
        opts.fixedYMin = 0
        opts.fixedYMax = 50
        let renderer = WorkbenchChartRenderer()
        let data = try renderer.renderPNG(payload: makeTestPayload(), options: opts)
        #expect(!data.isEmpty)
    }

    @Test("layout uses fixedYMin/fixedYMax from options")
    func layoutUsesFixedY() {
        var opts = WorkbenchChartRenderer.Options()
        opts.fixedYMin = 0
        opts.fixedYMax = 100
        let layout = WorkbenchPlotLayout.compute(options: opts, payload: makeTestPayload(), legendPoint: nil)
        #expect(layout.axisYMin == 0)
        #expect(layout.axisYMax == 100)
    }

    @Test("pipeline applies axisRangeOverride to renderer")
    func pipelineAppliesAxisRange() throws {
        let s = WorkbenchPlotSeries(label: "A", x: [0, 1], y: [5, 15])
        var input = WorkbenchRenderPipeline.Input(payload: makeTestPayload(series: [s]))
        input.axisRangeOverride = AxisRangeOverride(xMin: nil, xMax: nil, yMin: -10, yMax: 50)
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.layout.axisYMin == -10)
        #expect(output.layout.axisYMax == 50)
    }
}

// MARK: - Pack snapshot/restore preserves axisRangeOverride

@Suite("TabRenderManager pack persistence with axisRangeOverride")
struct TabRenderManagerPackPersistenceTests {

    @Test("snapshot/restore round-trips axisRangeOverride")
    @MainActor
    func snapshotRestoreRoundTrip() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        var state = TabRenderState()
        state.axisRangeOverride = AxisRangeOverride(xMin: 2, xMax: 8, yMin: -1, yMax: 4)
        manager.tabStates[.ahe] = state

        let snapshot = manager.snapshotStates(keyFor: { $0.rawValue })
        #expect(snapshot["ahe"]?.axisRangeOverride?.xMin == 2)

        let manager2 = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        manager2.restoreStates(snapshot, tabFor: { AHEWorkbenchTab(rawValue: $0) })
        #expect(manager2.tabStates[.ahe]?.axisRangeOverride?.xMin == 2)
        #expect(manager2.tabStates[.ahe]?.axisRangeOverride?.yMax == 4)
    }
}

// MARK: - Axis range validation (min commit symmetry with max commit)

@Suite("WorkbenchAxisRangeControls validation symmetry")
struct AxisRangeValidationTests {

    // Simulates what the xMin/yMin/xMax/yMax onCommit closures do in WorkbenchAxisRangeControls.
    // autoMin/autoMax represent layout.axisXMin etc. when no manual bound is set.
    private func commitMin(
        newVal: Double?,
        existingOverride: AxisRangeOverride?,
        autoMin: Double?,
        autoMax: Double?
    ) -> AxisRangeOverride? {
        var o = existingOverride ?? AxisRangeOverride()
        o.xMin = newVal
        if newVal == nil { return o.isEmpty ? nil : o }
        // validate: effective lo must be < effective hi
        let lo = o.xMin ?? autoMin
        let hi = o.xMax ?? autoMax
        if let lo, let hi, lo >= hi { return existingOverride }
        return o.isEmpty ? nil : o
    }

    private func commitMax(
        newVal: Double?,
        existingOverride: AxisRangeOverride?,
        autoMin: Double?,
        autoMax: Double?
    ) -> AxisRangeOverride? {
        var o = existingOverride ?? AxisRangeOverride()
        o.xMax = newVal
        if newVal == nil { return o.isEmpty ? nil : o }
        let lo = o.xMin ?? autoMin
        let hi = o.xMax ?? autoMax
        if let lo, let hi, lo >= hi { return existingOverride }
        return o.isEmpty ? nil : o
    }

    @Test("editing xMin above auto xMax is rejected")
    func xMinAboveAutoMaxRejected() {
        // auto range is [0, 10]; user tries to set xMin = 15 (> autoMax 10)
        let result = commitMin(newVal: 15, existingOverride: nil, autoMin: 0, autoMax: 10)
        #expect(result == nil) // rejected → previous override (nil) preserved
    }

    @Test("editing xMin above manual xMax is rejected")
    func xMinAboveManualMaxRejected() {
        let existing = AxisRangeOverride(xMin: 1, xMax: 8)
        let result = commitMin(newVal: 9, existingOverride: existing, autoMin: 0, autoMax: 10)
        #expect(result?.xMin == 1) // rejected → previous xMin preserved
        #expect(result?.xMax == 8)
    }

    @Test("editing yMin above existing yMax is rejected")
    func yMinAboveYMaxRejected() {
        // Mirrors xMin logic for Y axis
        var o = AxisRangeOverride(yMin: nil, yMax: 5)
        let prev = o
        o.yMin = 6 // would make lo=6 >= hi=5
        let lo = o.yMin
        let hi = o.yMax
        let rejected = (lo != nil && hi != nil && lo! >= hi!)
        let result: AxisRangeOverride? = rejected ? prev : (o.isEmpty ? nil : o)
        #expect(result?.yMax == 5)
        #expect(result?.yMin == nil) // edit was rejected; yMin stays nil
    }

    @Test("editing xMax below auto xMin is rejected")
    func xMaxBelowAutoMinRejected() {
        // auto range is [5, 20]; user tries to set xMax = 3 (< autoMin 5)
        let result = commitMax(newVal: 3, existingOverride: nil, autoMin: 5, autoMax: 20)
        #expect(result == nil) // rejected → previous override (nil) preserved
    }

    @Test("editing yMax below existing yMin is rejected")
    func yMaxBelowYMinRejected() {
        let existing = AxisRangeOverride(yMin: 2, yMax: 10)
        // user tries to set yMax = 1 (< yMin 2)
        var o = existing
        o.yMax = 1
        let lo = o.yMin
        let hi = o.yMax
        let rejected = (lo != nil && hi != nil && lo! >= hi!)
        let result: AxisRangeOverride? = rejected ? existing : (o.isEmpty ? nil : o)
        #expect(result?.yMin == 2)   // unchanged
        #expect(result?.yMax == 10)  // rejected → yMax stays 10
    }

    @Test("clearing xMin returns that bound to auto without touching xMax")
    func clearXMinKeepsXMax() {
        let existing = AxisRangeOverride(xMin: 2, xMax: 8)
        let result = commitMin(newVal: nil, existingOverride: existing, autoMin: 0, autoMax: 10)
        #expect(result?.xMin == nil)  // cleared
        #expect(result?.xMax == 8)   // untouched
    }

    @Test("clearing xMax returns that bound to auto without touching xMin")
    func clearXMaxKeepsXMin() {
        let existing = AxisRangeOverride(xMin: 3, xMax: 9)
        let result = commitMax(newVal: nil, existingOverride: existing, autoMin: 0, autoMax: 10)
        #expect(result?.xMax == nil)  // cleared
        #expect(result?.xMin == 3)   // untouched
    }
}
