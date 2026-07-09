import Foundation
import XCTest
@testable import SpinLabApp

// MARK: - Stage 4B: AHE manifest title contract
//
// Verifies the contract for WorkbenchRenderPipeline.Output.manifestPayload.title:
// it must stay on the scientific/template title and ignore user titleOverride.
//
// Background (Stage 4A audit):
//   - The pipeline applies titleOverride to payload.title (line 90) but restores only
//     axisMapping (line 187), not payload.title.
//   - AHE uses applyPipelineOutput which stores pipelineOutput.manifestPayload directly.
//   - Note: the real AHE store (_rerenderActiveTab) pre-bakes the override into the payload
//     title before calling buildPipelineInput — meaning the override is applied twice.
//     These tests isolate the pipeline's behavior independently of that pre-baking.
//
// These tests now assert the contract: manifestPayload stays display-override-clean.

final class Stage4BAHEManifestTitleCharacterizationTests: XCTestCase {

    // MARK: - 1. titleOverride does not leak into manifestPayload.title (contract)

    @MainActor
    func testManifestTitleReceivesTitleOverride() throws {
        let (store, payload) = makeStoreAndPayload(title: "AHE Scientific Title")
        let scientificTitle = payload.title

        store.tabs.activeTab = .ahe
        store.tabs.updateTitleOverride("User AHE Title")

        let input  = store.tabs.buildPipelineInput(payload: payload, globalPlotDefaults: [:], for: .ahe)
        let output = try WorkbenchRenderPipeline.render(input)
        store.tabs.applyPipelineOutput(output, displayPayload: payload, for: .ahe)

        let manifestTitle = store.tabs.output(for: .ahe).manifestPayload?.title
        let displayTitle  = store.tabs.output(for: .ahe).displayPayload?.title

        // displayPayload is captured pre-pipeline: its title must be the scientific title.
        XCTAssertEqual(displayTitle, scientificTitle,
            "displayPayload.title must be the scientific title (pre-pipeline capture)")

        XCTAssertEqual(manifestTitle, scientificTitle,
            "manifestPayload.title must remain the scientific/template title and not inherit titleOverride")
        XCTAssertNotEqual(manifestTitle, "User AHE Title",
            "titleOverride must not be baked into manifestPayload.title")
    }

    // MARK: - 2. Without titleOverride, manifestPayload.title equals the scientific title (contract)

    @MainActor
    func testManifestTitleWithoutOverrideEqualsScientificTitle() throws {
        let (store, payload) = makeStoreAndPayload(title: "AHE Scientific Title")

        store.tabs.activeTab = .ahe
        // No titleOverride — tab state has empty override.

        let input  = store.tabs.buildPipelineInput(payload: payload, globalPlotDefaults: [:], for: .ahe)
        let output = try WorkbenchRenderPipeline.render(input)
        store.tabs.applyPipelineOutput(output, displayPayload: payload, for: .ahe)

        let manifestTitle = store.tabs.output(for: .ahe).manifestPayload?.title
        XCTAssertEqual(manifestTitle, "AHE Scientific Title",
            "Without titleOverride, manifestPayload.title must equal the scientific/template title")
    }

    // MARK: - 3. Double-application path still renders the user-visible title override
    //
    // Documents that the real AHE store can still pre-bake the override into the payload title
    // before buildPipelineInput, so the rendered/exported title remains the user override.

    @MainActor
    func testManifestTitleMatchesRealStorePatternWhenOverridePreBaked() throws {
        // Simulate _rerenderActiveTab: resolved title is already the override.
        let (store, payload) = makeStoreAndPayload(title: "User AHE Title")
        store.tabs.activeTab = .ahe
        store.tabs.updateTitleOverride("User AHE Title")

        let input  = store.tabs.buildPipelineInput(payload: payload, globalPlotDefaults: [:], for: .ahe)
        let output = try WorkbenchRenderPipeline.render(input)
        store.tabs.applyPipelineOutput(output, displayPayload: payload, for: .ahe)

        let manifestTitle = store.tabs.output(for: .ahe).manifestPayload?.title
        XCTAssertEqual(manifestTitle, "User AHE Title",
            "When override is pre-baked into payload and also passed as titleOverride, " +
            "the rendered/exported title remains the user override")
    }

    // MARK: - Helpers

    @MainActor
    private func makeStoreAndPayload(title: String) -> (AHEWorkspaceStore, WorkbenchPlotPayload) {
        let series = WorkbenchPlotSeries(
            label: "300 K",
            x: [-1.0, 0.0, 1.0],
            y: [0.5, 0.0, -0.5],
            sourceRef: "/tmp/ahe.csv",
            sampleID: "sample-ahe"
        )
        let ingestion = AHEIngestionResult(
            defaultAxisMapping: WorkbenchAxisMapping(
                xField: AHEAxisDetector.displayXField,
                yField: AHEAxisDetector.displayYField
            ),
            series: [series],
            sourceFiles: ["/tmp/ahe.csv"],
            warnings: []
        )
        let payload = BuildAHEPlotPayloadUseCase().execute(ingestion: ingestion, title: title)
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        return (store, payload)
    }
}
