import CoreGraphics
import Testing
@testable import SpinLabApp

@Suite("Plot Legend Drag Shared")
struct PlotLegendDragSharedTests {

    private func makeGeometry(
        legendBoxRect: CGRect? = CGRect(x: 140, y: 150, width: 120, height: 68),
        currentLegendOriginCG: CGPoint = CGPoint(x: 148, y: 184)
    ) -> PlotLegendDragGeometry {
        PlotLegendDragGeometry(
            rendererSize: CGSize(width: 800, height: 600),
            plotRect: CGRect(x: 100, y: 80, width: 320, height: 220),
            legendBoxRect: legendBoxRect,
            currentLegendOriginCG: currentLegendOriginCG
        )
    }

    @Test("shared drag engine starts inside the legend and rejects outside starts")
    func sharedDragEngineStartHitTesting() {
        let geometry = makeGeometry()
        let context = CoordinateContext(
            rendererSize: geometry.rendererSize,
            displayRect: CGRect(x: 0, y: 0, width: 800, height: 600)
        )

        let inside = context.rendererToScreen(CGPoint(x: 200, y: 184))
        let outside = CGPoint(x: inside.x + 220, y: inside.y + 120)

        #expect(PlotLegendDragEngine.isInsideLegend(location: inside, geometry: geometry, coordinateContext: context))
        #expect(!PlotLegendDragEngine.isInsideLegend(location: outside, geometry: geometry, coordinateContext: context))

        let result = PlotLegendDragEngine.dragStep(
            start: inside,
            current: inside,
            geometry: geometry,
            coordinateContext: context
        )
        #expect(result != nil)
    }

    @Test("shared drag engine clamps legend inside plotRect and keeps normalized points stable")
    func sharedDragEngineClampsAndStabilizes() throws {
        let geometry = makeGeometry()
        let context = CoordinateContext(
            rendererSize: geometry.rendererSize,
            displayRect: CGRect(x: 0, y: 0, width: 800, height: 600)
        )

        let start = context.rendererToScreen(CGPoint(x: 200, y: 184))
        let current = context.rendererToScreen(CGPoint(x: 460, y: 50))

        let first = PlotLegendDragEngine.dragStep(
            start: start,
            current: current,
            geometry: geometry,
            coordinateContext: context
        )
        let second = PlotLegendDragEngine.dragStep(
            start: start,
            current: current,
            geometry: geometry,
            coordinateContext: context
        )

        let firstResult = try #require(first)
        let secondResult = try #require(second)

        #expect(firstResult.adjustedLegendPoint == secondResult.adjustedLegendPoint)
        #expect(firstResult.adjustedLegendPoint.x >= 0)
        #expect(firstResult.adjustedLegendPoint.x <= 1)
        #expect(firstResult.adjustedLegendPoint.y >= 0)
        #expect(firstResult.adjustedLegendPoint.y <= 1)
        #expect(firstResult.previewRect.minX >= context.displayRect.minX - 0.5)
        #expect(firstResult.previewRect.minY >= context.displayRect.minY - 0.5)
        #expect(firstResult.previewRect.maxX <= context.displayRect.maxX + 0.5)
        #expect(firstResult.previewRect.maxY <= context.displayRect.maxY + 0.5)
    }

    @Test("XY layouts still expose a drag geometry adapter and canvas origin helper")
    func xyLayoutAdapterRemainsAvailable() throws {
        let payload = WorkbenchPlotPayload(
            workflowID: "xy",
            workflowDisplayName: "XY",
            title: "XY",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [
                WorkbenchPlotSeries(
                    label: "Series A",
                    x: [0, 1, 2],
                    y: [0, 1, 2],
                    sourceRef: "/tmp/a.csv",
                    sampleID: "a"
                )
            ]
        )
        let layout = WorkbenchPlotLayout.compute(
            options: .init(),
            payload: payload,
            legendPoint: CGPoint(x: 0.2, y: 0.7)
        )
        let canvas = WorkbenchPlotCanvas(exportArtifacts: .empty, layout: layout)

        let geometry = try #require(layout.legendDragGeometry)
        #expect(canvas.currentLegendOriginCG() == geometry.currentLegendOriginCG)
        #expect(canvas._isInLegendFrame(
            CGPoint(x: 20, y: 20),
            coordinateContext: CoordinateContext(rendererSize: geometry.rendererSize, displayRect: CGRect(x: 0, y: 0, width: 800, height: 600))
        ) == false)
    }
}
