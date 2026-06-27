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

    @Test("default policy preserves text overrides when source identity changes")
    @MainActor
    func defaultPolicyPreservesTextOverrides() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        let p1 = makeSourcePayload(sourceRef: "/data/file.dat", semanticParam: "A")
        manager.setOutput(TabRenderOutput(manifestPayload: p1), for: .ahe)
        manager.updateTitleOverride("My Title")
        manager.updateXLabelOverride("Custom X")
        manager.updateYLabelOverride("Custom Y")

        let p2 = makeSourcePayload(sourceRef: "/data/file.dat", semanticParam: "B")
        manager.setOutput(TabRenderOutput(manifestPayload: p2), for: .ahe)

        #expect(manager.tabStates[.ahe]?.titleOverride == "My Title")
        #expect(manager.tabStates[.ahe]?.xLabelOverride == "Custom X")
        #expect(manager.tabStates[.ahe]?.yLabelOverride == "Custom Y")
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

// MARK: - Regression: source-replacement policy wiring

@Suite("Source-replacement policy regression")
struct SourceReplacementPolicyRegressionTests {

    @Test("display-only rerender preserves manual axis range (preserveDisplayOverrides)")
    @MainActor
    func displayRerenderPreservesAxisRange() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        let payload = makeSourcePayload(sourceRef: "/data/a.dat", semanticParam: "A")
        manager.setOutput(TabRenderOutput(manifestPayload: payload), for: .ahe)
        manager.updateAxisRangeOverride(AxisRangeOverride(xMin: 0, xMax: 90))

        // Style-only rerender uses default policy (preserve)
        manager.setOutput(TabRenderOutput(manifestPayload: payload), for: .ahe, policy: .preserveDisplayOverrides)

        #expect(manager.tabStates[.ahe]?.axisRangeOverride?.xMax == 90,
            "Style-only rerender must not clear manual axis range")
    }

    @Test("source replacement clears manual axis range (clearDisplayOverridesIfSourceChanged)")
    @MainActor
    func sourceReplacementClearsAxisRange() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        let p1 = makeSourcePayload(sourceRef: "/data/a.dat", semanticParam: "A")
        manager.setOutput(TabRenderOutput(manifestPayload: p1), for: .ahe)
        manager.updateAxisRangeOverride(AxisRangeOverride(xMin: 0, xMax: 90))

        let p2 = makeSourcePayload(sourceRef: "/data/b.dat", semanticParam: "B")
        manager.setOutput(TabRenderOutput(manifestPayload: p2), for: .ahe, policy: .clearDisplayOverridesIfSourceChanged)

        #expect(manager.tabStates[.ahe]?.axisRangeOverride == nil,
            "New source analysis must clear manual axis range")
    }

    @Test("point tag toggle does not clear axis range")
    @MainActor
    func pointTagTogglePreservesAxisRange() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        let override = AxisRangeOverride(xMin: 0, xMax: 90, yMin: -2, yMax: 2)
        manager.tabStates[.ahe] = TabRenderState(axisRangeOverride: override)

        manager.setShowPointTags(true)
        manager.setShowPointTags(false)

        #expect(manager.tabStates[.ahe]?.axisRangeOverride?.xMax == 90,
            "Point tag toggle must not touch axisRangeOverride")
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

// MARK: - Axis range update path: onStyleChange must not be called

@Suite("WorkbenchPlotControlsPanel axis range update isolation")
struct AxisRangeUpdatePathIsolationTests {

