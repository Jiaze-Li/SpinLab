import Foundation
import XCTest
@testable import SpinLabApp

// MARK: - Stage 4B: IV manifest title contract
//
// Verifies the contract for WorkbenchRenderPipeline.Output.manifestPayload.title:
// it must stay on the scientific/template title and ignore user titleOverride.
//
// Background (Stage 4A audit):
//   - WorkbenchRenderPipeline.render restores axisMapping (line 187) but does NOT restore
//     payload.title after applying titleOverride (line 90).
//   - IV uses applyPipelineOutput, which stores pipelineOutput.manifestPayload directly.
//   - ThreeOmega avoids this because it uses a dedicated _refreshManifestPayloads() path.
//
// These tests now assert the contract: manifestPayload stays display-override-clean.

final class Stage4BIVManifestTitleCharacterizationTests: XCTestCase {

    // MARK: - 1. titleOverride does not leak into manifestPayload.title (contract)

    @MainActor
    func testManifestTitleReceivesTitleOverride() throws {
        let (store, payload) = try makeStoreAndPayload()
        let scientificTitle = payload.title

        store.tabs.activeTab = .voltage
        store.tabs.updateTitleOverride("User IV Title")

        let input  = store.tabs.buildPipelineInput(payload: payload, globalPlotDefaults: [:], for: .voltage)
        let output = try WorkbenchRenderPipeline.render(input)
        store.tabs.applyPipelineOutput(output, displayPayload: payload, for: .voltage)

        let manifestTitle = store.tabs.output(for: .voltage).manifestPayload?.title
        let displayTitle  = store.tabs.output(for: .voltage).displayPayload?.title

        // displayPayload is captured pre-pipeline, so its title is always the scientific title.
        XCTAssertEqual(displayTitle, scientificTitle,
            "displayPayload.title must be the scientific/template title (pre-pipeline capture)")

        XCTAssertEqual(manifestTitle, scientificTitle,
            "manifestPayload.title must remain the scientific/template title and not inherit titleOverride")
        XCTAssertNotEqual(manifestTitle, "User IV Title",
            "titleOverride must not be baked into manifestPayload.title")
    }

    // MARK: - 2. Without titleOverride, manifestPayload.title equals the scientific title (contract)

    @MainActor
    func testManifestTitleWithoutOverrideEqualsScientificTitle() throws {
        let (store, payload) = try makeStoreAndPayload()
        let scientificTitle = payload.title

        store.tabs.activeTab = .voltage
        // No titleOverride — tab state has empty override.

        let input  = store.tabs.buildPipelineInput(payload: payload, globalPlotDefaults: [:], for: .voltage)
        let output = try WorkbenchRenderPipeline.render(input)
        store.tabs.applyPipelineOutput(output, displayPayload: payload, for: .voltage)

        let manifestTitle = store.tabs.output(for: .voltage).manifestPayload?.title
        XCTAssertEqual(manifestTitle, scientificTitle,
            "Without titleOverride, manifestPayload.title must equal the scientific/template title")
    }

    // MARK: - 3. Verify observed scientific title value (contract anchor)

    @MainActor
    func testObservedScientificTitleFormat() throws {
        let (_, payload) = try makeStoreAndPayload()
        // Anchor: confirm what the scientific title looks like with the test template.
        // The template "IV #tab #device" resolves to "IV 1st / I D1" for the voltage tab.
        XCTAssertTrue(payload.title.contains("IV"),
            "Scientific title from template 'IV #tab #device' must contain 'IV'; got: \(payload.title)")
        XCTAssertTrue(payload.title.contains("D1"),
            "Scientific title must contain the device token; got: \(payload.title)")
    }

    // MARK: - Helpers

    @MainActor
    private func makeStoreAndPayload() throws -> (IVWorkspaceStore, WorkbenchPlotPayload) {
        let sweep = IVSweep(
            stem: "test.lvm",
            temperatureK: 300,
            fieldT: 0,
            current: [0.001, 0.002, 0.003],
            ch1X:    [0.10,  0.20,  0.30],
            ch1Y:    [0.01,  0.02,  0.03],
            ch2X:    [0.05,  0.10,  0.15],
            ch2Y:    [0.005, 0.010, 0.015],
            firstR:  nil, firstTheta: nil,
            secondR: nil, secondTheta: nil,
            firstRH: nil, frequencyAfter: nil,
            measurementFilePath: "/tmp/test.lvm",
            sampleMetadata: [:]
        )
        var renderer = IVPlotRenderer()
        renderer.workflowID = "iv-test"
        renderer.titleTemplate = "IV #tab #device"

        let payload = try XCTUnwrap(
            renderer.makeFirstHarmonicPayload(sweeps: [sweep], device: "D1"),
            "renderer must produce a payload for non-empty sweeps"
        )
        let store = IVWorkspaceStore(workflowID: "iv-test")
        return (store, payload)
    }
}
