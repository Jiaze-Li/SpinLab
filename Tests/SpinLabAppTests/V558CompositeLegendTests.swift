import Foundation
import Testing
@testable import SpinLabApp

// MARK: - V558CompositeLegendTests
//
// v5.5.8.1: same-tier-ambiguous outcomes now compose a multi-dimension legend label
// (e.g. "100 mJ / 150 mT") instead of falling back to the workflow's declared semantic
// label. Composite-building lives entirely inside LegendResolver/LegendDimensionResolver
// (Sources/SpinLabApp/Workbench/Modules/PlotSystem/Legend/) — no workflow renderer
// changed to support this.

@Suite("v5.5.8.1 — LegendResolver composite ambiguous-tier labels")
struct V558CompositeLegendTests {

    // MARK: - Two varying dimensions in the same tier produce composite labels

    @Test("Two dimensions varying at the same tier produce a composite label per series")
    func twoDimensionsProduceCompositeLabels() {
        let resolver = LegendDimensionResolver(chain: LegendDimensionResolver.defaultChain)
        let meta: [[String: String]] = [
            ["energy": "100 mJ", "pressure": "150 mT"],
            ["energy": "80 mJ",  "pressure": "160 mT"],
            ["energy": "115 mJ", "pressure": "160 mT"],
        ]
        let result = resolver.resolve(seriesMetadata: meta)
        guard case .ambiguous(let dims, let values) = result else {
            Issue.record("Expected .ambiguous, got \(result)")
            return
        }
        #expect(dims.map(\.key) == ["energy", "pressure"])
        #expect(values == [["100 mJ", "150 mT"], ["80 mJ", "160 mT"], ["115 mJ", "160 mT"]])

        let input = LegendResolutionInput(series: [
            .init(identityKey: "s1", semanticLabel: "S1", metadata: meta[0]),
            .init(identityKey: "s2", semanticLabel: "S2", metadata: meta[1]),
            .init(identityKey: "s3", semanticLabel: "S3", metadata: meta[2]),
        ])
        let output = LegendResolver.resolve(input)
        #expect(output.labels == ["100 mJ / 150 mT", "80 mJ / 160 mT", "115 mJ / 160 mT"])
        guard case .resolvedComposite(let dimNames) = output.status else {
            Issue.record("Expected .resolvedComposite, got \(output.status)")
            return
        }
        #expect(dimNames == ["Energy", "Pressure"])
        #expect(output.legendDimensionDisplayName == "Energy / Pressure")
    }

    // MARK: - RT LNO3/LNO4/LNO5 — the exact case from the manual verification

    @Test("RT LNO3/LNO4/LNO5 real sample metadata produces the exact composite legend")
    func rtLNO345ProducesExactCompositeLegend() {
        // Real sample.json numericDisplay values for LNO3/4/5 | STO | 001, run through the
        // exact production metadata builder used by AnalyzeRTWorkflowUseCase.
        let samples: [(sampleKey: String, numericDisplay: [String: String])] = [
            ("LNO3||STO|001", ["厚度": "3000 ps", "氧压": "150 mT", "温度": "700 °C", "能量": "100 mJ"]),
            ("LNO4||STO|001", ["厚度": "3000 ps", "氧压": "160 mT", "温度": "700 °C", "能量": "80 mJ"]),
            ("LNO5||STO|001", ["厚度": "3000 ps", "氧压": "160 mT", "温度": "700 °C", "能量": "115 mJ"]),
        ]
        let series: [LegendResolutionInput.SeriesEntry] = samples.map { s in
            let hit = WorkflowMeasurementSearchHit(
                sidecarPath: "/tmp/\(s.sampleKey).json",
                measurementFilePath: "/tmp/\(s.sampleKey).dat",
                sourceFilePath: "/tmp/\(s.sampleKey).dat",
                workflowID: "RT",
                workflowDisplayName: "RT",
                workflowCanonicalID: "RT",
                batchID: String(s.sampleKey.prefix(4)),
                sampleKey: s.sampleKey,
                sampleSubstrate: "STO(001)",
                conditions: [:],
                channels: ["ch1"],
                appliedAt: Date()
            )
            let meta = WorkbenchSeriesMetadataBuilder.build(from: hit, numericDisplay: s.numericDisplay)
            return .init(identityKey: s.sampleKey, semanticLabel: "\(s.sampleKey) (ch1)", metadata: meta)
        }
        let output = LegendResolver.resolve(LegendResolutionInput(series: series))
        #expect(output.labels == ["100 mJ / 150 mT", "80 mJ / 160 mT", "115 mJ / 160 mT"])
        #expect(output.legendDimensionDisplayName == "Energy / Pressure")
    }

