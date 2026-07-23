import Foundation
import Testing
@testable import SpinLabApp

/// v5.5.7 — 3ω run trace axisMapping must reflect the active tab's actually-rendered
/// payload (field sweep / Scaling / RAHE-vs-Device all plot different quantities), not
/// the hardcoded field-sweep-shaped fallback "H (Oe)"/"R (Ω)" that every tab previously
/// reported regardless of what it plotted (docs/architecture/workbench audit finding D).
///
/// Follows the same pattern as AHEWorkspaceStore.buildRunTrace(): prefer
/// `activeChartManifestPayload?.axisMapping`, fall back to the legacy literal labels only
/// when no manifest payload is available yet.
@Suite("v5.5.7 - 3ω run trace axis label derivation")
struct V557ThreeOmegaRunTraceAxisLabelTests {

    // MARK: - Fixtures

    private func makeSweeps() -> [ThreeOmegaFieldSweepResult] {
        [
            ThreeOmegaFieldSweepResult(
                temperatureK: 5.0,
                device: "0deg",
                sampleMetadata: ["device": "0deg"],
                sampleID: "sample",
                sourceFilePath: "/tmp/sample-5K.csv",
                hField: [-1000, 0, 1000],
                r1omega: [-1, 0, 1],
                r3omega: [-2, 0, 2],
                iRms: 1e-4,
                rahe1omega: 0.4,
                rahe1omegaWA: 0.8,
                hc1omega: 0.0,
                hc3omega: 0.0,
                v3omegaWindow: 0.2e-4,
                v3omegaFit: 0.2e-4
            ),
            ThreeOmegaFieldSweepResult(
                temperatureK: 10.0,
                device: "0deg",
                sampleMetadata: ["device": "0deg"],
                sampleID: "sample",
                sourceFilePath: "/tmp/sample-10K.csv",
                hField: [-1000, 0, 1000],
                r1omega: [-1, 0, 1],
                r3omega: [-2, 0, 2],
                iRms: 1e-4,
                rahe1omega: 0.8,
                rahe1omegaWA: 0.4,
                hc1omega: 0.0,
                hc3omega: 0.0,
                v3omegaWindow: 0.6e-4,
                v3omegaFit: 0.6e-4
            )
        ]
    }

    @MainActor
    private func makeStore(activeTab: ThreeOmegaWorkbenchTab) -> ThreeOmegaWorkspaceStore {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: makeSweeps(),
            rtResult: nil,
            device: "0deg",
            iRmsValues: [5.0: 1e-4, 10.0: 1e-4]
        )
        store.cachedInputFiles = ["/tmp/sample-5K.csv", "/tmp/sample-10K.csv"]
        store.tabs.activeTab = activeTab
        return store
    }

    private let legacyFallbackXField = "H (Oe)"
    private let legacyFallbackYField = "R (Ω)"

    // MARK: - Field-based 3ω plot

    @MainActor
    @Test("Field sweep (1ω) tab run trace reflects the rendered field-sweep payload's axis labels")
    func fieldSweep1omegaUsesPayloadAxisMapping() throws {
        let store = makeStore(activeTab: .fieldSweep1omega)
        store._refreshManifestPayloads()

        let payload = try #require(store.activeChartManifestPayload)
        let trace = try #require(store.buildRunTrace())

        #expect(trace.axisMapping == payload.axisMapping)
        #expect(trace.axisMapping.yField == WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .resistance1omega))
        #expect(trace.axisMapping.yField != legacyFallbackYField)
    }

    @MainActor
    @Test("Field sweep (3ω) tab run trace reflects its own payload, distinct from the 1ω tab")
    func fieldSweep3omegaUsesPayloadAxisMapping() throws {
        let store = makeStore(activeTab: .fieldSweep3omega)
        store._refreshManifestPayloads()

        let payload = try #require(store.activeChartManifestPayload)
        let trace = try #require(store.buildRunTrace())

        #expect(trace.axisMapping == payload.axisMapping)
        #expect(trace.axisMapping.yField == WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .resistance3omega))
        #expect(trace.axisMapping.yField != legacyFallbackYField)
        #expect(trace.axisMapping.yField != WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .resistance1omega))
    }

    // MARK: - Scaling

    @MainActor
    @Test("Scaling tab run trace reflects the scaling-law axis labels, not the field-sweep fallback")
    func scalingTabUsesPayloadAxisMapping() throws {
        let store = makeStore(activeTab: .scaling)
        store._refreshManifestPayloads()

        let payload = try #require(store.activeChartManifestPayload)
        let trace = try #require(store.buildRunTrace())

        #expect(trace.axisMapping == payload.axisMapping)
        #expect(trace.axisMapping.xField == ThreeOmegaPlotRenderer.scalingXAxisLabel)
        #expect(trace.axisMapping.yField == ThreeOmegaPlotRenderer.scalingYAxisLabel)
        #expect(trace.axisMapping.xField != legacyFallbackXField)
        #expect(trace.axisMapping.yField != legacyFallbackYField)
    }

    // MARK: - RAHE vs Device

    @MainActor
    @Test("RAHE(1ω)-vs-Device tab run trace reflects device-angle/RAHE axis labels, not H (Oe)/R (Ω)")
    func rahe1omegaVsDeviceUsesPayloadAxisMapping() throws {
        let store = makeStore(activeTab: .rahe1omegaVsDevice)
        store._refreshManifestPayloads()

        let payload = try #require(store.activeChartManifestPayload)
        let trace = try #require(store.buildRunTrace())

        #expect(trace.axisMapping == payload.axisMapping)
        #expect(trace.axisMapping.xField == WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .deviceAngle))
        #expect(trace.axisMapping.yField == WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .rahe1omega))
        #expect(trace.axisMapping.xField != legacyFallbackXField)
        #expect(trace.axisMapping.yField != legacyFallbackYField)
    }

    @MainActor
    @Test("RAHE(3ω)-vs-Device tab run trace reflects its own axis labels, distinct from the 1ω RAHE tab")
    func rahe3omegaVsDeviceUsesPayloadAxisMapping() throws {
        let store = makeStore(activeTab: .rahe3omegaVsDevice)
        store._refreshManifestPayloads()

        let payload = try #require(store.activeChartManifestPayload)
        let trace = try #require(store.buildRunTrace())

        #expect(trace.axisMapping == payload.axisMapping)
        #expect(trace.axisMapping.yField == WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .rahe3omega))
        #expect(trace.axisMapping.yField != legacyFallbackYField)
        #expect(trace.axisMapping.yField != WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .rahe1omega))
    }

    // MARK: - Absence of a current payload → preserved fallback

    @MainActor
    @Test("No manifest payload available yet falls back to the legacy H (Oe)/R (Ω) labels")
    func noManifestPayloadFallsBackToLegacyLabels() throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: makeSweeps(),
            rtResult: nil,
            device: "0deg",
            iRmsValues: [5.0: 1e-4, 10.0: 1e-4]
        )
        // Deliberately do not call _refreshManifestPayloads(): no tab output has been
        // produced yet, so activeChartManifestPayload is nil and buildRunTrace() must fall
        // back rather than crash or emit an empty axisMapping.
        #expect(store.activeChartManifestPayload == nil)

        let trace = try #require(store.buildRunTrace())
        #expect(trace.axisMapping.xField == legacyFallbackXField)
        #expect(trace.axisMapping.yField == legacyFallbackYField)
    }

    @MainActor
    @Test("buildRunTrace returns nil when there is no ingestion result at all")
    func noIngestionResultReturnsNilTrace() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        #expect(store.buildRunTrace() == nil)
    }
}
