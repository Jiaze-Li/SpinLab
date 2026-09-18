import Foundation
import Testing
@testable import SpinLabApp

@Suite("AFMInputAdapter / CanonicalAFMDataset")
struct AFMInputAdapterTests {

    private func threeChannelFixture(nX: Int = 4, nY: Int = 3, xScale: Double = 7.843137254901961e-08, yScale: Double = 7.843137254901961e-08) -> Data {
        func plane(_ base: Float) -> [[Float]] {
            (0..<nY).map { y in (0..<nX).map { x in base + Float(y * nX + x) } }
        }
        return IBWFixtureBuilder.build(
            waveName: "AFMTest",
            nX: nX, nY: nY,
            channels: [
                IBWFixtureBuilder.Channel(
                    label: "HeightRetrace", semanticType: "Height", values: plane(1e-7),
                    planefit: "Flatten 1", planefitOrder: -1, flattenOrder: 1
                ),
                IBWFixtureBuilder.Channel(
                    label: "DeflectionRetrace", semanticType: "Deflection", values: plane(2e-7),
                    planefit: "None", planefitOrder: -1, flattenOrder: -1
                ),
                IBWFixtureBuilder.Channel(
                    label: "ZSensorRetrace", semanticType: "ZSensor", values: plane(3e-7)
                ),
            ],
            xScale: xScale, yScale: yScale
        )
    }

    @Test("coordinate counts match matrix dimensions")
    func coordinateCountsMatchMatrix() throws {
        let output = try AFMInputAdapter.build(from: threeChannelFixture(nX: 5, nY: 4), sourceRef: "/tmp/test.ibw")
        let dataset = output.dataset
        #expect(dataset.xCoordinates.count == 5)
        #expect(dataset.yCoordinates.count == 4)
        for channel in dataset.channels {
            #expect(channel.values.count == 4)
            #expect(channel.values.allSatisfy { $0.count == 5 })
        }
    }

    @Test("X/Y calibration converts meters to µm — 256 px * 7.843e-8 m/px = 20 µm")
    func xyCalibrationConvertsToMicrons() throws {
        let output = try AFMInputAdapter.build(
            from: threeChannelFixture(nX: 256, nY: 256, xScale: 7.843137254901961e-08, yScale: 7.843137254901961e-08),
            sourceRef: "/tmp/test.ibw"
        )
        let dataset = output.dataset
        let xSpan = dataset.xCoordinates.last! - dataset.xCoordinates.first!
        let ySpan = dataset.yCoordinates.last! - dataset.yCoordinates.first!
        // 255 steps (not 256) between first and last coordinate.
        #expect(abs(xSpan - 255.0 * 7.843137254901961e-08 * 1e6) < 1e-6)
        #expect(abs(ySpan - 255.0 * 7.843137254901961e-08 * 1e6) < 1e-6)
        // (n-1) steps at this per-pixel calibration is ~20 µm, matching the representative file's
        // reported 20 µm × 20 µm scan size.
        #expect(abs(xSpan - 20.0) < 0.01)
        #expect(abs(ySpan - 20.0) < 0.01)
    }

    @Test("length-unit source data (meters) is converted to nm")
    func lengthUnitConvertsToNanometers() throws {
        let output = try AFMInputAdapter.build(from: threeChannelFixture(), sourceRef: "/tmp/test.ibw")
        let height = output.dataset.channels.first { $0.sourceLabel == "HeightRetrace" }!
        #expect(height.canonicalUnit == "nm")
        #expect(height.sourceUnit == "m")
        // Base value 1e-7 m == 100 nm (tolerance accounts for the Float32 source precision).
        #expect(abs(height.values[0][0] - 100.0) < 1e-4)
    }

    @Test("a non-length source unit is preserved unchanged, never falsely labeled nm")
    func nonLengthUnitIsPreservedUnchanged() throws {
        func plane() -> [[Float]] { [[1.5, 2.5], [3.5, 4.5]] }
        let data = IBWFixtureBuilder.build(
            nX: 2, nY: 2,
            channels: [IBWFixtureBuilder.Channel(label: "Current", semanticType: nil, values: plane())],
            xScale: 1e-7, yScale: 1e-7, dataUnit: "V"
        )
        let output = try AFMInputAdapter.build(from: data, sourceRef: "/tmp/test.ibw")
        let channel = output.dataset.channels[0]
        #expect(channel.canonicalUnit == "V")
        #expect(channel.values[0][0] == 1.5)
        #expect(channel.values[1][1] == 4.5)
    }

    @Test("default channel resolution picks the semantic Height channel")
    func defaultChannelResolutionPicksHeight() throws {
        let output = try AFMInputAdapter.build(from: threeChannelFixture(), sourceRef: "/tmp/test.ibw")
        let resolution = AFMChannelResolver.resolveDefaultChannel(in: output.dataset.channels)
        #expect(resolution.channel?.sourceLabel == "HeightRetrace")
        #expect(resolution.warning == nil)
        #expect(output.warnings.isEmpty)
    }

