import Foundation
import Testing
@testable import SpinLabApp

// MARK: - V534LegendDimensionResolverTests

@Suite("v5.3.4 — LegendDimensionResolver")
struct V534LegendDimensionResolverTests {

    private let resolver = LegendDimensionResolver(chain: LegendDimensionResolver.defaultChain)

    // MARK: - Temperature wins (tier 0)

    @Test("Temperature varies → resolved as temperature")
    func temperatureVaries() {
        let meta: [[String: String]] = [
            ["temperature": "80",  "substrate": "STO", "energy": "2.0"],
            ["temperature": "200", "substrate": "STO", "energy": "2.0"],
            ["temperature": "300", "substrate": "STO", "energy": "2.0"],
        ]
        let result = resolver.resolve(seriesMetadata: meta)
        guard case .resolved(let dim, let values) = result else {
            Issue.record("Expected .resolved, got \(result)")
            return
        }
        #expect(dim.key == "temperature")
        #expect(dim.displayName == "Temperature (K)")
        #expect(values == ["80", "200", "300"])
    }

    // MARK: - Tier 1: single dimension varies

    @Test("Energy varies, temperature same → resolved as energy")
    func energyVaries() {
        let meta: [[String: String]] = [
            ["temperature": "80", "substrate": "STO", "energy": "1.5", "pressure": "50"],
            ["temperature": "80", "substrate": "STO", "energy": "2.0", "pressure": "50"],
        ]
        let result = resolver.resolve(seriesMetadata: meta)
        guard case .resolved(let dim, let values) = result else {
            Issue.record("Expected .resolved, got \(result)")
            return
        }
        #expect(dim.key == "energy")
        #expect(values == ["1.5", "2.0"])
    }

    @Test("Field varies, temperature same → resolved as field")
    func fieldVaries() {
        let meta: [[String: String]] = [
            ["temperature": "80", "field": "0T", "device": "0deg"],
            ["temperature": "80", "field": "2.5T", "device": "0deg"],
        ]
        let result = resolver.resolve(seriesMetadata: meta)
        guard case .resolved(let dim, let values) = result else {
            Issue.record("Expected .resolved, got \(result)")
            return
        }
        #expect(dim.key == "field")
        #expect(values == ["0T", "2.5T"])
    }

    @Test("Harmonic varies, temperature and field same → resolved as harmonic")
    func harmonicVaries() {
        let meta: [[String: String]] = [
            ["temperature": "80", "field": "0T", "harmonic": "1w"],
            ["temperature": "80", "field": "0T", "harmonic": "3w"],
        ]
        let result = resolver.resolve(seriesMetadata: meta)
        guard case .resolved(let dim, let values) = result else {
            Issue.record("Expected .resolved, got \(result)")
            return
        }
        #expect(dim.key == "harmonic")
        #expect(values == ["1w", "3w"])
    }

    @Test("Substrate varies, temperature same → resolved as substrate")
    func substrateVaries() {
        let meta: [[String: String]] = [
            ["temperature": "80", "substrate": "o",   "energy": "2.0"],
            ["temperature": "80", "substrate": "b",   "energy": "2.0"],
            ["temperature": "80", "substrate": "HF-STO(111)", "energy": "2.0"],
        ]
        let result = resolver.resolve(seriesMetadata: meta)
        guard case .resolved(let dim, let values) = result else {
            Issue.record("Expected .resolved, got \(result)")
            return
        }
        #expect(dim.key == "substrate")
        #expect(values == ["o", "b", "HF-STO(111)"])
    }

    // MARK: - Tier 1: multiple vary → ambiguous

    @Test("Energy and pressure both vary → ambiguous warning")
    func sameTierAmbiguous() {
        let meta: [[String: String]] = [
            ["temperature": "80", "substrate": "STO", "energy": "1.5", "pressure": "50"],
            ["temperature": "80", "substrate": "STO", "energy": "2.0", "pressure": "100"],
        ]
        let result = resolver.resolve(seriesMetadata: meta)
        guard case .ambiguous(let dims) = result else {
            Issue.record("Expected .ambiguous, got \(result)")
            return
        }
        let keys = Set(dims.map(\.key))
        #expect(keys == ["energy", "pressure"])
    }