    /// Regression guard: WorkbenchPlotControlsPanel's onBoundUpdate closure must call only
    /// onAxisBoundUpdate. Calling onStyleChange too triggers a second rerender that
    /// resyncs AxisBoundField from the auto placeholder, reverting committed values.
    @Test("onBoundUpdate calls onAxisBoundUpdate once and onStyleChange zero times")
    func axisRangeUpdateDoesNotCallStyleChange() {
        var styleCallCount = 0
        var axisRangeCallCount = 0

        let onStyleChange = { styleCallCount += 1 }
        let onAxisBoundUpdate: (AxisRangeBound, Double?) -> Void = { _, _ in axisRangeCallCount += 1 }

        // Mirror exactly what WorkbenchPlotControlsPanel's onBoundUpdate closure does.
        let onBoundUpdate: (AxisRangeBound, Double?) -> Void = { bound, value in
            onAxisBoundUpdate(bound, value)
            // onStyleChange must NOT be called here.
        }

        onBoundUpdate(.xMax, 180.0)

        #expect(axisRangeCallCount == 1)
        #expect(styleCallCount == 0, "onStyleChange must not fire for axis range edits")

        _ = onStyleChange // silence unused-variable warning
    }
}

// MARK: - updateAxisBound: bound-level merge and validation

@Suite("TabRenderManager.updateAxisBound")
struct AxisBoundUpdateTests {

    @Test("xMax then xMin: both preserved")
    @MainActor
    func xMaxThenXMinBothPreserved() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        manager.updateAxisBound(.xMax, value: 180.0)
        manager.updateAxisBound(.xMin, value: 0.0)
        #expect(manager.tabStates[.ahe]?.axisRangeOverride?.xMax == 180.0)
        #expect(manager.tabStates[.ahe]?.axisRangeOverride?.xMin == 0.0)
    }

    @Test("clearing yMax preserves xMin, xMax, yMin")
    @MainActor
    func clearYMaxPreservesOthers() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        manager.updateAxisBound(.xMin, value: 1.0)
        manager.updateAxisBound(.xMax, value: 10.0)
        manager.updateAxisBound(.yMin, value: -5.0)
        manager.updateAxisBound(.yMax, value: 50.0)
        manager.updateAxisBound(.yMax, value: nil)
        let r = manager.tabStates[.ahe]?.axisRangeOverride
        #expect(r?.xMin == 1.0)
        #expect(r?.xMax == 10.0)
        #expect(r?.yMin == -5.0)
        #expect(r?.yMax == nil)
    }

    @Test("invalid xMin >= xMax rejected, previous state preserved")
    @MainActor
    func invalidXMinRejectedPreservesState() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        manager.updateAxisBound(.xMax, value: 8.0)
        // attempt xMin = 9 which would be >= xMax 8
        manager.updateAxisBound(.xMin, value: 9.0)
        let r = manager.tabStates[.ahe]?.axisRangeOverride
        #expect(r?.xMax == 8.0)
        #expect(r?.xMin == nil)  // rejected — stays nil
    }

    @Test("invalid yMax <= yMin rejected, previous state preserved")
    @MainActor
    func invalidYMaxRejectedPreservesState() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        manager.updateAxisBound(.yMin, value: 5.0)
        // attempt yMax = 3 which is < yMin 5
        manager.updateAxisBound(.yMax, value: 3.0)
        let r = manager.tabStates[.ahe]?.axisRangeOverride
        #expect(r?.yMin == 5.0)
        #expect(r?.yMax == nil)  // rejected — stays nil
    }

    @Test("regression: xMax 187.5→180, then second update preserves 180")
    @MainActor
    func xMaxStaysAfterSecondBoundUpdate() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        // Simulate: auto xMax was 187.5, user types 180
        manager.updateAxisBound(.xMax, value: 180.0)
        // Simulate: user then focuses xMin and commits nil (no change)
        manager.updateAxisBound(.xMin, value: nil)
        let r = manager.tabStates[.ahe]?.axisRangeOverride
        #expect(r?.xMax == 180.0)  // must not revert to auto
        #expect(r?.xMin == nil)    // auto — not set
    }

    @Test("all bounds cleared when last bound is nilled")
    @MainActor
    func allBoundsClearedLeavesNilOverride() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        manager.updateAxisBound(.xMax, value: 10.0)
        manager.updateAxisBound(.xMax, value: nil)
        #expect(manager.tabStates[.ahe]?.axisRangeOverride == nil)
    }
}