    // MARK: - Composite labels preserve configured tier dimension order

    @Test("Composite label component order follows chain order, not metadata insertion order")
    func compositePreservesChainOrder() {
        // Chain order within tier 1: field, device, harmonic, substrate, energy, pressure,
        // growthTemperature. Substrate + growthTemperature both vary here; substrate must
        // lead even though pressure/energy keys are absent and growthTemperature appears
        // "first" in this literal dictionary.
        let meta: [[String: String]] = [
            ["growthTemperature": "700", "substrate": "STO"],
            ["growthTemperature": "750", "substrate": "MgO"],
        ]
        let resolver = LegendDimensionResolver(chain: LegendDimensionResolver.defaultChain)
        guard case .ambiguous(let dims, let values) = resolver.resolve(seriesMetadata: meta) else {
            Issue.record("Expected .ambiguous")
            return
        }
        #expect(dims.map(\.key) == ["substrate", "growthTemperature"])
        #expect(values == [["STO", "700"], ["MgO", "750"]])
    }

    // MARK: - Lower-tier varying dimensions are excluded once a higher tier resolves

    @Test("Tier-0 temperature resolving excludes tier-1 varying dimensions from the composite")
    func higherTierResolutionExcludesLowerTierVariance() {
        let meta: [[String: String]] = [
            ["temperature": "80",  "energy": "1.5", "pressure": "50"],
            ["temperature": "300", "energy": "2.0", "pressure": "100"],
        ]
        let resolver = LegendDimensionResolver(chain: LegendDimensionResolver.defaultChain)
        let result = resolver.resolve(seriesMetadata: meta)
        guard case .resolved(let dim, let values) = result else {
            Issue.record("Expected .resolved (temperature, tier 0), got \(result)")
            return
        }
        #expect(dim.key == "temperature")
        #expect(values == ["80", "300"])
        // energy/pressure (tier 1) also vary here but must never surface — tier 0 already won.
    }

    @Test("Tier-1 ambiguity excludes tier-2 thickness even though thickness also varies")
    func tier1AmbiguityExcludesTier2Variance() {
        let meta: [[String: String]] = [
            ["energy": "1.5", "pressure": "50",  "thickness": "10"],
            ["energy": "2.0", "pressure": "100", "thickness": "20"],
        ]
        let resolver = LegendDimensionResolver(chain: LegendDimensionResolver.defaultChain)
        guard case .ambiguous(let dims, _) = resolver.resolve(seriesMetadata: meta) else {
            Issue.record("Expected .ambiguous at tier 1")
            return
        }
        #expect(dims.map(\.key) == ["energy", "pressure"])
        #expect(!dims.map(\.key).contains("thickness"))
    }

    // MARK: - One varying dimension still produces the existing simple (non-composite) labels

    @Test("Single varying dimension still resolves to a simple, non-composite label")
    func singleVaryingDimensionStaysSimple() {
        let input = LegendResolutionInput(series: [
            .init(identityKey: "s1", semanticLabel: "S1", metadata: ["energy": "1.5", "pressure": "50"]),
            .init(identityKey: "s2", semanticLabel: "S2", metadata: ["energy": "2.0", "pressure": "50"]),
        ])
        let output = LegendResolver.resolve(input)
        #expect(output.status == .resolved(dimension: "Energy"))
        #expect(output.labels == ["1.5", "2.0"])
    }

    // MARK: - User overrides still win over composite resolution

    @Test("User override wins over composite resolution")
    func userOverrideWinsOverComposite() {
        let input = LegendResolutionInput(
            series: [
                .init(identityKey: "s1", semanticLabel: "S1", metadata: ["energy": "100 mJ", "pressure": "150 mT"]),
                .init(identityKey: "s2", semanticLabel: "S2", metadata: ["energy": "80 mJ", "pressure": "160 mT"]),
            ],
            userOverrides: ["s1": "My Custom Name"]
        )
        let output = LegendResolver.resolve(input)
        #expect(output.labels == ["My Custom Name", "80 mJ / 160 mT"])
        guard case .resolvedComposite = output.status else {
            Issue.record("Expected .resolvedComposite status even though s1's label was overridden")
            return
        }
    }

