import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Fixture data

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

private let rsmKL2x2 = """
H     K     L     Detector
0.0   0.0   1.0   10.0
0.0   0.5   1.0   20.0
0.0   0.0   2.0   30.0
0.0   0.5   2.0   40.0
"""

private let rsmHK2x2 = """
H     K     L     Intensity
-1.0  0.0   1.0   11.0
 1.0  0.0   1.0   22.0
-1.0  1.0   1.0   33.0
 1.0  1.0   1.0   44.0
"""

// MARK: - RSM Workflow Wiring Tests

@Suite("RSM workflow wiring (Gate G)")
struct V820RSMWorkflowWiringTests {
    private static func source(at relativePath: String) throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SpinLabAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let url = base.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: Full pipeline

    @Test func fullPipelineHLProducesNonEmptyPNG() throws {
        let dataset = try RSMDataParser.parse(text: rsmHL3x3, title: "HL Test")
        let options = RSMHeatmapPayloadBuilder.Options(view: .hl, title: "HL Test")
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset, options: options)
        let output = try HeatmapRenderPipeline.render(HeatmapRenderPipeline.Input(payload: payload))

        #expect(!output.imageData.isEmpty)
        let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        #expect([UInt8](output.imageData.prefix(4)) == pngHeader, "Image data must be a valid PNG")
    }

    // MARK: K-fixed data defaults to HL view

    @Test func kFixedDataHLLabels() throws {
        let dataset = try RSMDataParser.parse(text: rsmHL3x3)
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset, options: .init(view: .hl))

        #expect(payload.xLabel == "H (r.l.u.)")
        #expect(payload.yLabel == "L (r.l.u.)")
        #expect(payload.zLabel == "Detector")
    }

    // MARK: Label contracts per acceptance criteria

    @Test func hlViewXLabelIsH() throws {
        let dataset = try RSMDataParser.parse(text: rsmHL3x3)
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset, options: .init(view: .hl))
        #expect(payload.xLabel == "H (r.l.u.)")
    }

    @Test func hlViewYLabelIsL() throws {
        let dataset = try RSMDataParser.parse(text: rsmHL3x3)
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset, options: .init(view: .hl))
        #expect(payload.yLabel == "L (r.l.u.)")
    }

    @Test func hlViewZLabelIsDetector() throws {
        let dataset = try RSMDataParser.parse(text: rsmHL3x3)
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset, options: .init(view: .hl))
        #expect(payload.zLabel == "Detector")
    }

    @Test func workflowIDIsRSM() throws {
        let dataset = try RSMDataParser.parse(text: rsmHL3x3)
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset, options: .init(view: .hl))
        #expect(payload.workflowID == "rsm")
    }

    // MARK: Canvas layout contract

    @Test @MainActor func storeActivelayoutIsNil() {
        // RSMWorkspaceStore must always return nil for activeLayout —
        // WorkbenchPlotCanvas receives layout: nil for heatmaps (no XY hit-testing).
        let store = RSMWorkspaceStore(workflowID: WorkflowKey.rsm.rawValue)
        #expect(store.activeLayout == nil)
    }

    @Test func rsmWorkspaceStoreDoesNotOwnCartesianXYCompatibilityFields() throws {
        let src = try Self.source(at: "Sources/SpinLabApp/Features/Workbench/RSMWorkspaceStore.swift")
        #expect(!src.contains("showPlotGrid"), "RSMWorkspaceStore must not own showPlotGrid")
        #expect(!src.contains("seriesRenderMode"), "RSMWorkspaceStore must not own seriesRenderMode")
        #expect(!src.contains("globalPlotDefaults"), "RSMWorkspaceStore must not own globalPlotDefaults")
        #expect(!src.contains("chartStyleOverrides"), "RSMWorkspaceStore must not own chartStyleOverrides")
    }

    // MARK: KL and HK views

    @Test func klViewPipelineSucceeds() throws {
        let dataset = try RSMDataParser.parse(text: rsmKL2x2)
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset, options: .init(view: .kl))
        let output = try HeatmapRenderPipeline.render(HeatmapRenderPipeline.Input(payload: payload))

        #expect(!output.imageData.isEmpty)
        #expect(payload.xLabel == "K (r.l.u.)")
        #expect(payload.yLabel == "L (r.l.u.)")
    }

    @Test func hkViewPipelineSucceeds() throws {
        let dataset = try RSMDataParser.parse(text: rsmHK2x2)
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset, options: .init(view: .hk))
        let output = try HeatmapRenderPipeline.render(HeatmapRenderPipeline.Input(payload: payload))

        #expect(!output.imageData.isEmpty)
        #expect(payload.xLabel == "H (r.l.u.)")
        #expect(payload.yLabel == "K (r.l.u.)")
    }

    // MARK: Error paths

    @Test func parseFailureMissingDetectorColumn() {
        let badText = "H K L\n1.0 0.0 1.0"
        #expect(throws: RSMDataParser.ParseError.self) {
            try RSMDataParser.parse(text: badText)
        }
    }

    @Test func irregularGridThrows() throws {
        let irregularText = """
        H K L Detector
        0.0 0.0 1.0 100.0
        1.0 0.0 1.0 200.0
        0.0 0.0 2.0 300.0
        """
        let dataset = try RSMDataParser.parse(text: irregularText)
        #expect(throws: RSMHeatmapPayloadBuilderError.self) {
            try RSMHeatmapPayloadBuilder.build(from: dataset, options: .init(view: .hl))
        }
    }

    @Test func emptyDatasetThrows() throws {
        let dataset = CanonicalRSMDataset(points: [], title: "", sourceRef: "", detectorColumnName: "Detector")
        #expect(throws: RSMHeatmapPayloadBuilderError.emptyDataset) {
            try RSMHeatmapPayloadBuilder.build(from: dataset)
        }
    }

    // MARK: XY workflow isolation

    @Test func rsmWorkflowIDDoesNotConflictWithXY() throws {
        let dataset = try RSMDataParser.parse(text: rsmHL3x3)
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset)
        #expect(payload.workflowID != "xy")
        #expect(payload.workflowID != "ahe")
        #expect(payload.workflowID != "3w")
        #expect(payload.workflowID != "IV")
    }

    @Test func rsmDoesNotOwnHeatmapRendering() throws {
        // RSM owns scientific mapping (data → grid); HeatmapRenderPipeline owns rendering.
        // Verify pipeline is invoked independently: RSMHeatmapPayloadBuilder produces a payload,
        // HeatmapRenderPipeline.render() produces the image — RSM has no render logic.
        let dataset = try RSMDataParser.parse(text: rsmHL3x3)
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset, options: .init(view: .hl))
        // payload is a plain data struct — RSM's job ends here
        #expect(payload.grid.xValues.count == 3)
        #expect(payload.grid.yValues.count == 3)
        #expect(payload.grid.zMatrix.count == 3)
        // rendering is HeatmapRenderPipeline's domain
        let output = try HeatmapRenderPipeline.render(HeatmapRenderPipeline.Input(payload: payload))
        #expect(!output.imageData.isEmpty)
    }
}