    // MARK: - Tier 2: thickness

    @Test("Only thickness varies → resolved as thickness")
    func thicknessVaries() {
        let meta: [[String: String]] = [
            ["temperature": "80", "substrate": "STO", "energy": "2.0", "pressure": "50", "thickness": "10"],
            ["temperature": "80", "substrate": "STO", "energy": "2.0", "pressure": "50", "thickness": "20"],
        ]
        let result = resolver.resolve(seriesMetadata: meta)
        guard case .resolved(let dim, _) = result else {
            Issue.record("Expected .resolved, got \(result)")
            return
        }
        #expect(dim.key == "thickness")
    }

    // MARK: - Indeterminate

    @Test("All dimensions identical → indeterminate")
    func allIdentical() {
        let meta: [[String: String]] = [
            ["temperature": "80", "substrate": "STO", "energy": "2.0"],
            ["temperature": "80", "substrate": "STO", "energy": "2.0"],
        ]
        let result = resolver.resolve(seriesMetadata: meta)
        #expect(result == .indeterminate)
    }

    // MARK: - Numeric tolerance

    @Test("Numeric jitter within tolerance → treated as equal")
    func numericTolerance() {
        let meta: [[String: String]] = [
            ["temperature": "79.998", "substrate": "o"],
            ["temperature": "80.002", "substrate": "b"],
        ]
        let result = resolver.resolve(seriesMetadata: meta)
        // Temperature within 1% tolerance → considered same.
        // Substrate differs → resolved as substrate.
        guard case .resolved(let dim, _) = result else {
            Issue.record("Expected .resolved, got \(result)")
            return
        }
        #expect(dim.key == "substrate")
    }

    @Test("Numeric difference beyond tolerance → varies")
    func numericBeyondTolerance() {
        let meta: [[String: String]] = [
            ["temperature": "80",  "substrate": "STO"],
            ["temperature": "300", "substrate": "STO"],
        ]
        let result = resolver.resolve(seriesMetadata: meta)
        guard case .resolved(let dim, _) = result else {
            Issue.record("Expected .resolved, got \(result)")
            return
        }
        #expect(dim.key == "temperature")
    }

    // MARK: - Partial metadata

    @Test("Missing key on one series is ignored, only non-empty values compared")
    func partialMetadata() {
        let meta: [[String: String]] = [
            ["temperature": "80"],
            ["temperature": "80", "substrate": "STO"],
        ]
        // substrate: only one non-empty value → not enough to compare → does not vary.
        // All configured dimensions same or insufficient → indeterminate.
        let result = resolver.resolve(seriesMetadata: meta)
        #expect(result == .indeterminate)
    }

    // MARK: - Missing values ignored

    @Test("Missing device on one sample does not cause ambiguity with energy")
    func missingDeviceIgnored() {
        let meta: [[String: String]] = [
            ["temperature": "80K", "device": "wafer", "substrate": "o STO 111", "energy": "50 mJ"],
            ["temperature": "80K", "device": "wafer", "substrate": "o STO 111", "energy": "40 mJ"],
            ["temperature": "80K",                     "substrate": "o STO 111", "energy": "45 mJ"],
        ]
        let result = resolver.resolve(seriesMetadata: meta)
        guard case .resolved(let dim, let values) = result else {
            Issue.record("Expected .resolved, got \(result)")
            return
        }
        // device: "wafer"="wafer", missing ignored → same → doesn't vary
        // energy: 50≠40≠45 → varies → resolved
        #expect(dim.key == "energy")
        #expect(values == ["50 mJ", "40 mJ", "45 mJ"])
    }

    @Test("All values missing for a key → does not vary")
    func allMissing() {
        let meta: [[String: String]] = [
            ["temperature": "80", "substrate": "o"],
            ["temperature": "80", "substrate": "b"],
        ]
        // "device" key absent from both → does not vary
        let result = resolver.resolve(seriesMetadata: meta)
        guard case .resolved(let dim, _) = result else {
            Issue.record("Expected .resolved, got \(result)")
            return
        }
        #expect(dim.key == "substrate")
    }