    @Test("Pipeline-staged user override step wins over a composite resolved at the earlier pipeline step")
    func pipelineStagedOverrideWinsOverComposite() throws {
        let s1 = WorkbenchPlotSeries(label: "S1", x: [1], y: [1], metadata: ["energy": "100 mJ", "pressure": "150 mT"])
        let s2 = WorkbenchPlotSeries(label: "S2", x: [2], y: [2], metadata: ["energy": "80 mJ", "pressure": "160 mT"])
        var input = WorkbenchRenderPipeline.Input(
            payload: WorkbenchPlotPayload(
                workflowID: "test", workflowDisplayName: "test",
                title: "Test", axisMapping: .init(xField: "X", yField: "Y"),
                series: [s1, s2]
            )
        )
        input.seriesLabelOverrides = [0: "Renamed"]
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.displayPayload.series[0].label == "Renamed")
        #expect(output.displayPayload.series[1].label == "80 mJ / 160 mT")
        #expect(output.displayPayload.legendDimension == "Energy / Pressure")
    }

    // MARK: - Missing values are handled deterministically

    @Test("A series missing one of the varying dimensions gets the shared placeholder for that component")
    func missingComponentGetsSharedPlaceholder() {
        let input = LegendResolutionInput(series: [
            .init(identityKey: "s1", semanticLabel: "S1", metadata: ["energy": "100 mJ", "pressure": "150 mT"]),
            .init(identityKey: "s2", semanticLabel: "S2", metadata: ["energy": "80 mJ"]), // no pressure
            .init(identityKey: "s3", semanticLabel: "S3", metadata: ["energy": "115 mJ", "pressure": "160 mT"]),
        ])
        let output = LegendResolver.resolve(input)
        #expect(output.labels == [
            "100 mJ / 150 mT",
            "80 mJ / \(LegendResolver.missingValuePlaceholder)",
            "115 mJ / 160 mT",
        ])
    }

    @Test("A series with none of the varying dimensions falls back to its declared semantic label, not an all-placeholder composite")
    func seriesWithNoVaryingValuesFallsBackToSemanticLabel() {
        let input = LegendResolutionInput(series: [
            .init(identityKey: "s1", semanticLabel: "S1", metadata: ["energy": "100 mJ", "pressure": "150 mT"]),
            .init(identityKey: "s2", semanticLabel: "Unmeasured Series", metadata: [:]),
            .init(identityKey: "s3", semanticLabel: "S3", metadata: ["energy": "115 mJ", "pressure": "160 mT"]),
        ])
        let output = LegendResolver.resolve(input)
        #expect(output.labels == ["100 mJ / 150 mT", "Unmeasured Series", "115 mJ / 160 mT"])
        // Never a malformed "— / —" for a series with nothing to contribute.
        #expect(!output.labels.contains("\(LegendResolver.missingValuePlaceholder) / \(LegendResolver.missingValuePlaceholder)"))
    }

    // MARK: - Existing non-label series data is untouched by composite resolution

    @Test("Composite resolution only rewrites .label — x, y, identity, and series order are byte-for-byte unchanged")
    func compositeResolutionOnlyTouchesLabel() throws {
        let s1 = WorkbenchPlotSeries(
            label: "S1", x: [1.0, 2.0, 3.0], y: [10.0, 20.0, 30.0],
            sampleID: "id-1", metadata: ["energy": "100 mJ", "pressure": "150 mT"]
        )
        let s2 = WorkbenchPlotSeries(
            label: "S2", x: [4.0, 5.0, 6.0], y: [40.0, 50.0, 60.0],
            sampleID: "id-2", metadata: ["energy": "80 mJ", "pressure": "160 mT"]
        )
        let input = WorkbenchRenderPipeline.Input(
            payload: WorkbenchPlotPayload(
                workflowID: "test", workflowDisplayName: "test",
                title: "Test", axisMapping: .init(xField: "X", yField: "Y"),
                series: [s1, s2]
            )
        )
        let output = try WorkbenchRenderPipeline.render(input)
        let resultSeries = output.displayPayload.series
        #expect(resultSeries.count == 2)
        #expect(resultSeries[0].x == s1.x && resultSeries[0].y == s1.y)
        #expect(resultSeries[1].x == s2.x && resultSeries[1].y == s2.y)
        #expect(resultSeries[0].sampleID == "id-1")
        #expect(resultSeries[1].sampleID == "id-2")
        #expect(resultSeries.map(\.label) == ["100 mJ / 150 mT", "80 mJ / 160 mT"])
    }
}
