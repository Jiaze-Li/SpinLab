import Foundation
import Testing
@testable import SpinLabApp

// MARK: - V536SampleMetadataSubstrateTests
//
// Verifies that _buildSampleMetadata uses the raw key processing component
// when no rule-set treatment entries are present, so unregistered tokens
// (e.g. "o", "b") still distinguish series in the legend resolver.

@Suite("v5.3.6 — SampleMetadata substrate fallback")
struct V536SampleMetadataSubstrateTests {

    // MARK: - Helpers

    private func makeHit(sampleKey: String, temperature: String? = nil) -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: "/fake/\(sampleKey).sidecar",
            measurementFilePath: "/fake/\(sampleKey).lvm",
            sourceFilePath: "/fake/\(sampleKey).lvm",
            workflowID: "xy",
            workflowDisplayName: "XY Rotation",
            workflowCanonicalID: "xy",
            batchID: "B25",
            sampleKey: sampleKey,
            sampleSubstrate: "",
            conditions: temperature.map { ["temperature": $0] } ?? [:],
            channels: [],
            appliedAt: Date()
        )
    }

    // MARK: - Raw processing token fallback

    @Test("Different raw processing tokens produce different substrate metadata")
    func differentRawTokensProduceDifferentSubstrate() {
        let hitO = makeHit(sampleKey: "B25|o|STO|111")
        let hitB = makeHit(sampleKey: "B25|b|STO|111")

        let metaO = IngestThreeOmegaSelectionsUseCase._buildSampleMetadata(from: hitO)
        let metaB = IngestThreeOmegaSelectionsUseCase._buildSampleMetadata(from: hitB)

        // Both substrates non-empty and distinct
        #expect(!(metaO["substrate"] ?? "").isEmpty, "o-substrate should be non-empty")
        #expect(!(metaB["substrate"] ?? "").isEmpty, "b-substrate should be non-empty")
        #expect(metaO["substrate"] != metaB["substrate"],
                "o and b samples must produce different substrate metadata so resolver can distinguish them")
    }

    @Test("Same raw processing token produces same substrate metadata")
    func sameRawTokenProducesSameSubstrate() {
        let hit1 = makeHit(sampleKey: "B25|o|STO|111")
        let hit2 = makeHit(sampleKey: "B25|o|STO|111")

        let meta1 = IngestThreeOmegaSelectionsUseCase._buildSampleMetadata(from: hit1)
        let meta2 = IngestThreeOmegaSelectionsUseCase._buildSampleMetadata(from: hit2)

        #expect(meta1["substrate"] == meta2["substrate"],
                "Same key must produce identical substrate metadata")
    }

    @Test("Empty processing token falls through to material+orientation only")
    func emptyProcessingTokenUsesMaterialOrientation() {
        let hit = makeHit(sampleKey: "B25||STO|111")

        let meta = IngestThreeOmegaSelectionsUseCase._buildSampleMetadata(from: hit)

        // No treatment → substrate = "STO 111" (or equivalent normalised)
        let substrate = meta["substrate"] ?? ""
        #expect(!substrate.isEmpty, "Substrate must be non-empty even when processing is absent")
        #expect(!substrate.contains("||"), "Substrate must not contain empty segments")
    }

    // MARK: - Resolver integration: same temperature, substrate varies

    @Test("Resolver resolves substrate when all temperatures identical and substrate differs via raw token")
    func resolverPicksSubstrateWhenTempSameAndSubstrateDiffers() {
        let hitO = makeHit(sampleKey: "B25|o|STO|111", temperature: "80K")
        let hitB = makeHit(sampleKey: "B25|b|STO|111", temperature: "80K")

        let metaO = IngestThreeOmegaSelectionsUseCase._buildSampleMetadata(from: hitO)
        let metaB = IngestThreeOmegaSelectionsUseCase._buildSampleMetadata(from: hitB)

        let resolver = LegendDimensionResolver(chain: LegendDimensionResolver.defaultChain)
        let result = resolver.resolve(seriesMetadata: [metaO, metaB])

        guard case .resolved(let dim, let values) = result else {
            Issue.record("Expected .resolved, got \(result)")
            return
        }
        #expect(dim.key == "substrate", "Resolver must pick substrate when temperature is same")
        #expect(values[0] != values[1], "Substrate labels must differ between o and b samples")
    }
}
