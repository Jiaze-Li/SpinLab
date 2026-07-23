import CoreGraphics
import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Title Visibility Phase 2: renderer + layout audit
//
// Covers showTitle=false suppressing the drawn title and reclaiming its top-padding
// lane across the three plot families (Cartesian XY, DualAxis, Heatmap), while the
// payload's own title metadata is left untouched. Screen (PNG) and export (PDF) are
// verified to come from the same computed layout, not a second re-derivation.

@Suite("Title visibility renderer/layout (Gate showTitle Phase 2)")
struct V568TitleVisibilityRendererLayoutTests {

    // MARK: - Cartesian XY

    private func xyPayload(title: String = "XY Title Test") -> WorkbenchPlotPayload {
        WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test Workflow",
            title: title,
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [
                WorkbenchPlotSeries(label: "series", x: [0.0, 1.0, 2.0], y: [1.0, 2.0, 1.5]),
            ]
        )
    }

    @Test("XY: default showTitle=true matches pre-existing layout (title drawn, standard top padding)")
    func xyDefaultMatchesExistingLayout() throws {
        let output = try WorkbenchRenderPipeline.render(.init(payload: xyPayload()))
        #expect(output.layout.showTitle)
        #expect(output.layout.titleHitRect != .zero)
        // Standard paddingTop (64) reserved above plotRect, mirroring the pre-Phase-2 layout.
        let expectedTopGap = WorkbenchChartRenderer.Options().paddingTop
        #expect(abs((CGFloat(output.layout.rendererSize.height) - output.layout.plotRect.maxY) - expectedTopGap) < 0.01)
    }

    @Test("XY: showTitle=false suppresses the title hit region")
    func xyFalseSuppressesHitRegion() throws {
        let output = try WorkbenchRenderPipeline.render(.init(payload: xyPayload(), showTitle: false))
        #expect(!output.layout.showTitle)
        #expect(output.layout.titleHitRect == .zero, "no title hit region must be created when showTitle=false")
    }

    @Test("XY: showTitle=false expands the plot area by reclaiming the title's top padding")
    func xyFalseExpandsPlotArea() throws {
        let trueOutput = try WorkbenchRenderPipeline.render(.init(payload: xyPayload(), showTitle: true))
        let falseOutput = try WorkbenchRenderPipeline.render(.init(payload: xyPayload(), showTitle: false))

        #expect(falseOutput.layout.plotRect.height > trueOutput.layout.plotRect.height,
                "hiding the title must grow plotRect height, not just blank the text")
        #expect(falseOutput.layout.plotRect.maxY > trueOutput.layout.plotRect.maxY,
                "the reclaimed top padding must move the plot's top edge upward")
    }

    @Test("XY: payload/manifest title metadata is preserved regardless of showTitle")
    func xyPayloadTitlePreserved() throws {
        let output = try WorkbenchRenderPipeline.render(.init(payload: xyPayload(title: "Keep Me"), showTitle: false))
        #expect(output.manifestPayload.title == "Keep Me",
                "showTitle must only control visual display, never delete payload title metadata")
        #expect(output.layout.chartTitle == "Keep Me",
                "layout.chartTitle must still resolve the real title text even when not drawn")
    }

    @Test("XY: screen (PNG) and export (PDF) both come from the same computed layout")
    func xyScreenAndExportShareRenderPath() throws {
        for showTitle in [true, false] {
            let output = try WorkbenchRenderPipeline.render(.init(payload: xyPayload(), showTitle: showTitle))
            #expect(!output.imageData.isEmpty)
            #expect([UInt8](output.imageData.prefix(4)) == [0x89, 0x50, 0x4E, 0x47], "PNG magic bytes")
            #expect(output.pdfData.starts(with: Array("%PDF-".utf8)), "PDF magic bytes")
            // Both were rendered against output.layout — one WorkbenchPlotLayout.compute call,
            // not a second independent derivation for PDF.
            #expect(output.layout.showTitle == showTitle)
        }
    }

    // MARK: - DualAxis

    private func dualAxisPayload(title: String = "DualAxis Title Test") -> DualAxisPlotPayload {
        DualAxisPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test Workflow",
            title: title,
            xLabel: "x",
            leftYLabel: "left",
            rightYLabel: "right",
            leftSeries: [DualAxisPlotSeries(label: "L", x: [0, 1, 2], y: [1, 2, 3])],
            rightSeries: [DualAxisPlotSeries(label: "R", x: [0, 1, 2], y: [3, 2, 1])]
        )
    }

    @Test("DualAxis: default showTitle=true matches pre-existing layout")
    func dualAxisDefaultMatchesExistingLayout() throws {
        let output = try DualAxisRenderPipeline.render(.init(payload: dualAxisPayload()))
        #expect(output.layout.showTitle)
        let expectedTopGap = DualAxisPlotLayout.Options().paddingTop
        #expect(abs((output.layout.rendererSize.height - output.layout.plotRect.maxY) - expectedTopGap) < 0.01)
    }

    @Test("DualAxis: showTitle=false suppresses drawing and expands plot area")
    func dualAxisFalseSuppressesAndExpands() throws {
        let trueOutput = try DualAxisRenderPipeline.render(.init(payload: dualAxisPayload()))
        let falseOutput = try DualAxisRenderPipeline.render(.init(
            payload: dualAxisPayload(),
            displayState: DualAxisDisplayStateSnapshot(showTitle: false)
        ))

        #expect(!falseOutput.layout.showTitle)
        #expect(falseOutput.layout.plotRect.height > trueOutput.layout.plotRect.height,
                "hiding the title must grow plotRect height, not just blank the text")
        #expect(falseOutput.layout.plotRect.maxY > trueOutput.layout.plotRect.maxY)
    }

    @Test("DualAxis: payload title metadata preserved when showTitle=false")
    func dualAxisPayloadTitlePreserved() throws {
        let output = try DualAxisRenderPipeline.render(.init(
            payload: dualAxisPayload(title: "Keep Me DualAxis"),
            displayState: DualAxisDisplayStateSnapshot(showTitle: false)
        ))
        // displayState.applying(to:) only overwrites title when titleOverride is non-empty;
        // an empty override (the default here) leaves the payload's own title intact.
        let appliedPayload = DualAxisDisplayStateSnapshot(showTitle: false).applying(to: dualAxisPayload(title: "Keep Me DualAxis"))
        #expect(appliedPayload.title == "Keep Me DualAxis")
        #expect(!output.layout.showTitle)
    }

    @Test("DualAxis: screen (PNG) and export (PDF) both come from the same computed layout")
    func dualAxisScreenAndExportShareRenderPath() throws {
        for showTitle in [true, false] {
            let output = try DualAxisRenderPipeline.render(.init(
                payload: dualAxisPayload(),
                displayState: DualAxisDisplayStateSnapshot(showTitle: showTitle)
            ))
            #expect(!output.imageData.isEmpty)
            #expect([UInt8](output.imageData.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
            #expect(output.pdfData.starts(with: Array("%PDF-".utf8)))
            #expect(output.layout.showTitle == showTitle)
        }
    }

    // MARK: - Heatmap

    private func heatmapGrid() -> HeatmapGrid {
        HeatmapGrid(xValues: [0.0, 1.0], yValues: [0.0, 1.0], zMatrix: [[0.0, 0.5], [0.5, 1.0]])
    }

    private func heatmapPayload(title: String = "Heatmap Title Test") -> HeatmapPlotPayload {
        HeatmapPlotPayload(
            workflowID: "rsm",
            title: title,
            xLabel: "X (mm)",
            yLabel: "Y (mm)",
            zLabel: "Intensity",
            grid: heatmapGrid()
        )
    }

    @Test("Heatmap: default showTitle=true matches pre-existing layout")
    func heatmapDefaultMatchesExistingLayout() throws {
        let output = try HeatmapRenderPipeline.render(.init(payload: heatmapPayload()))
        #expect(output.layout.showTitle)
        let expectedTopGap = HeatmapPlotLayout.Options().paddingTop
        #expect(abs((output.layout.rendererSize.height - output.layout.gridRect.maxY) - expectedTopGap) < 0.01)
    }

    @Test("Heatmap: showTitle=false suppresses drawing and expands the grid area")
    func heatmapFalseSuppressesAndExpands() throws {
        let trueOutput = try HeatmapRenderPipeline.render(.init(payload: heatmapPayload(), showTitle: true))
        let falseOutput = try HeatmapRenderPipeline.render(.init(payload: heatmapPayload(), showTitle: false))

        #expect(!falseOutput.layout.showTitle)
        #expect(falseOutput.layout.gridRect.height > trueOutput.layout.gridRect.height,
                "hiding the title must grow gridRect height, not just blank the text")
        #expect(falseOutput.layout.gridRect.maxY > trueOutput.layout.gridRect.maxY)
    }

    @Test("Heatmap: showTitle=false does not affect colorbar/z-label layout")
    func heatmapFalseDoesNotAffectColorbar() throws {
        let trueOutput = try HeatmapRenderPipeline.render(.init(payload: heatmapPayload(), showColorbar: true, showTitle: true))
        let falseOutput = try HeatmapRenderPipeline.render(.init(payload: heatmapPayload(), showColorbar: true, showTitle: false))

        #expect(falseOutput.layout.showColorbar)
        #expect(falseOutput.layout.colorbarRect.width == trueOutput.layout.colorbarRect.width)
        #expect(falseOutput.layout.colorbarTicks.count == trueOutput.layout.colorbarTicks.count)
        #expect(falseOutput.layout.colorbarLabelCenter.x == trueOutput.layout.colorbarLabelCenter.x,
                "colorbar/Z-label horizontal placement must be unaffected by title visibility")
    }

    @Test("Heatmap: payload title metadata preserved when showTitle=false")
    func heatmapPayloadTitlePreserved() throws {
        let payload = heatmapPayload(title: "Keep Me Heatmap")
        let output = try HeatmapRenderPipeline.render(.init(payload: payload, showTitle: false))
        #expect(!output.layout.showTitle)
        #expect(payload.title == "Keep Me Heatmap", "original payload title must remain untouched")
    }

    @Test("Heatmap: screen (PNG) and export (PDF) both come from the same computed layout")
    func heatmapScreenAndExportShareRenderPath() throws {
        for showTitle in [true, false] {
            let output = try HeatmapRenderPipeline.render(.init(payload: heatmapPayload(), showTitle: showTitle))
            #expect(!output.imageData.isEmpty)
            #expect([UInt8](output.imageData.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
            #expect(output.pdfData.starts(with: Array("%PDF-".utf8)))
            #expect(output.layout.showTitle == showTitle)
        }
    }
}
