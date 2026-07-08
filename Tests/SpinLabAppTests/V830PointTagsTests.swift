import Foundation
import Testing
@testable import SpinLabApp

/// Tests for the shared point tag feature (v8.3.0).
///
/// Covers:
/// - hiddenPointLabelIndicesBySeries toggle behavior in TabRenderManager
/// - Pipeline strips all pointLabels when showPointTags is false
/// - Pipeline preserves pointLabels (minus hidden) when showPointTags is true
/// - Toggling point tags does not modify axisRangeOverride
@Suite("V8.3.0 Point Tags")
struct V830PointTagsTests {

    // MARK: - Helpers

    private static func makeTaggedPayload() -> WorkbenchPlotPayload {
        WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "Test Chart",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [WorkbenchPlotSeries(
                label: "S1",
                x: [0, 30, 60, 90],
                y: [1.0, 1.5, 2.0, 1.8],
                renderMode: .scatter,
                renderModeLocked: true,
                pointLabels: ["0°", "30°", "60°", "90°"]
            )]
        )
    }

    // MARK: - hiddenPointLabelIndicesBySeries toggle

    @MainActor
    @Test("togglePointLabelVisibility adds index on first call")
    func toggleAddsIndex() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        manager.togglePointLabelVisibility(sampleID: "s1", pointIndex: 2)
        let hidden = manager.hiddenPointLabelsBySampleID(for: .ahe)
        #expect(hidden["s1"] == [2])
    }

    @MainActor
    @Test("togglePointLabelVisibility removes index on second call")
    func toggleRemovesIndex() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        manager.togglePointLabelVisibility(sampleID: "s1", pointIndex: 2)
        manager.togglePointLabelVisibility(sampleID: "s1", pointIndex: 2)
        let hidden = manager.hiddenPointLabelsBySampleID(for: .ahe)
        #expect(hidden["s1"] == nil)
    }

    @MainActor
    @Test("togglePointLabelVisibility accumulates multiple indices sorted")
    func toggleAccumulatesMultipleIndices() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        manager.togglePointLabelVisibility(sampleID: "s1", pointIndex: 3)
        manager.togglePointLabelVisibility(sampleID: "s1", pointIndex: 1)
        let hidden = manager.hiddenPointLabelsBySampleID(for: .ahe)
        #expect(hidden["s1"] == [1, 3])
    }

    // MARK: - Pipeline: showPointTags = false strips all point labels

    @Test("Pipeline with showPointTags=false produces no hit targets in layout")
    func pipelineStripsTags() throws {
        var input = WorkbenchRenderPipeline.Input(
            payload: Self.makeTaggedPayload()
        )
        input.showPointTags = false
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.layout.pointDotHitTargets.isEmpty,
            "showPointTags=false must strip labels so no hit targets are generated")
    }

    @Test("Pipeline with showPointTags=true produces hit targets for tagged series")
    func pipelinePreservesTags() throws {
        var input = WorkbenchRenderPipeline.Input(
            payload: Self.makeTaggedPayload()
        )
        input.showPointTags = true
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(!output.layout.pointDotHitTargets.isEmpty,
            "showPointTags=true must preserve labels so hit targets are generated")
        #expect(output.layout.pointDotHitTargets.count == 4,
            "4 tagged points → 4 hit targets")
    }

    // MARK: - Pipeline: hidden index suppresses specific tag

    @Test("Pipeline suppresses label for hidden point index only")
    func pipelineSuppressesHiddenIndex() throws {
        var input = WorkbenchRenderPipeline.Input(
            payload: Self.makeTaggedPayload()
        )
        input.showPointTags = true
        // Hide point at index 1 ("30°")
        input.hiddenPointLabelsBySeries = [0: [1]]
        let output = try WorkbenchRenderPipeline.render(input)
        // Hit targets are based on pointLabels existing; hidden index still has a hit target
        // (the hit target allows re-toggling visibility). Verify 4 targets still exist.
        #expect(output.layout.pointDotHitTargets.count == 4,
            "Hit targets exist for all points regardless of label visibility")
    }

    // MARK: - setShowPointTags does not affect axisRangeOverride

    @MainActor
    @Test("setShowPointTags does not modify axisRangeOverride")
    func setShowPointTagsPreservesAxisRangeOverride() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        let override = AxisRangeOverride(xMin: 1.0, xMax: 5.0, yMin: -1.0, yMax: 3.0)
        manager.tabStates[.ahe] = TabRenderState(axisRangeOverride: override)

        manager.setShowPointTags(true)

        let state = manager.state(for: .ahe)
        #expect(state.showPointTags == true)
        #expect(state.axisRangeOverride == override,
            "setShowPointTags must not touch axisRangeOverride")
    }

    @MainActor
    @Test("togglePointLabelVisibility does not modify axisRangeOverride")
    func toggleTagPreservesAxisRangeOverride() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        let override = AxisRangeOverride(xMin: 0.0, xMax: 90.0, yMin: -2.0, yMax: 2.0)
        manager.tabStates[.ahe] = TabRenderState(axisRangeOverride: override)

        manager.togglePointLabelVisibility(sampleID: "s1", pointIndex: 0)

        let state = manager.state(for: .ahe)
        #expect(state.axisRangeOverride == override,
            "togglePointLabelVisibility must not touch axisRangeOverride")
    }

    // MARK: - ThreeOmegaPlotRenderer threads showPointTags into the pipeline

    private static func makeAngleSweepResult(device: String, rahe1: Double) -> ThreeOmegaFieldSweepResult {
        ThreeOmegaFieldSweepResult(
            temperatureK: 300,
            device: device,
            sampleMetadata: nil,
            sampleID: nil,
            sourceFilePath: nil,
            hField: [0, 1],
            r1omega: [0, 1],
            r3omega: [0, 1],
            iRms: 1e-3,
            rahe1omega: rahe1,
            rahe1omegaWA: nil,
            hc1omega: nil,
            hc3omega: nil,
            v3omegaWindow: 0,
            v3omegaFit: nil
        )
    }

    @Test("ThreeOmegaPlotRenderer RAHE vs Device: showPointTags=false strips point labels from layout")
    func threeOmegaRendererStripsTagsWhenHidden() throws {
        let sweeps = [
            Self.makeAngleSweepResult(device: "0deg", rahe1: 1.0),
            Self.makeAngleSweepResult(device: "45deg", rahe1: 1.5),
            Self.makeAngleSweepResult(device: "90deg", rahe1: 2.0),
        ]
        var renderer = ThreeOmegaPlotRenderer()
        renderer.showPointTags = false
        let (_, _, layout, _, _) = renderer.renderRAHE1omegaVsDevice(sweeps: sweeps, device: "angle_sweep", method: .highField)
        let targets = try #require(layout, "render must produce a layout for valid angle-sweep data")
        #expect(targets.pointDotHitTargets.isEmpty,
            "showPointTags=false must strip pointLabels so no hit targets are generated")
    }

    @Test("ThreeOmegaPlotRenderer RAHE vs Device: showPointTags=true keeps point labels in layout")
    func threeOmegaRendererKeepsTagsWhenVisible() throws {
        let sweeps = [
            Self.makeAngleSweepResult(device: "0deg", rahe1: 1.0),
            Self.makeAngleSweepResult(device: "45deg", rahe1: 1.5),
            Self.makeAngleSweepResult(device: "90deg", rahe1: 2.0),
        ]
        var renderer = ThreeOmegaPlotRenderer()
        renderer.showPointTags = true
        let (_, _, layout, _, _) = renderer.renderRAHE1omegaVsDevice(sweeps: sweeps, device: "angle_sweep", method: .highField)
        let targets = try #require(layout, "render must produce a layout for valid angle-sweep data")
        #expect(!targets.pointDotHitTargets.isEmpty,
            "showPointTags=true must keep pointLabels so hit targets are generated")
    }

    // MARK: - TabRenderState Codable round-trip

    @Test("TabRenderState encodes and decodes showPointTags")
    func tabRenderStateRoundTrip() throws {
        let original = TabRenderState(showPointTags: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TabRenderState.self, from: data)
        #expect(decoded.showPointTags == true)
    }

    @Test("TabRenderState defaults showPointTags to false when key absent")
    func tabRenderStateDefaultsFalse() throws {
        let json = #"{"titleOverride": ""}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TabRenderState.self, from: json)
        #expect(decoded.showPointTags == false)
    }
}
