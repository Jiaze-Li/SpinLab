import Foundation
import Testing
@testable import SpinLabApp

// MARK: - V558LegendResolverOwnershipTests
//
// v5.5.8 legend-ownership consolidation: LegendResolver (Sources/SpinLabApp/Workbench/
// Modules/PlotSystem/Legend/LegendResolver.swift) is now the single authority for final
// legend display text. These tests cover the phase-7 checklist from the architecture spec:
//   1. No workflow directly sets final legend output.
//   2. No ordinary XY workflow hardcodes legendDimension.
//   3. RT and 3ω both pass through the same Legend module output contract.
//   4. RT resolution failure no longer exposes an uncontrolled workflow label.
//   5. 3ω RAHE-vs-T resolves harmonic through metadata, not hardcoded legendDimension.
//   6. User rename remains highest priority but is applied inside the Legend module.
//   7. Same-tier-ambiguous and indeterminate outcomes produce shared-module fallback/
//      composite labels (v5.5.8.1: ambiguous now composes a multi-dimension label
//      instead of falling back to the semantic label — see V558CompositeLegendTests).
//   8. WorkbenchPlotLayout / WorkbenchChartRenderer only consume final labels.
//   9. Pack restore (re-running the same inputs) preserves user label overrides and
//      produces the same final legend as live rendering.
//   10. Existing resolver tier tests continue to pass (verified separately in
//       V534LegendDimensionResolverTests / V534PayloadPipelineTests — unchanged).

@Suite("v5.5.8 — LegendResolver ownership")
struct V558LegendResolverOwnershipTests {

    // MARK: - 1 & 8: static ownership — no bypass of the Legend module

    @Test("No source file outside the Legend module or render pipeline assigns WorkbenchPlotSeries.label")
    func noDirectLabelAssignmentOutsideOwners() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/SpinLabAppTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Sources/SpinLabApp")
        let allowedFiles: Set<String> = [
            "WorkbenchRenderPipeline.swift", // the only pipeline step allowed to write .label,
                                              // and it delegates the decision to LegendResolver
            "TabRenderManager.swift",        // applySeriesLabelOverrides: same override-apply
                                              // helper the pipeline uses, not a second policy
            "WorkbenchResultContracts.swift", // WorkbenchPlotSeries' own init assignment (`self.label
                                               // = label`) — declaring the type, not a workflow bypass
            "DualAxisPlotPayload.swift",      // DualAxisPlotSeries' own init assignment — a separate,
                                               // narrower struct/renderer (Temperature Dependence dual-
                                               // axis chart) that never goes through WorkbenchChartRenderer
                                               // or LegendResolver; out of this contract's scope.
        ]
        // Scoped to the areas that actually construct/mutate WorkbenchPlotSeries (plot payload
        // construction + the shared render pipeline). Unrelated `.label` properties elsewhere in
        // the app (AnalysisPack display names, DualAxisPlotSeries — a separate, narrower renderer
        // that never goes through WorkbenchChartRenderer/LegendResolver, NotImplementedWorkflowView's
        // own unrelated `label`, pack-rename UI writing AnalysisPack labels) are out of this
        // contract's scope entirely and must not be flagged.
        let scanRoots = [
            "Workbench/Modules/PlotSystem",
            "UseCases",
        ].map { root.appendingPathComponent($0) }

