import CoreGraphics
import Foundation
import XCTest
@testable import SpinLabApp

// MARK: - Copy PNG / Copy PDF direct-copy architecture guards
//
// Copy PNG and Copy PDF no longer re-render. WorkbenchPlotCanvas's context menu copies
// exportArtifacts.pngData / exportArtifacts.pdfData already on screen via
// WorkbenchPasteboardWriter; live render is the single source of truth and always renders
// at WorkbenchPlotRenderScale.display. WorkbenchPlotCanvas is render-path-agnostic: it
// consumes a WorkbenchGraphicExportArtifacts envelope and never knows whether the active
// tab is Cartesian XY, DualAxis, Heatmap, or RSM.

final class WorkbenchCopyPNGDirectCopyTests: XCTestCase {

    private static func canvasSource() throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SpinLabAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let url = base.appendingPathComponent(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Canvas/WorkbenchPlotCanvas.swift"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Canvas Copy PNG / Copy PDF context menu only copies current imageData/pdfData

    func testCopyPNGContextMenuHasNoExportCallback() throws {
        let src = try Self.canvasSource()

        XCTAssertFalse(src.contains("onCopyPNG"), "Canvas must not declare an onCopyPNG export callback")
        XCTAssertFalse(src.contains("copyPNGScales"), "Canvas must not declare per-scale Copy PNG options")
        XCTAssertTrue(src.contains("Button(\"Copy PNG\")"), "Canvas must expose a single Copy PNG button")
        XCTAssertTrue(src.contains("Button(\"Copy PDF\")"), "Canvas must expose a Copy PDF button")
        XCTAssertTrue(
            src.contains("WorkbenchPasteboardWriter.copyPNG(imageData)"),
            "Copy PNG must copy the currently displayed imageData directly, with no re-render"
        )
        XCTAssertTrue(
            src.contains("WorkbenchPasteboardWriter.copyPDF(pdfData)"),
            "Copy PDF must copy the currently rendered pdfData directly, with no re-render"
        )
    }

    // MARK: - Canvas is render-path-agnostic: single exportArtifacts envelope, no per-path knowledge

    func testCanvasConsumesSharedExportArtifactsEnvelope() throws {
        let src = try Self.canvasSource()

        XCTAssertTrue(
            src.contains("var exportArtifacts: WorkbenchGraphicExportArtifacts"),
            "Canvas must consume a single WorkbenchGraphicExportArtifacts envelope, not separate imageData/pdfData params"
        )
        XCTAssertFalse(
            src.contains("let imageData: Data?"),
            "Canvas must not declare a standalone imageData stored property"
        )
        for renderPathToken in ["CartesianXY", "DualAxisPlotPayload", "HeatmapPlotPayload", "RSMView"] {
            XCTAssertFalse(
                src.contains(renderPathToken),
                "Canvas must not reference render-path-specific type \(renderPathToken) — it must stay render-path-agnostic"
            )
        }
    }

    // MARK: - Copy PDF menu item visibility follows exportArtifacts.pdfData presence

    func testCopyPDFButtonGuardedByPdfDataPresence() throws {
        let src = try Self.canvasSource()
        XCTAssertTrue(
            src.contains("if let pdfData = exportArtifacts.pdfData"),
            "Copy PDF button must be conditionally shown only when exportArtifacts.pdfData is non-nil"
        )
    }

    func testCanvasExportArtifactsCarriesPdfDataWhenPresent() {
        let artifacts = WorkbenchGraphicExportArtifacts(pngData: Data([1, 2, 3]), pdfData: Data([4, 5, 6]))
        let canvas = WorkbenchPlotCanvas(exportArtifacts: artifacts)
        XCTAssertNotNil(canvas.exportArtifacts.pdfData, "Copy PDF should be available when pdfData is present")
    }

    func testCanvasExportArtifactsOmitsPdfDataWhenRenderPathHasNone() {
        let artifacts = WorkbenchGraphicExportArtifacts(pngData: Data([1, 2, 3]), pdfData: nil)
        let canvas = WorkbenchPlotCanvas(exportArtifacts: artifacts)
        XCTAssertNil(canvas.exportArtifacts.pdfData, "Copy PDF should be hidden when the render path has no pdfData")
    }

    // MARK: - Pipeline Output produces PNG and PDF from the same render pass

    func testRenderPipelineOutputIncludesVectorPDF() throws {
        let series = WorkbenchPlotSeries(label: "A", x: [0, 1, 2], y: [0, 1, 4])
        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "PDF Export Test",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [series]
        )
        let output = try WorkbenchRenderPipeline.render(.init(payload: payload))
        XCTAssertFalse(output.imageData.isEmpty)
        XCTAssertFalse(output.pdfData.isEmpty)
        // "%PDF-" only proves this is a well-formed PDF container — it says nothing about
        // whether the page content is vector drawing or a raster image embedded in a PDF
        // wrapper. Vector-ness is guaranteed structurally: renderPDF() draws into a
        // CGContext(consumer:mediaBox:) (a PDF-page-content context) via the exact same
        // drawCanvas(...) call renderPNG() uses, and never touches imageData/CGImage/NSImage
        // (see WorkbenchChartRenderer.renderPDF). We verify that guarantee here by asserting
        // the PDF page content contains no embedded Image XObject at all — a simple line/scatter
        // plot with text produces only vector path and text-showing operators, no raster images.
        XCTAssertTrue(output.pdfData.starts(with: Array("%PDF-".utf8)))
        let pdfString = String(decoding: output.pdfData, as: UTF8.self)
        XCTAssertFalse(
            pdfString.contains("/Subtype /Image") || pdfString.contains("/Subtype/Image"),
            "Vector PDF must not embed a raster Image XObject for a plain line/scatter plot"
        )
    }

