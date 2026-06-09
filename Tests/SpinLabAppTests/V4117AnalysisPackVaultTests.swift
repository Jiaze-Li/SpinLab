import XCTest
@testable import SpinLabApp

@MainActor
final class V4117AnalysisPackVaultTests: XCTestCase {

    // MARK: - AnalysisVault CRUD

    func testVaultAddAndGet() {
        let vault = AnalysisVault()
        let pack = _makePack(label: "Test Pack")
        vault.add(pack)
        XCTAssertEqual(vault.get(id: pack.id)?.label, "Test Pack")
    }

    func testVaultRemove() {
        let vault = AnalysisVault()
        let pack = _makePack(label: "Remove Me")
        vault.add(pack)
        vault.remove(id: pack.id)
        XCTAssertNil(vault.get(id: pack.id))
    }

    func testVaultUpdate() {
        let vault = AnalysisVault()
        var pack = _makePack(label: "Original")
        vault.add(pack)
        pack.label = "Updated"
        vault.update(pack)
        XCTAssertEqual(vault.get(id: pack.id)?.label, "Updated")
    }

    func testVaultUpdateNonexistent() {
        let vault = AnalysisVault()
        let pack = _makePack(label: "Ghost")
        vault.update(pack)  // should not crash
        XCTAssertNil(vault.get(id: pack.id))
    }

    // MARK: - Workflow filtering + sort

    func testPacksForWorkflowFilteredAndSorted() {
        let vault = AnalysisVault()
        vault.add(_makePack(label: "Zeta", workflowID: "3w"))
        vault.add(_makePack(label: "Alpha", workflowID: "3w"))
        vault.add(_makePack(label: "Beta", workflowID: "ahe"))  // different workflow

        let result = vault.packs(forWorkflow: "3w")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.label), ["Alpha", "Zeta"])
    }

    // MARK: - AnalysisPack encode/decode round-trip

    func testPackConfigResultRoundTrip() throws {
        let config = ThreeOmegaPackConfig(
            device: "0deg",
            geometry: ThreeOmegaGeometry(lxx: 26, lxy: 21, dNm: 30),
            fitRanges: [ThreeOmegaFitRange(tLo: 100, tHi: 300)],
            v3Method: ThreeOmegaV3Method.highField.rawValue,
            rahe1Method: ThreeOmegaV3Method.highField.rawValue,
            rahe3Method: ThreeOmegaV3Method.window.rawValue,
            rtFilePath: "/path/to/rt.lvm",
            sampleBatchAndSubstrate: "PN69-Pt/Co",
            activeTab: "rahe1omegaVsT",
            titleTemplate: "#tab #device #sample",
            stackOffsetMultiplier: 1.2,
            minGapFraction: 0.15,
            showPlotGrid: true,
            plotLegendAnchor: "",
            tabStates: [:],
            cachedSearchResults: [],
            selectedSearchResultIDs: [],
            selectedRTHit: nil,
            rtQuery: "rt PN69",
            searchQueryText: "3w PN69"
        )

        let result = ThreeOmegaPackResult(
            ingestionResult: ThreeOmegaIngestionResult(
                fieldSweeps: [],
                rtResult: nil,
                device: "0deg"
            ),
            scalingResult: nil
        )

        let pack = try AnalysisPack(
            label: "Test",
            workflowID: "3w",
            filePaths: ["/a.lvm"],
            sampleKeys: ["PN69"],
            config: config,
            result: result
        )

        let decodedConfig = try pack.decodeConfig(ThreeOmegaPackConfig.self)
        XCTAssertEqual(decodedConfig.device, "0deg")
        XCTAssertEqual(decodedConfig.geometry.lxx, 26)
        XCTAssertEqual(decodedConfig.v3Method, "High-field extrapolation")
        XCTAssertEqual(decodedConfig.activeTab, "rahe1omegaVsT")
        XCTAssertEqual(decodedConfig.rtQuery, "rt PN69")

        let decodedResult = try pack.decodeResult(ThreeOmegaPackResult.self)
        XCTAssertEqual(decodedResult.ingestionResult.device, "0deg")
        XCTAssertNil(decodedResult.scalingResult)
    }

    // MARK: - Backward-compatibility: older packs without deviceMode

    func testIngestionResultDecodesWithoutDeviceMode() throws {
        // Minimal JSON payload as produced by older packs (pre-deviceMode field).
        let json = """
        {
            "fieldSweeps": [],
            "device": "legacy_dev"
        }
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(ThreeOmegaIngestionResult.self, from: json)
        XCTAssertEqual(result.device, "legacy_dev")
        XCTAssertEqual(result.deviceMode, "single")
        XCTAssertEqual(result.devices, [])
        XCTAssertEqual(result.iRmsValues, [:])
        XCTAssertEqual(result.warnings, [])
    }

    func testIngestionResultRoundTripPreservesDeviceMode() throws {
        let original = ThreeOmegaIngestionResult(
            fieldSweeps: [],
            rtResult: nil,
            device: "0deg",
            deviceMode: "angleSweep",
            devices: ["0deg", "30deg"],
            iRmsValues: [100.0: 1e-3],
            warnings: ["w1"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ThreeOmegaIngestionResult.self, from: data)
        XCTAssertEqual(decoded.deviceMode, "angleSweep")
        XCTAssertEqual(decoded.devices, ["0deg", "30deg"])
        XCTAssertEqual(decoded.iRmsValues, [100.0: 1e-3])
        XCTAssertEqual(decoded.warnings, ["w1"])
    }

    // MARK: - Overlay snapshot independence

    func testOverlaySnapshotSurvivesVaultDeletion() {
        let vault = AnalysisVault()
        let store = ThreeOmegaWorkspaceStore()
        store.vault = vault

        let pack = _makePack(label: "Overlay Source")
        vault.add(pack)

        // Simulate addOverlay manually (we don't have real ingestion data)
        let snapshot = OverlaySnapshot(
            label: pack.label,
            sweeps: [],
            sourceFiles: ["/a.lvm"],
            sampleKeys: pack.sampleKeys
        )
        store.overlaySnapshots[pack.id] = snapshot
        store.overlayPackIDs.append(pack.id)

        // Delete pack from vault
        vault.remove(id: pack.id)

        // Overlay data still in snapshot
        XCTAssertNotNil(store.overlaySnapshots[pack.id])
        XCTAssertEqual(store.overlaySnapshots[pack.id]?.label, "Overlay Source")
        XCTAssertTrue(store.overlayPackIDs.contains(pack.id))
    }

    // MARK: - Helpers

    private func _makePack(label: String, workflowID: String = "3w") -> AnalysisPack {
        AnalysisPack(
            label: label,
            workflowID: workflowID,
            filePaths: [],
            sampleKeys: [],
            config: Data(),
            result: Data()
        )
    }
}