        var offenders: [String] = []
        for scanRoot in scanRoots {
            guard let enumerator = FileManager.default.enumerator(at: scanRoot, includingPropertiesForKeys: nil) else { continue }
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                let name = fileURL.lastPathComponent
                guard !allowedFiles.contains(name) else { continue }
                guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
                    if line.contains(".label = ") || line.contains(".label=") {
                        offenders.append("\(name): \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }
        #expect(offenders.isEmpty, "Unexpected direct label assignment(s) outside Legend/pipeline ownership: \(offenders)")
    }

    @Test("WorkbenchPlotLayout and WorkbenchChartRenderer do not reference the dimension resolver")
    func layoutAndRendererDoNotInferLegendSemantics() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SpinLabApp/Workbench/V3")
        for name in ["WorkbenchPlotLayout.swift", "WorkbenchChartRenderer.swift"] {
            let fileURL = root.appendingPathComponent(name)
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            #expect(!contents.contains("LegendDimensionResolver"),
                    "\(name) must not perform legend dimension inference — that is LegendResolver's job")
            #expect(!contents.contains("LegendResolver."),
                    "\(name) must only consume final labels, not call into the Legend module itself")
        }
    }

    @Test("ThreeOmegaPlotRenderer no longer hardcodes legendDimension")
    func threeOmegaDoesNotHardcodeLegendDimension() throws {
        let fileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(!contents.contains(#"legendDimension = "Harmonic""#),
                "3ω RAHE-vs-T must resolve \"Harmonic\" through metadata, not a hardcoded assignment")
        #expect(!contents.contains("legendDimension:"),
                "No 3ω payload constructor should pass an explicit legendDimension anymore")
    }

    // MARK: - 3: RT and 3ω share the same output contract

    @Test("RT-shaped and 3ω-shaped inputs both resolve through the identical LegendResolver.resolve contract")
    func rtAnd3omegaShareLegendModuleContract() {
        // RT: literal per-series labels ("SampleA (Rxx)"/"SampleA (Rxy)"), temperature metadata.
        let rtInput = LegendResolutionInput(series: [
            .init(identityKey: "rt-1", semanticLabel: "SampleA (Rxx)", metadata: ["temperature": "80"]),
            .init(identityKey: "rt-2", semanticLabel: "SampleA (Rxx)", metadata: ["temperature": "300"]),
        ])
        let rtOutput = LegendResolver.resolve(rtInput)
        #expect(rtOutput.status == .resolved(dimension: "Temperature (K)"))
        #expect(rtOutput.labels == ["80", "300"])

        // 3ω RAHE-vs-T: math-markup per-series labels, harmonic metadata.
        let threeOmegaInput = LegendResolutionInput(series: [
            .init(identityKey: "3w-1", semanticLabel: #"math:R_{AHE}^{1ω}"#, metadata: ["harmonic": "1ω"]),
            .init(identityKey: "3w-2", semanticLabel: #"math:R_{AHE}^{3ω}"#, metadata: ["harmonic": "3ω"]),
        ])
        let threeOmegaOutput = LegendResolver.resolve(threeOmegaInput)
        #expect(threeOmegaOutput.status == .resolved(dimension: "Harmonic"))
        #expect(threeOmegaOutput.labels == ["1ω", "3ω"])

        // Both went through the exact same function — no per-workflow resolver fork.
    }

    // MARK: - 4: RT indeterminate/ambiguous cases fall back to a module-selected label

    @Test("RT-shaped resolution failure falls back to the declared semantic label, chosen by the module")
    func rtResolutionFailureUsesModuleSelectedFallback() {
        // No metadata at all → automatic resolution cannot apply. The module must still
        // decide the output label — it must not be a bypass of workflow.label reaching the UI
        // unmediated; the fallback is a rule the module owns (see phase 6).
        let input = LegendResolutionInput(series: [
            .init(identityKey: "rt-1", semanticLabel: "SampleA (Rxx)", metadata: [:]),
            .init(identityKey: "rt-2", semanticLabel: "SampleB (Rxx)", metadata: [:]),
        ])
        let output = LegendResolver.resolve(input)
        #expect(output.status == .notApplicable)
        #expect(output.labels == ["SampleA (Rxx)", "SampleB (Rxx)"])
    }

    // MARK: - 5: 3ω RAHE-vs-T resolves harmonic end-to-end via ThreeOmegaPlotRenderer

    @Test("ThreeOmegaPlotRenderer RAHE-vs-T payload resolves Harmonic through metadata at render time")
    func threeOmegaRAHEResolvesHarmonicThroughMetadata() throws {
        func sweep(temperatureK: Double) -> ThreeOmegaFieldSweepResult {
            ThreeOmegaFieldSweepResult(
                temperatureK: temperatureK,
                device: "0deg",
                sampleMetadata: ["device": "0deg"],
                sampleID: "sample",
                sourceFilePath: "/tmp/sample-\(Int(temperatureK))K.csv",
                hField: [-1000, 0, 1000],
                r1omega: [-1, 0, 1],
                r3omega: [-2, 0, 2],
                iRms: 1e-4,
                rahe1omega: 0.4 + temperatureK * 0.001,
                rahe1omegaWA: 0.8,
                hc1omega: 0.0,
                hc3omega: 0.0,
                v3omegaWindow: 0.2e-4,
                v3omegaFit: 0.2e-4
            )
        }
        let sweeps = [sweep(temperatureK: 5.0), sweep(temperatureK: 10.0)]

        let renderer = ThreeOmegaPlotRenderer()
        let manifestPayload = try #require(renderer.makeRAHEPayload(
            sweeps: sweeps, device: "0deg", rahe1Method: .highField, rahe3Method: .highField
        ))
        // manifestPayload purity: legendDimension resolution is render-only.
        #expect(manifestPayload.legendDimension == nil)

        var renderPayload = manifestPayload
        WorkbenchRenderPipeline.applyLegendDimensionResolution(to: &renderPayload)
        #expect(renderPayload.legendDimension == "Harmonic")
        #expect(renderPayload.series.map(\.label) == ["1ω", "3ω"])
    }

    // MARK: - 6: user rename beats automatic resolution, applied inside the Legend module

    @Test("User override wins over automatic resolution")
    func userOverrideWinsOverAutomaticResolution() {
        let input = LegendResolutionInput(
            series: [
                .init(identityKey: "s1", semanticLabel: "80 K", metadata: ["temperature": "80"]),
                .init(identityKey: "s2", semanticLabel: "300 K", metadata: ["temperature": "300"]),
            ],
            userOverrides: ["s1": "Custom Name"]
        )
        let output = LegendResolver.resolve(input)
        #expect(output.status == .resolved(dimension: "Temperature (K)"))
        #expect(output.labels == ["Custom Name", "300"])
    }

    @Test("Pipeline routes user rename through LegendResolver.applyUserOverrides, not an ad hoc mutation")
    func pipelineRoutesRenameThroughLegendResolver() throws {
        let s1 = WorkbenchPlotSeries(label: "80 K", x: [1], y: [1], metadata: ["temperature": "80"])
        let s2 = WorkbenchPlotSeries(label: "300 K", x: [2], y: [2], metadata: ["temperature": "300"])
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
        #expect(output.displayPayload.series[1].label == "300") // auto-resolved, not overridden
        // manifestPayload purity: neither resolution nor override leak into the manifest.
        #expect(output.manifestPayload.series[0].label == "80 K")
        #expect(output.manifestPayload.series[1].label == "300 K")
    }

    // MARK: - 7: ambiguous / indeterminate → shared fallback, never a bare bypass

    @Test("Same-tier-ambiguous outcome composes a multi-dimension label, not a fallback to the semantic label")
    func ambiguousProducesCompositeLabel() {
        let input = LegendResolutionInput(series: [
            .init(identityKey: "s1", semanticLabel: "Series A", metadata: ["energy": "1.5", "pressure": "50"]),
            .init(identityKey: "s2", semanticLabel: "Series B", metadata: ["energy": "2.0", "pressure": "100"]),
        ])
        let output = LegendResolver.resolve(input)
        guard case .resolvedComposite(let dims) = output.status else {
            Issue.record("Expected .resolvedComposite, got \(output.status)")
            return
        }
        #expect(dims == ["Energy", "Pressure"])
        #expect(output.legendDimensionDisplayName == "Energy / Pressure")
        #expect(output.labels == ["1.5 / 50", "2.0 / 100"])
    }

    @Test("Indeterminate outcome falls back to declared semantic labels")
    func indeterminateFallsBackToSemanticLabels() {
        let input = LegendResolutionInput(series: [
            .init(identityKey: "s1", semanticLabel: "Experiment Data", metadata: ["device": "wafer"]),
            .init(identityKey: "s2", semanticLabel: "Fitting Results", metadata: ["device": "wafer"]),
        ])
        let output = LegendResolver.resolve(input)
        #expect(output.status == .indeterminate)
        #expect(output.labels == ["Experiment Data", "Fitting Results"])
        #expect(!output.warnings.isEmpty)
    }

    // MARK: - 9: restore-equivalence — same inputs always produce the same final legend

    @Test("Re-running the same LegendResolver input (simulating pack restore) reproduces the same final legend as the first run")
    func packRestoreProducesSameFinalLegendAsLiveRender() {
        let makeInput: () -> LegendResolutionInput = {
            LegendResolutionInput(
                series: [
                    .init(identityKey: "s1", semanticLabel: "80 K", metadata: ["temperature": "80"]),
                    .init(identityKey: "s2", semanticLabel: "300 K", metadata: ["temperature": "300"]),
                ],
                userOverrides: ["s2": "My Renamed Series"]
            )
        }
        let liveOutput = LegendResolver.resolve(makeInput())
        let restoredOutput = LegendResolver.resolve(makeInput())
        #expect(liveOutput.labels == restoredOutput.labels)
        #expect(liveOutput.labels == ["80", "My Renamed Series"])
        #expect(liveOutput.status == restoredOutput.status)
    }

    // MARK: - 6: single-series / declared math-markup labels still pass through the module (phase 6)

    @Test("Single series bypasses dimension resolution but still returns the module's own decision")
    func singleSeriesUsesDeclaredSemanticLabelViaModule() {
        let input = LegendResolutionInput(series: [
            .init(identityKey: "iv-1", semanticLabel: #"math:V_{x}^{ω}/I_{x}^{ω}"#, metadata: [:])
        ])
        let output = LegendResolver.resolve(input)
        #expect(output.status == .notApplicable)
        #expect(output.labels == [#"math:V_{x}^{ω}/I_{x}^{ω}"#])
    }
}