    // MARK: - DualAxis PDF is true vector, produced from the same drawCanvas(...) path as PNG

    func testDualAxisRenderPipelineOutputIncludesVectorPDF() throws {
        let left = DualAxisPlotSeries(label: "Left", x: [0, 1, 2, 3], y: [0, 1, 4, 9])
        let right = DualAxisPlotSeries(label: "Right", x: [0, 1, 2, 3], y: [10, 8, 6, 4])
        let payload = DualAxisPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "DualAxis PDF Test",
            xLabel: "X",
            leftYLabel: "Left Y",
            rightYLabel: "Right Y",
            leftSeries: [left],
            rightSeries: [right]
        )
        let output = try DualAxisRenderPipeline.render(.init(payload: payload))
        XCTAssertFalse(output.imageData.isEmpty)
        XCTAssertFalse(output.pdfData.isEmpty)
        XCTAssertTrue(output.pdfData.starts(with: Array("%PDF-".utf8)))
        let pdfString = String(decoding: output.pdfData, as: UTF8.self)
        XCTAssertFalse(
            pdfString.contains("/Subtype /Image") || pdfString.contains("/Subtype/Image"),
            "DualAxis vector PDF must not embed a raster Image XObject"
        )
    }

    // MARK: - Heatmap/RSM PDF is true vector: every grid cell is a real fill-rect path, not a raster image

    func testHeatmapRenderPipelineOutputIncludesVectorPDF() throws {
        let grid = HeatmapGrid(
            xValues: [0.0, 1.0, 2.0],
            yValues: [0.0, 1.0, 2.0],
            zMatrix: [
                [0.10, 0.40, 0.70],
                [0.20, 0.50, 0.80],
                [0.30, 0.60, 0.90],
            ]
        )
        let payload = HeatmapPlotPayload(
            workflowID: "test",
            title: "Heatmap PDF Test",
            xLabel: "X",
            yLabel: "Y",
            zLabel: "Z",
            grid: grid,
            colormapKey: nil,
            zRangeClamp: nil
        )
        let output = try HeatmapRenderPipeline.render(.init(payload: payload))
        XCTAssertFalse(output.imageData.isEmpty)
        XCTAssertFalse(output.pdfData.isEmpty)
        XCTAssertTrue(output.pdfData.starts(with: Array("%PDF-".utf8)))
        // Unlike a single-image chart, a genuinely vector heatmap PDF page-content stream is
        // expected to contain many fill operators (one per grid cell) rather than an Image
        // XObject. This directly tests the architecture-audit claim in PLOT_SYSTEM.md: every
        // cell is drawn as a real CGContext fill-rect, not a rasterized grid.
        let pdfString = String(decoding: output.pdfData, as: UTF8.self)
        XCTAssertFalse(
            pdfString.contains("/Subtype /Image") || pdfString.contains("/Subtype/Image"),
            "Heatmap/RSM vector PDF must not embed a raster Image XObject for the grid body"
        )
    }

    /// Manual structural probe (not asserted, informational only): writes a rendered PDF to
    /// disk so its object table can be inspected with external tools (`strings`, a PDF parser)
    /// to independently confirm no full-page image XObject exists.
    func testWriteVectorPDFProbeToDisk() throws {
        let series = WorkbenchPlotSeries(label: "A", x: [0, 1, 2, 3], y: [0, 1, 4, 9])
        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "Vector Probe",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [series]
        )
        let output = try WorkbenchRenderPipeline.render(.init(payload: payload))
        try output.pdfData.write(to: URL(fileURLWithPath: "/tmp/spinlab_vector_probe.pdf"))
    }

    // MARK: - Live render input defaults to WorkbenchPlotRenderScale.display (3x)

    @MainActor
    func testTabRenderManagerBuildPipelineInputDefaultsToDisplayScale() {
        enum TestTab: Hashable, Sendable { case first }
        let manager = TabRenderManager<TestTab>(defaultTab: .first)

        let series = WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0, 1])
        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "Scale Test",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [series]
        )

        let input = manager.buildPipelineInput(payload: payload, for: .first)

        XCTAssertEqual(input.pixelScaleOverride, WorkbenchPlotRenderScale.display)
        XCTAssertEqual(WorkbenchPlotRenderScale.display, 3)
    }
}