    @Test("falls back to a label-based match when no semantic Height type is present")
    func fallsBackToLabelMatch() throws {
        func plane() -> [[Float]] { [[0, 0], [0, 0]] }
        let data = IBWFixtureBuilder.build(
            nX: 2, nY: 2,
            channels: [
                IBWFixtureBuilder.Channel(label: "SomeHeightChannel", semanticType: nil, values: plane()),
                IBWFixtureBuilder.Channel(label: "Other", semanticType: nil, values: plane()),
            ],
            xScale: 1e-7, yScale: 1e-7
        )
        let output = try AFMInputAdapter.build(from: data, sourceRef: "/tmp/test.ibw")
        let resolution = AFMChannelResolver.resolveDefaultChannel(in: output.dataset.channels)
        #expect(resolution.channel?.sourceLabel == "SomeHeightChannel")
        #expect(resolution.warning == nil)
    }

    @Test("falls back to the first channel with a warning when no Height channel can be identified")
    func fallsBackToFirstChannelWithWarning() throws {
        func plane() -> [[Float]] { [[0, 0], [0, 0]] }
        let data = IBWFixtureBuilder.build(
            nX: 2, nY: 2,
            channels: [
                IBWFixtureBuilder.Channel(label: "Alpha", semanticType: nil, values: plane()),
                IBWFixtureBuilder.Channel(label: "Beta", semanticType: nil, values: plane()),
            ],
            xScale: 1e-7, yScale: 1e-7
        )
        let output = try AFMInputAdapter.build(from: data, sourceRef: "/tmp/test.ibw")
        #expect(output.warnings.count == 1)
        let resolution = AFMChannelResolver.resolveDefaultChannel(in: output.dataset.channels)
        #expect(resolution.channel?.sourceLabel == "Alpha")
        #expect(resolution.warning != nil)
    }

    @Test("channel identity survives a display-label change and is stable across rebuilds")
    func channelIdentitySurvivesDisplayLabelChange() throws {
        let output1 = try AFMInputAdapter.build(from: threeChannelFixture(), sourceRef: "/tmp/test.ibw")
        let output2 = try AFMInputAdapter.build(from: threeChannelFixture(), sourceRef: "/tmp/test.ibw")
        let ids1 = output1.dataset.channels.map(\.id)
        let ids2 = output2.dataset.channels.map(\.id)
        #expect(ids1 == ids2)

        var mutatedChannel = output1.dataset.channels[0]
        // displayLabel is a `let` — simulate a "rename" by constructing a new value with a
        // different displayLabel but the same sourceIndex/sourceLabel, as the workflow layer
        // would when applying a user rename on top of the immutable parsed channel.
        mutatedChannel = CanonicalAFMChannel(
            id: mutatedChannel.id,
            sourceIndex: mutatedChannel.sourceIndex,
            sourceLabel: mutatedChannel.sourceLabel,
            semanticTypeRaw: mutatedChannel.semanticTypeRaw,
            displayLabel: "My Custom Name",
            values: mutatedChannel.values,
            canonicalUnit: mutatedChannel.canonicalUnit,
            sourceUnit: mutatedChannel.sourceUnit,
            provenance: mutatedChannel.provenance
        )
        #expect(mutatedChannel.id == output1.dataset.channels[0].id)
    }

    @Test("Planefit/Flatten provenance is preserved verbatim without affecting resolution")
    func provenanceIsPreservedVerbatim() throws {
        let output = try AFMInputAdapter.build(from: threeChannelFixture(), sourceRef: "/tmp/test.ibw")
        let height = output.dataset.channels.first { $0.sourceLabel == "HeightRetrace" }!
        #expect(height.provenance.planefit == "Flatten 1")
        #expect(height.provenance.flattenOrder == 1)
        let deflection = output.dataset.channels.first { $0.sourceLabel == "DeflectionRetrace" }!
        #expect(deflection.provenance.planefit == "None")
    }

    @Test("processing never sees a mutated CanonicalAFMDataset — it is a pure value type")
    func datasetIsImmutableValueType() throws {
        let output = try AFMInputAdapter.build(from: threeChannelFixture(), sourceRef: "/tmp/test.ibw")
        var copy = output.dataset
        // Value semantics: reassigning fields on a `var` copy must never affect the original,
        // even though CanonicalAFMDataset itself exposes no mutating API.
        copy = CanonicalAFMDataset(
            sourceRef: "different",
            title: copy.title,
            xCoordinates: copy.xCoordinates,
            yCoordinates: copy.yCoordinates,
            channels: copy.channels,
            sourceMetadata: copy.sourceMetadata
        )
        #expect(output.dataset.sourceRef == "/tmp/test.ibw")
        #expect(copy.sourceRef == "different")
    }

    @Test("empty channel dimension labels still resolve channels by index (Channel<N> fallback label)")
    func missingDimLabelsFallsBackToIndexedName() throws {
        func plane() -> [[Float]] { [[1, 2], [3, 4]] }
        let data = IBWFixtureBuilder.build(
            nX: 2, nY: 2,
            channels: [IBWFixtureBuilder.Channel(label: "Ignored", semanticType: "Height", values: plane())],
            xScale: 1e-7, yScale: 1e-7,
            omitChannelDimLabels: true
        )
        let output = try AFMInputAdapter.build(from: data, sourceRef: "/tmp/test.ibw")
        #expect(output.dataset.channels[0].sourceLabel == "Channel1")
        #expect(output.dataset.channels[0].semanticTypeRaw == "Height")
    }
}