    // MARK: - Single series

    @Test("Single series → resolved with highest-priority available key")
    func singleSeries() {
        let meta: [[String: String]] = [
            ["temperature": "300", "substrate": "STO"],
        ]
        let result = resolver.resolve(seriesMetadata: meta)
        guard case .resolved(let dim, let values) = result else {
            Issue.record("Expected .resolved, got \(result)")
            return
        }
        #expect(dim.key == "temperature")
        #expect(values == ["300"])
    }

    @Test("Empty input → indeterminate")
    func emptyInput() {
        let result = resolver.resolve(seriesMetadata: [])
        #expect(result == .indeterminate)
    }

    // MARK: - Custom chain

    @Test("Custom chain overrides default priorities")
    func customChain() {
        let custom = LegendDimensionResolver(chain: [
            .init(key: "substrate", displayName: "Substrate", tier: 0),
            .init(key: "temperature", displayName: "Temperature (K)", tier: 1),
        ])
        let meta: [[String: String]] = [
            ["temperature": "80",  "substrate": "o"],
            ["temperature": "300", "substrate": "b"],
        ]
        // Both vary, but substrate is tier 0 in custom chain.
        let result = custom.resolve(seriesMetadata: meta)
        guard case .resolved(let dim, _) = result else {
            Issue.record("Expected .resolved, got \(result)")
            return
        }
        #expect(dim.key == "substrate")
    }
}

// MARK: - Payload backward decode + pipeline reversal

@Suite("v5.3.4 — Payload & Pipeline")
struct V534PayloadPipelineTests {

    @Test("Legacy payload decode: missing fields get safe defaults")
    func legacyPayloadDecode() throws {
        // JSON without legendDimension or reverseSeriesForLegend
        let json = """
        {
            "schemaVersion": 1,
            "workflowID": "3w",
            "workflowDisplayName": "3w",
            "title": "Test",
            "axisMapping": {"xField": "X", "yField": "Y"},
            "series": [],
            "semanticParams": {},
            "styleParams": {}
        }
        """
        let data = json.data(using: .utf8)!
        let payload = try JSONDecoder().decode(WorkbenchPlotPayload.self, from: data)
        #expect(payload.legendDimension == nil)
        #expect(payload.reverseSeriesForLegend == false) // legacy payloads preserve original order
    }

