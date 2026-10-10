import CoreGraphics
import Foundation
import Testing
@testable import SpinLabApp

@Suite("Heatmap Plot Layout Aspect Ratio Tests")
struct HeatmapPlotLayoutAspectTests {

    private func makeGrid(xRange: (Double, Double), yRange: (Double, Double), steps: (Int, Int) = (5, 5)) -> HeatmapGrid {
        let (xMin, xMax) = xRange
        let (yMin, yMax) = yRange
        let (nx, ny) = steps
        let xs = (0..<nx).map { xMin + (xMax - xMin) * Double($0) / Double(nx - 1) }
        let ys = (0..<ny).map { yMin + (yMax - yMin) * Double($0) / Double(ny - 1) }
        let z = Array(repeating: Array(repeating: 1.0, count: nx), count: ny)
        return HeatmapGrid(xValues: xs, yValues: ys, zMatrix: z)
    }

    private func makePayload(grid: HeatmapGrid, aspectPolicy: HeatmapAspectPolicy = .fill) -> HeatmapPlotPayload {
        HeatmapPlotPayload(
            workflowID: "test",
            title: "Aspect Test",
            xLabel: "X",
            yLabel: "Y",
            zLabel: "Z",
            grid: grid,
            aspectPolicy: aspectPolicy
        )
    }

    @Test("fill aspect policy fills available width and height")
    func fillAspectPolicyFillsAvailableArea() {
        let grid = makeGrid(xRange: (0, 5), yRange: (0, 5))
        let payload = makePayload(grid: grid, aspectPolicy: .fill)
        let options = HeatmapPlotLayout.Options(width: 800, height: 600)
        let layout = HeatmapPlotLayout.compute(payload: payload, options: options)

        #expect(layout.aspectPolicy == .fill)
        // With paddingLeft/paddingRight = 80, available width is 640
        #expect(layout.gridRect.width == 640)
        // With paddingTop = 60, paddingBottom = 80, available height is 460
        #expect(layout.gridRect.height == 460)
        #expect(layout.gridRect.width != layout.gridRect.height)
    }

    @Test("physical aspect policy with 5µm x 5µm scan produces square gridRect")
    func physicalAspectSquareScan() {
        let grid = makeGrid(xRange: (0, 5), yRange: (0, 5))
        let payload = makePayload(grid: grid, aspectPolicy: .physical)
        let options = HeatmapPlotLayout.Options(width: 800, height: 600)
        let layout = HeatmapPlotLayout.compute(payload: payload, options: options)

        #expect(layout.aspectPolicy == .physical)
        #expect(abs(layout.gridRect.width - layout.gridRect.height) < 1e-6, "5µm x 5µm must render square")
        #expect(layout.gridRect.height == 460)
        #expect(layout.gridRect.width == 460)
    }

    @Test("physical aspect policy with 10µm x 5µm scan produces 2:1 aspect ratio")
    func physicalAspectLandscapeScan() {
        let grid = makeGrid(xRange: (0, 10), yRange: (0, 5))
        let payload = makePayload(grid: grid, aspectPolicy: .physical)
        let options = HeatmapPlotLayout.Options(width: 800, height: 600)
        let layout = HeatmapPlotLayout.compute(payload: payload, options: options)

        #expect(layout.aspectPolicy == .physical)
        let ratio = layout.gridRect.width / layout.gridRect.height
        #expect(abs(ratio - 2.0) < 1e-4, "10µm x 5µm scan must render with 2:1 width-to-height ratio")
        #expect(layout.gridRect.width == 640)
        #expect(layout.gridRect.height == 320)
    }

