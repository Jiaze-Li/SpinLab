import Foundation
import Testing
@testable import SpinLabApp

/// Stage 2A-1: manifestPayload must be the raw/scientific payload.
///
/// UI display overrides (titleOverride, xLabelOverride, yLabelOverride,
/// seriesLabelOverrides) live in TabRenderState and must NOT be baked
/// into manifestPayload. TabRenderState owns the display layer;
/// the manifest is the source-of-truth for chart identity and pack persistence.
@Suite("Stage 2A-1 — manifest payload purity")
struct Stage2A1ManifestPayloadPurityTests {

    // MARK: - Helpers

    @MainActor
    private func makeStore() -> ThreeOmegaWorkspaceStore {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.ingestionResult = ThreeOmegaIngestionResult(device: "0deg", deviceMode: "single")
        store.cachedInputFiles = ["/tmp/a.dat"]
        return store
    }

    // MARK: - Axis label purity

    @MainActor
    @Test("xLabelOverride does not pollute manifestPayload axisMapping.xField")
    func xLabelOverrideDoesNotPolluteManiestAxisX() {
        let store = makeStore()
        store.tabs.activeTab = .fieldSweep1omega

        // Capture the scientific x label before setting any override
        store._refreshManifestPayloads()
        let scientificX = store.tabs.output(for: .fieldSweep1omega).manifestPayload?.axisMapping.xField
        guard let scientificX else {
            Issue.record("Expected manifestPayload to be non-nil after _refreshManifestPayloads")
            return
        }

        // Set a display override for the active tab
        store.tabs.tabStates[.fieldSweep1omega, default: TabRenderState()].xLabelOverride = "My Custom X"
        store._refreshManifestPayloads()

        let manifestX = store.tabs.output(for: .fieldSweep1omega).manifestPayload?.axisMapping.xField
        #expect(manifestX == scientificX, "manifestPayload.axisMapping.xField must remain the scientific label; got \(manifestX ?? "nil")")
        #expect(manifestX != "My Custom X", "xLabelOverride must not be baked into manifestPayload")
    }

    @MainActor
    @Test("yLabelOverride does not pollute manifestPayload axisMapping.yField")
    func yLabelOverrideDoesNotPolluteManiestAxisY() {
        let store = makeStore()
        store.tabs.activeTab = .fieldSweep1omega

        store._refreshManifestPayloads()
        let scientificY = store.tabs.output(for: .fieldSweep1omega).manifestPayload?.axisMapping.yField
        guard let scientificY else {
            Issue.record("Expected manifestPayload to be non-nil after _refreshManifestPayloads")
            return
        }

        store.tabs.tabStates[.fieldSweep1omega, default: TabRenderState()].yLabelOverride = "My Custom Y"
        store._refreshManifestPayloads()

        let manifestY = store.tabs.output(for: .fieldSweep1omega).manifestPayload?.axisMapping.yField
        #expect(manifestY == scientificY, "manifestPayload.axisMapping.yField must remain the scientific label; got \(manifestY ?? "nil")")
        #expect(manifestY != "My Custom Y", "yLabelOverride must not be baked into manifestPayload")
    }

    // MARK: - Title purity

    @MainActor
    @Test("titleOverride does not pollute manifestPayload title")
    func titleOverrideDoesNotPolluteManiestTitle() {
        let store = makeStore()
        // .rahe's manifest builder requires non-empty field sweeps to produce a payload.
        let sweep = ThreeOmegaFieldSweepResult(
            temperatureK: 300,
            device: "0deg",
            sampleID: "sample-abc",
            sourceFilePath: "/tmp/a.dat",
            hField: [0.0, 1.0],
            r1omega: [1.0, 2.0],
            r3omega: [0.1, 0.2],
            iRms: 1e-3,
            v3omegaWindow: 0.001
        )
        store.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: [sweep],
            device: "0deg",
            deviceMode: "single"
        )
        store.cachedInputFiles = ["/tmp/a.dat"]
        store.tabs.activeTab = .rahe

        store._refreshManifestPayloads()
        let scientificTitle = store.tabs.output(for: .rahe).manifestPayload?.title
        guard let scientificTitle else {
            Issue.record("Expected manifestPayload to be non-nil after _refreshManifestPayloads")
            return
        }

        store.tabs.tabStates[.rahe, default: TabRenderState()].titleOverride = "My Custom Title"
        store._refreshManifestPayloads()

        let manifestTitle = store.tabs.output(for: .rahe).manifestPayload?.title
        #expect(manifestTitle == scientificTitle, "manifestPayload.title must remain the analysis-generated title; got \(manifestTitle ?? "nil")")
        #expect(manifestTitle != "My Custom Title", "titleOverride must not be baked into manifestPayload")
    }

    // MARK: - Series label purity

    @MainActor
    @Test("seriesLabelOverrides do not pollute manifestPayload series labels")
    func seriesLabelOverridesDoNotPolluteManiestSeries() {
        let store = makeStore()
        // Use a sweep with a known sampleID so series identity is deterministic
        let sweep = ThreeOmegaFieldSweepResult(
            temperatureK: 300,
            device: "0deg",
            sampleID: "sample-abc",
            sourceFilePath: "/tmp/a.dat",
            hField: [0.0, 1.0],
            r1omega: [1.0, 2.0],
            r3omega: [0.1, 0.2],
            iRms: 1e-3,
            v3omegaWindow: 0.001
        )
        store.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: [sweep],
            device: "0deg",
            deviceMode: "single"
        )
        store.cachedInputFiles = ["/tmp/a.dat"]
        store.tabs.activeTab = .fieldSweep1omega

        store._refreshManifestPayloads()
        let originalLabel = store.tabs.output(for: .fieldSweep1omega).manifestPayload?.series.first?.label
        guard let originalLabel else {
            Issue.record("Expected at least one series in manifestPayload after _refreshManifestPayloads")
            return
        }

        // Apply a series label override keyed by sampleID
        store.tabs.tabStates[.fieldSweep1omega, default: TabRenderState()].seriesLabelOverrides = ["sample-abc": "Renamed Series"]
        store._refreshManifestPayloads()

        let manifestLabel = store.tabs.output(for: .fieldSweep1omega).manifestPayload?.series.first?.label
        #expect(manifestLabel == originalLabel, "manifestPayload series label must remain the original scientific identity; got \(manifestLabel ?? "nil")")
        #expect(manifestLabel != "Renamed Series", "seriesLabelOverrides must not be baked into manifestPayload")
    }
}
