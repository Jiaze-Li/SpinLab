import Foundation
import Testing
@testable import SpinLabApp

@Suite("AFMHeatmapPayloadBuilder")
struct AFMHeatmapPayloadBuilderTests {

    private func makeDataset(nX: Int = 4, nY: Int = 3) -> (CanonicalAFMDataset, CanonicalAFMChannel) {
        let xCoords = (0..<nX).map { Double($0) }
        let yCoords = (0..<nY).map { Double($0) }
        let values = yCoords.map { y in xCoords.map { x in x + y } }
        let channel = CanonicalAFMChannel(
            id: "ch0-HeightRetrace", sourceIndex: 0, sourceLabel: "HeightRetrace",
            semanticTypeRaw: "Height", displayLabel: "HeightRetrace", values: values,
            canonicalUnit: "nm", sourceUnit: "m",
            provenance: AFMChannelProvenance(planefit: nil, planefitOrder: nil, flattenOrder: nil, planefitOffset: nil, planefitXSlope: nil, planefitYSlope: nil)
        )
        let dataset = CanonicalAFMDataset(
            sourceRef: "/tmp/test.ibw", title: "TestWave", xCoordinates: xCoords, yCoordinates: yCoords,
            channels: [channel],
            sourceMetadata: AFMSourceProvenance(sourceFilePath: "/tmp/test.ibw", waveName: "TestWave", sourceWidth: nX, sourceHeight: nY, rawNote: "")
        )
        return (dataset, channel)
    }

    @Test("payload X/Y coordinate counts match the dataset")
    func payloadCoordinateCountsMatchDataset() throws {
        let (dataset, channel) = makeDataset(nX: 5, nY: 4)
        let processed = AFMProcessingPipeline.process(channel: channel, xCoordinates: dataset.xCoordinates, yCoordinates: dataset.yCoordinates, configuration: .init(activeChannelID: channel.id))
        let payload = try AFMHeatmapPayloadBuilder.build(dataset: dataset, processed: processed, options: .init(workflowID: "afm"))
        #expect(payload.grid.xValues.count == 5)
        #expect(payload.grid.yValues.count == 4)
        #expect(payload.grid.isValid)
    }

    @Test("default labels/units match the selected channel's semantics")
    func defaultLabelsMatchChannelSemantics() throws {
        let (dataset, channel) = makeDataset()
        let processed = AFMProcessingPipeline.process(channel: channel, xCoordinates: dataset.xCoordinates, yCoordinates: dataset.yCoordinates, configuration: .init(activeChannelID: channel.id))
        let payload = try AFMHeatmapPayloadBuilder.build(dataset: dataset, processed: processed, options: .init(workflowID: "afm"))
        #expect(payload.title == "TestWave")
        #expect(payload.xLabel.contains("µm"))
        #expect(payload.yLabel.contains("µm"))
        #expect(payload.zLabel == "HeightRetrace (nm)")
    }

    @Test("explicit option overrides win over defaults")
    func explicitOptionsOverrideDefaults() throws {
        let (dataset, channel) = makeDataset()
        let processed = AFMProcessingPipeline.process(channel: channel, xCoordinates: dataset.xCoordinates, yCoordinates: dataset.yCoordinates, configuration: .init(activeChannelID: channel.id))
        let payload = try AFMHeatmapPayloadBuilder.build(
            dataset: dataset, processed: processed,
            options: .init(workflowID: "afm", title: "Custom Title", zLabel: "Custom Z")
        )
        #expect(payload.title == "Custom Title")
        #expect(payload.zLabel == "Custom Z")
    }

    @Test("Heatmap payload validates and renders non-empty PNG through the existing pipeline")
    func payloadRendersNonEmptyPNG() throws {
        let (dataset, channel) = makeDataset(nX: 6, nY: 5)
        let processed = AFMProcessingPipeline.process(channel: channel, xCoordinates: dataset.xCoordinates, yCoordinates: dataset.yCoordinates, configuration: .init(activeChannelID: channel.id))
        let payload = try AFMHeatmapPayloadBuilder.build(dataset: dataset, processed: processed, options: .init(workflowID: "afm"))
        let output = try HeatmapRenderPipeline.render(HeatmapRenderPipeline.Input(payload: payload))
        #expect(!output.imageData.isEmpty)
        let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        #expect([UInt8](output.imageData.prefix(4)) == pngHeader)
    }

    @Test("throws on a dimension mismatch between processed channel and dataset coordinates")
    func throwsOnDimensionMismatch() {
        let (dataset, channel) = makeDataset(nX: 4, nY: 3)
        let badProcessed = ProcessedAFMChannel(
            sourceChannelID: channel.id, values: [[1, 2], [3, 4]],   // wrong shape
            canonicalUnit: "nm", displayLabel: "HeightRetrace",
            configuration: .init(activeChannelID: channel.id), warnings: []
        )
        #expect(throws: AFMHeatmapPayloadBuilderError.self) {
            try AFMHeatmapPayloadBuilder.build(dataset: dataset, processed: badProcessed, options: .init(workflowID: "afm"))
        }
    }
}