    @Test("physical aspect policy with 5µm x 10µm scan produces 1:2 aspect ratio")
    func physicalAspectPortraitScan() {
        let grid = makeGrid(xRange: (0, 5), yRange: (0, 10))
        let payload = makePayload(grid: grid, aspectPolicy: .physical)
        let options = HeatmapPlotLayout.Options(width: 800, height: 600)
        let layout = HeatmapPlotLayout.compute(payload: payload, options: options)

        #expect(layout.aspectPolicy == .physical)
        let ratio = layout.gridRect.width / layout.gridRect.height
        #expect(abs(ratio - 0.5) < 1e-4, "5µm x 10µm scan must render with 1:2 width-to-height ratio")
        #expect(layout.gridRect.height == 460)
        #expect(layout.gridRect.width == 230)
    }

    @Test("physicalDataAspectRatio calculation handles arbitrary coordinate offsets and ordering")
    func physicalDataAspectRatioCalculation() {
        let standard = HeatmapGrid(xValues: [0, 5], yValues: [0, 5], zMatrix: [[1, 2], [3, 4]])
        #expect(standard.physicalDataAspectRatio == 1.0)

        let shifted = HeatmapGrid(xValues: [-10, 10], yValues: [100, 110], zMatrix: [[1, 2], [3, 4]])
        #expect(shifted.physicalDataAspectRatio == 2.0)

        let inverted = HeatmapGrid(xValues: [10, 0], yValues: [0, 5], zMatrix: [[1, 2], [3, 4]])
        #expect(inverted.physicalDataAspectRatio == 2.0)

        let single = HeatmapGrid(xValues: [5], yValues: [5], zMatrix: [[1]])
        #expect(single.physicalDataAspectRatio == nil)
    }

    @Test("AFMHeatmapPayloadBuilder defaults to physical aspect")
    func afmPayloadDefaultsToPhysicalAspect() throws {
        let xCoords = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]
        let yCoords = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]
        let values = yCoords.map { y in xCoords.map { x in x + y } }
        let channel = CanonicalAFMChannel(
            id: "ch0-HeightRetrace",
            sourceIndex: 0,
            sourceLabel: "HeightRetrace",
            semanticTypeRaw: "Height",
            displayLabel: "HeightRetrace",
            values: values,
            canonicalUnit: "nm",
            sourceUnit: "m",
            provenance: AFMChannelProvenance(planefit: nil, planefitOrder: nil, flattenOrder: nil, planefitOffset: nil, planefitXSlope: nil, planefitYSlope: nil)
        )
        let dataset = CanonicalAFMDataset(
            sourceRef: "/tmp/test.ibw",
            title: "TestWave",
            xCoordinates: xCoords,
            yCoordinates: yCoords,
            channels: [channel],
            sourceMetadata: AFMSourceProvenance(sourceFilePath: "/tmp/test.ibw", waveName: "TestWave", sourceWidth: 6, sourceHeight: 6, rawNote: "")
        )
        let processed = AFMProcessingPipeline.process(
            channel: channel,
            xCoordinates: dataset.xCoordinates,
            yCoordinates: dataset.yCoordinates,
            configuration: .init(activeChannelID: channel.id)
        )
        let payload = try AFMHeatmapPayloadBuilder.build(
            dataset: dataset,
            processed: processed,
            options: .init(workflowID: "afm")
        )
        #expect(payload.aspectPolicy == .physical)
    }

    @Test("RSMHeatmapPayloadBuilder defaults to fill aspect")
    func rsmPayloadDefaultsToFillAspect() throws {
        let pts = [
            CanonicalRSMPoint(h: 0, k: 0, l: 0, detector: 10),
            CanonicalRSMPoint(h: 1, k: 0, l: 0, detector: 20),
            CanonicalRSMPoint(h: 0, k: 0, l: 1, detector: 30),
            CanonicalRSMPoint(h: 1, k: 0, l: 1, detector: 40)
        ]
        let dataset = CanonicalRSMDataset(
            points: pts,
            title: "RSM Test",
            sourceRef: "test.dat",
            detectorColumnName: "Intensity"
        )
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset)
        #expect(payload.aspectPolicy == .fill)
    }
}