    @Test("reverseSeriesForLegend: false preserves original series order")
    func noReversal() throws {
        let s1 = WorkbenchPlotSeries(label: "A", x: [1], y: [1])
        let s2 = WorkbenchPlotSeries(label: "B", x: [2], y: [2])
        let input = WorkbenchRenderPipeline.Input(
            payload: WorkbenchPlotPayload(
                workflowID: "test", workflowDisplayName: "test",
                title: "Test", axisMapping: .init(xField: "X", yField: "Y"),
                series: [s1, s2],
                reverseSeriesForLegend: false
            )
        )
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.manifestPayload.series.first?.label == "A")
        #expect(output.manifestPayload.series.last?.label == "B")
    }

    @Test("reverseSeriesForLegend: true reverses series so last becomes first")
    func withReversal() throws {
        let s1 = WorkbenchPlotSeries(label: "A", x: [1], y: [1])
        let s2 = WorkbenchPlotSeries(label: "B", x: [2], y: [2])
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "test",
            title: "Test", axisMapping: .init(xField: "X", yField: "Y"),
            series: [s1, s2],
            reverseSeriesForLegend: true
        )

        // Reversal is render-only (manifestPayload purity contract, v5.5.5 render-route
        // cleanup). `displaySeriesOrder` is the exact production helper the pipeline's
        // renderPayload reversal (step 4e) mirrors, so it's the correct render-time
        // equivalent to assert the reversal against.
        let displayOrder = displaySeriesOrder(for: payload)
        #expect(displayOrder.first?.label == "B")
        #expect(displayOrder.last?.label == "A")

        // manifestPayload must stay pristine: original (unreversed) order.
        let input = WorkbenchRenderPipeline.Input(payload: payload)
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.manifestPayload.series.first?.label == "A")
        #expect(output.manifestPayload.series.last?.label == "B")
    }

    @Test("Single series is not reversed even with flag true")
    func singleSeriesNoOp() throws {
        let s1 = WorkbenchPlotSeries(label: "Only", x: [1], y: [1])
        let input = WorkbenchRenderPipeline.Input(
            payload: WorkbenchPlotPayload(
                workflowID: "test", workflowDisplayName: "test",
                title: "Test", axisMapping: .init(xField: "X", yField: "Y"),
                series: [s1],
                reverseSeriesForLegend: true
            )
        )
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.manifestPayload.series.first?.label == "Only")
    }

    // MARK: - Pipeline auto-resolve from metadata

    @Test("Pipeline resolves substrate from metadata and updates labels")
    func pipelineAutoResolveSubstrate() throws {
        let s1 = WorkbenchPlotSeries(label: "80 K", x: [1], y: [1],
            metadata: ["temperature": "80", "substrate": "o"])
        let s2 = WorkbenchPlotSeries(label: "80 K", x: [2], y: [2],
            metadata: ["temperature": "80", "substrate": "b"])
        let input = WorkbenchRenderPipeline.Input(
            payload: WorkbenchPlotPayload(
                workflowID: "test", workflowDisplayName: "test",
                title: "Test", axisMapping: .init(xField: "X", yField: "Y"),
                series: [s1, s2]
            )
        )
        let output = try WorkbenchRenderPipeline.render(input)
        // Legend dimension resolution is render-only (manifestPayload purity contract).
        #expect(output.manifestPayload.legendDimension == nil)
        #expect(output.manifestPayload.series[0].label == "80 K")
        #expect(output.manifestPayload.series[1].label == "80 K")

        // Render-time equivalent: WorkbenchRenderPipeline.applyLegendDimensionResolution is
        // the exact helper the pipeline runs against renderPayload (step 4f) — assert the
        // resolved dimension/labels there.
        var renderPayload = input.payload
        WorkbenchRenderPipeline.applyLegendDimensionResolution(to: &renderPayload)
        #expect(renderPayload.legendDimension == "Substrate")
        #expect(renderPayload.series[0].label == "o")
        #expect(renderPayload.series[1].label == "b")
    }

    @Test("Pipeline keeps temperature labels when temperature varies")
    func pipelineAutoResolveTemperature() throws {
        let s1 = WorkbenchPlotSeries(label: "80 K", x: [1], y: [1],
            metadata: ["temperature": "80", "substrate": "STO"])
        let s2 = WorkbenchPlotSeries(label: "300 K", x: [2], y: [2],
            metadata: ["temperature": "300", "substrate": "STO"])
        let input = WorkbenchRenderPipeline.Input(
            payload: WorkbenchPlotPayload(
                workflowID: "test", workflowDisplayName: "test",
                title: "Test", axisMapping: .init(xField: "X", yField: "Y"),
                series: [s1, s2]
            )
        )
        let output = try WorkbenchRenderPipeline.render(input)
        // Legend dimension resolution is render-only (manifestPayload purity contract).
        #expect(output.manifestPayload.legendDimension == nil)
        #expect(output.manifestPayload.series[0].label == "80 K")
        #expect(output.manifestPayload.series[1].label == "300 K")

        // Render-time equivalent: labels updated to raw temperature values from metadata.
        var renderPayload = input.payload
        WorkbenchRenderPipeline.applyLegendDimensionResolution(to: &renderPayload)
        #expect(renderPayload.legendDimension == "Temperature (K)")
        #expect(renderPayload.series[0].label == "80")
        #expect(renderPayload.series[1].label == "300")
    }

    @Test("Pipeline skips resolver when legendDimension is pre-set")
    func pipelineSkipsWhenPreSet() throws {
        let s1 = WorkbenchPlotSeries(label: "A", x: [1], y: [1],
            metadata: ["temperature": "80", "substrate": "o"])
        let s2 = WorkbenchPlotSeries(label: "B", x: [2], y: [2],
            metadata: ["temperature": "80", "substrate": "b"])
        let input = WorkbenchRenderPipeline.Input(
            payload: WorkbenchPlotPayload(
                workflowID: "test", workflowDisplayName: "test",
                title: "Test", axisMapping: .init(xField: "X", yField: "Y"),
                series: [s1, s2],
                legendDimension: "Custom"
            )
        )
        let output = try WorkbenchRenderPipeline.render(input)
        // Labels unchanged — resolver did not run
        #expect(output.manifestPayload.series[0].label == "A")
        #expect(output.manifestPayload.series[1].label == "B")
        #expect(output.manifestPayload.legendDimension == "Custom")
    }

    @Test("Pipeline shows warning for ambiguous same-tier dimensions")
    func pipelineAmbiguousWarning() throws {
        let s1 = WorkbenchPlotSeries(label: "A", x: [1], y: [1],
            metadata: ["temperature": "80", "substrate": "o", "energy": "1.5"])
        let s2 = WorkbenchPlotSeries(label: "B", x: [2], y: [2],
            metadata: ["temperature": "80", "substrate": "b", "energy": "2.0"])
        let input = WorkbenchRenderPipeline.Input(
            payload: WorkbenchPlotPayload(
                workflowID: "test", workflowDisplayName: "test",
                title: "Test", axisMapping: .init(xField: "X", yField: "Y"),
                series: [s1, s2]
            )
        )
        let output = try WorkbenchRenderPipeline.render(input)
        // The ambiguity warning is already surfaced through output.warnings (and mirrored into
        // manifestPayload.semanticParams["_pipelineWarnings"] as non-destructive metadata) —
        // legendDimension itself is a render-only field and must stay nil on manifestPayload.
        #expect(output.manifestPayload.legendDimension == nil)
        #expect(output.warnings.contains { $0.contains("multiple dimensions vary at the same priority") })

        var renderPayload = input.payload
        WorkbenchRenderPipeline.applyLegendDimensionResolution(to: &renderPayload)
        #expect(renderPayload.legendDimension?.hasPrefix("⚠") == true)
    }

    // MARK: - Purity contract (positive proof)

    /// manifestPayload = "Persistence / library indexing | No UI overrides"
    /// (docs/architecture/workbench/STAGE2A_PAYLOAD_SEMANTICS_CLOSEOUT.md). Legend dimension
    /// resolution and series reversal are both render-only (WorkbenchRenderPipeline.render,
    /// steps 4e/4f) and must never leak into manifestPayload, regardless of how ambiguous or
    /// destructive the render-time resolution/reversal is. See also
    /// V532WorkbenchRenderPipelineTests.testRender_manifestPayloadExcludesChartStyleOverrides
    /// and testRender_manifestPayloadPreservesOriginalSeriesRenderMode for the general pipeline
    /// purity proof this suite's fixes rely on.
    @Test("manifestPayload stays pristine across legend-dimension resolution and reversal")
    func manifestPayloadStaysPristineAcrossLegendResolutionAndReversal() throws {
        let s1 = WorkbenchPlotSeries(label: "80 K", x: [1], y: [1],
            metadata: ["temperature": "80", "substrate": "STO"])
        let s2 = WorkbenchPlotSeries(label: "300 K", x: [2], y: [2],
            metadata: ["temperature": "300", "substrate": "STO"])
        let input = WorkbenchRenderPipeline.Input(
            payload: WorkbenchPlotPayload(
                workflowID: "test", workflowDisplayName: "test",
                title: "Test", axisMapping: .init(xField: "X", yField: "Y"),
                series: [s1, s2],
                reverseSeriesForLegend: true
            )
        )
        let output = try WorkbenchRenderPipeline.render(input)

        #expect(output.manifestPayload.legendDimension == nil,
                "legendDimension resolution is render-only")
        #expect(output.manifestPayload.series[0].label == "80 K",
                "legend-resolved labels must not overwrite manifestPayload")
        #expect(output.manifestPayload.series[1].label == "300 K")
        #expect(output.manifestPayload.series.first?.label == "80 K",
                "reversal is render-only; manifestPayload keeps original series order")
        #expect(output.manifestPayload.series.last?.label == "300 K")
    }
}
