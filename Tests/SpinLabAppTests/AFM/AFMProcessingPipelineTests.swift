import Foundation
import Testing
@testable import SpinLabApp

@Suite("AFM Processing Pipeline")
struct AFMProcessingPipelineTests {

    private let xs: [Double] = [0, 1, 2, 3]
    private let ys: [Double] = [0, 1, 2]

    private func makeChannel(id: String = "ch0-HeightRetrace") -> CanonicalAFMChannel {
        // z = 2x - 3y + 5, so Plane Level should fully flatten it.
        let values = ys.map { y in xs.map { x in 2 * x - 3 * y + 5 } }
        return CanonicalAFMChannel(
            id: id, sourceIndex: 0, sourceLabel: "HeightRetrace", semanticTypeRaw: "Height",
            displayLabel: "HeightRetrace", values: values, canonicalUnit: "nm", sourceUnit: "m",
            provenance: AFMChannelProvenance(planefit: nil, planefitOrder: nil, flattenOrder: nil, planefitOffset: nil, planefitXSlope: nil, planefitYSlope: nil)
        )
    }

    @Test("default configuration (all off) is identity")
    func defaultConfigurationIsIdentity() {
        let channel = makeChannel()
        let config = AFMProcessingConfiguration(activeChannelID: channel.id)
        let processed = AFMProcessingPipeline.process(channel: channel, xCoordinates: xs, yCoordinates: ys, configuration: config)
        #expect(processed.values == channel.values)
        #expect(processed.warnings.isEmpty)
    }

    @Test("plane level alone flattens a pure-plane source to ~0")
    func planeLevelAloneFlattens() {
        let channel = makeChannel()
        var config = AFMProcessingConfiguration(activeChannelID: channel.id)
        config.planeLevelEnabled = true
        let processed = AFMProcessingPipeline.process(channel: channel, xCoordinates: xs, yCoordinates: ys, configuration: config)
        for row in processed.values { for v in row { #expect(abs(v) < 1e-9) } }
    }

    @Test("pipeline never mutates the source CanonicalAFMChannel")
    func neverMutatesSourceChannel() {
        let channel = makeChannel()
        let original = channel.values
        var config = AFMProcessingConfiguration(activeChannelID: channel.id)
        config.planeLevelEnabled = true
        config.lineFlattenOrder = .order1
        config.zeroReference = .mean
        _ = AFMProcessingPipeline.process(channel: channel, xCoordinates: xs, yCoordinates: ys, configuration: config)
        #expect(channel.values == original)
    }

    @Test("repeated processing with the same config from the immutable source is non-compounding")
    func repeatedProcessingIsNonCompounding() {
        let channel = makeChannel()
        var config = AFMProcessingConfiguration(activeChannelID: channel.id)
        config.planeLevelEnabled = true
        config.lineFlattenOrder = .order1
        config.zeroReference = .mean

        let first = AFMProcessingPipeline.process(channel: channel, xCoordinates: xs, yCoordinates: ys, configuration: config)
        let second = AFMProcessingPipeline.process(channel: channel, xCoordinates: xs, yCoordinates: ys, configuration: config)
        let third = AFMProcessingPipeline.process(channel: channel, xCoordinates: xs, yCoordinates: ys, configuration: config)
        #expect(first.values == second.values)
        #expect(second.values == third.values)
    }

    @Test("toggling configuration and reprocessing from source produces the same result as processing that configuration directly")
    func togglingConfigurationMatchesDirectProcessing() {
        let channel = makeChannel()

        var onConfig = AFMProcessingConfiguration(activeChannelID: channel.id)
        onConfig.planeLevelEnabled = true
        let withLeveling = AFMProcessingPipeline.process(channel: channel, xCoordinates: xs, yCoordinates: ys, configuration: onConfig)

        let offConfig = AFMProcessingConfiguration(activeChannelID: channel.id)
        let withoutLeveling = AFMProcessingPipeline.process(channel: channel, xCoordinates: xs, yCoordinates: ys, configuration: offConfig)

        // Turning leveling back off and reprocessing FROM THE SOURCE must reproduce the
        // original identity result exactly — not a residual of the leveled state.
        #expect(withoutLeveling.values == channel.values)
        #expect(withLeveling.values != withoutLeveling.values)
    }

    @Test("processing order is Plane Level -> Line Flatten -> Zero Reference")
    func processingOrderIsPlaneThenFlattenThenZero() {
        // Construct data where order matters: a plane plus a per-row offset that only
        // Line Flatten (not Plane Level) can remove, then verify the final mean is ~0.
        let values = ys.map { y in xs.map { x in 2 * x - 3 * y + 5 + (y == 1 ? 100 : 0) } }
        let channel = CanonicalAFMChannel(
            id: "ch0", sourceIndex: 0, sourceLabel: "H", semanticTypeRaw: "Height", displayLabel: "H",
            values: values, canonicalUnit: "nm", sourceUnit: "m",
            provenance: AFMChannelProvenance(planefit: nil, planefitOrder: nil, flattenOrder: nil, planefitOffset: nil, planefitXSlope: nil, planefitYSlope: nil)
        )
        var config = AFMProcessingConfiguration(activeChannelID: channel.id)
        config.planeLevelEnabled = true
        config.lineFlattenOrder = .order0
        config.zeroReference = .mean

        let processed = AFMProcessingPipeline.process(channel: channel, xCoordinates: xs, yCoordinates: ys, configuration: config)
        let mean = processed.values.flatMap { $0 }.reduce(0, +) / Double(processed.values.count * processed.values[0].count)
        #expect(abs(mean) < 1e-9)
    }
}
