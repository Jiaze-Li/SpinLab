import Foundation
import Testing
@testable import SpinLabApp

// MARK: - V6B PackRestoreFailureReporting — shared reporting contract
//
// Phase 6B: standardizes the restore-time failure/warning reporting channel across all
// six workflow stores. `PackRestoreFailureReporting` (a single `packRestoreErrorMessage:
// String?`) already existed for ThreeOmega only; this suite pins:
//   1. all six stores conform
//   2/3. message lifecycle (cleared on new restore, no stale leakage on success)
//   4. ThreeOmega legacy restore failure is unaffected (see V760PackRestoreProtectionTests
//      for the primary regression pin — not duplicated here)
//   5/6. RSM's async reparse now surfaces failure/success through the same channel
//   7. generic decode failures (pre-restoreFromPack) are not double-reported
//   8. the shared UI path has no workflow-specific branching

@Suite("V6B six-workflow PackRestoreFailureReporting conformance")
struct V6BConformanceTests {

    @MainActor
    @Test("all six workflow stores conform to PackRestoreFailureReporting")
    func allSixStoresConform() {
        #expect(AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue) is PackRestoreFailureReporting)
        #expect(IVWorkspaceStore(workflowID: WorkflowKey.iv.rawValue) is PackRestoreFailureReporting)
        #expect(RTWorkspaceStore(workflowID: WorkflowKey.rt.rawValue) is PackRestoreFailureReporting)
        #expect(XYRotationWorkspaceStore(workflowID: WorkflowKey.xyRotation.rawValue) is PackRestoreFailureReporting)
        #expect(ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue) is PackRestoreFailureReporting)
        #expect(RSMWorkspaceStore(workflowID: WorkflowKey.rsm.rawValue) is PackRestoreFailureReporting)
    }
}

@Suite("V6B message lifecycle — synchronous stores (AHE/IV/RT/XY)")
struct V6BSynchronousLifecycleTests {

    @MainActor
    @Test("AHE: successful restore leaves no stale packRestoreErrorMessage")
    func aheSuccessfulRestoreLeavesNoStaleMessage() throws {
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        let vault = AnalysisVault()
        store.vault = vault
        store.packRestoreErrorMessage = "stale from a previous attempt"

        let config = AHEPackConfig(
            titleTemplate: "#tab",
            showPlotGrid: false,
            legendAnchor: "bottom-right",
            seriesRenderMode: .scatter,
            chartStyleOverrides: [:],
            tabStates: [:],
            cachedSearchResults: [],
            selectedSearchResultIDs: [],
            searchQueryText: ""
        )
        let result = AHEPackResult(ingestionResult: nil)
        let pack = try AnalysisPack(
            label: "AHE Restore Fixture",
            workflowID: "ahe",
            filePaths: [],
            sampleKeys: [],
            config: config,
            result: result
        )
        vault.add(pack)

        store.loadPack(id: pack.id) { _, _ in }

        #expect(store.packRestoreErrorMessage == nil,
                "a fresh restore must clear any message left by a previous attempt")
        #expect(store.analysisMessage == "Loaded: \(pack.label)")
        #expect(store.activePackID == pack.id)
    }

    @MainActor
    @Test("IV: successful restore leaves no stale packRestoreErrorMessage")
    func ivSuccessfulRestoreLeavesNoStaleMessage() throws {
        let store = IVWorkspaceStore(workflowID: WorkflowKey.iv.rawValue)
        let vault = AnalysisVault()
        store.vault = vault
        store.packRestoreErrorMessage = "stale from a previous attempt"

        let config = IVPackConfig(titleTemplate: "#tab", showPlotGrid: true, legendAnchor: "top-left")
        let result = IVPackResult(ingestionResult: IVIngestionResult())
        let pack = try AnalysisPack(
            label: "IV Restore Fixture",
            workflowID: "iv",
            filePaths: [],
            sampleKeys: [],
            config: config,
            result: result
        )
        vault.add(pack)

        store.loadPack(id: pack.id) { _, _ in }

        #expect(store.packRestoreErrorMessage == nil)
        #expect(store.analysisMessage == "Loaded: \(pack.label)")
        #expect(store.activePackID == pack.id)
    }

    @MainActor
    @Test("RT: successful restore leaves no stale packRestoreErrorMessage")
    func rtSuccessfulRestoreLeavesNoStaleMessage() throws {
        let store = RTWorkspaceStore(workflowID: WorkflowKey.rt.rawValue)
        let vault = AnalysisVault()
        store.vault = vault
        store.packRestoreErrorMessage = "stale from a previous attempt"

        let config = RTPackConfig(legendAnchor: "top-left")
        let result = RTPackResult()
        let pack = try AnalysisPack(
            label: "RT Restore Fixture",
            workflowID: "rt",
            filePaths: [],
            sampleKeys: [],
            config: config,
            result: result
        )
        vault.add(pack)

        store.loadPack(id: pack.id) { _, _ in }

        #expect(store.packRestoreErrorMessage == nil)
        #expect(store.analysisMessage == "Loaded: \(pack.label)")
        #expect(store.activePackID == pack.id)
    }

    @MainActor
    @Test("XY Rotation: successful restore leaves no stale packRestoreErrorMessage")
    func xyRotationSuccessfulRestoreLeavesNoStaleMessage() throws {
        let store = XYRotationWorkspaceStore(workflowID: WorkflowKey.xyRotation.rawValue)
        let vault = AnalysisVault()
        store.vault = vault
        store.packRestoreErrorMessage = "stale from a previous attempt"

        let config = XYRotationPackConfig(
            phiOffsetOverrides: [:],
            centerBaseline: false,
            linearDetrend: false,
            activeTab: XYRotationWorkbenchTab.rxxVsPhi.rawValue,
            titleTemplate: "#tab",
            stackOffsetMultiplier: 0.0,
            minGapFraction: 0.15,
            showPlotGrid: true,
            showAuxiliaryLine180: true
        )
        let result = XYRotationPackResult(ingestionResult: XYRotationIngestionResult())
        let pack = try AnalysisPack(
            label: "XY Restore Fixture",
            workflowID: "xy",
            filePaths: [],
            sampleKeys: [],
            config: config,
            result: result
        )
        vault.add(pack)

        store.loadPack(id: pack.id) { _, _ in }

        #expect(store.packRestoreErrorMessage == nil)
        #expect(store.analysisMessage == "Loaded: \(pack.label)")
        #expect(store.activePackID == pack.id)
    }
}

@Suite("V6B generic decode failure — not double-reported through PackRestoreFailureReporting")
struct V6BGenericDecodeFailureTests {

    @MainActor
    @Test("RT: a pack that fails config decode is handled by loadPack's generic path, restoreFromPack never runs")
    func rtGenericDecodeFailureIsNotDoubleReported() throws {
        let store = RTWorkspaceStore(workflowID: WorkflowKey.rt.rawValue)
        let vault = AnalysisVault()
        store.vault = vault

        let validResult = try JSONEncoder().encode(RTPackResult())
        let pack = AnalysisPack(
            label: "Corrupt RT Pack",
            workflowID: "rt",
            filePaths: [],
            sampleKeys: [],
            config: Data("not valid json".utf8),
            result: validResult
        )
        vault.add(pack)

        store.loadPack(id: pack.id) { _, _ in }

        #expect(store.analysisMessage?.hasPrefix("Failed to decode pack data") == true,
                "generic decode failures must still surface through the pre-existing loadPack path")
        #expect(store.packRestoreErrorMessage == nil,
                "restoreFromPack never ran, so the restore-time channel must stay untouched — no double report")
        #expect(store.activePackID == nil)
    }
}

@Suite("V6B RSM async restore migration to shared reporting")
struct V6BRSMAsyncRestoreTests {

    private let rsmValidSource = """
    H     K     L     Detector
    -1.0  0.0   1.0   100.0
     0.0  0.0   1.0   200.0
     1.0  0.0   1.0   150.0
    -1.0  0.0   1.5   110.0
     0.0  0.0   1.5   250.0
     1.0  0.0   1.5   180.0
    """

    @MainActor
    private func makePack(sourceIdentity: String) throws -> (store: RSMWorkspaceStore, vault: AnalysisVault, pack: AnalysisPack) {
        let store = RSMWorkspaceStore(workflowID: WorkflowKey.rsm.rawValue)
        let vault = AnalysisVault()
        store.vault = vault
        let config = RSMPackConfig(
            packState: RSMPackState(
                sourceFileIdentity: sourceIdentity,
                detectorColumnName: "Detector",
                activeView: .hl
            ),
            displayState: HeatmapTabRenderState()
        )
        let pack = try AnalysisPack(
            label: "RSM Restore Fixture",
            workflowID: "rsm",
            filePaths: [sourceIdentity],
            sampleKeys: [],
            config: config,
            result: RSMPackResult()
        )
        vault.add(pack)
        return (store, vault, pack)
    }

    @MainActor
    @Test("RSM: missing source file surfaces through shared PackRestoreFailureReporting once the async reparse finishes")
    func rsmMissingSourceFileSurfacesThroughSharedReporting() async throws {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("v6b-rsm-missing-\(UUID().uuidString).dat").path
        let fixture = try makePack(sourceIdentity: missingPath)

        fixture.store.loadPack(id: fixture.pack.id) { _, _ in }

        // loadPack()'s synchronous check cannot see the failure yet — restoreFromPack's
        // async reparse task has not completed. This is the timing gap Phase 6B closes.
        var observedFailureMessage: String?
        for _ in 0..<200 {
            if let message = fixture.store.packRestoreErrorMessage {
                observedFailureMessage = message
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        let message = try #require(observedFailureMessage,
                                    "RSM restore failure must eventually surface through packRestoreErrorMessage")
        #expect(fixture.store.analysisMessage == message,
                "analysisMessage must be corrected once the async failure is known, same as the ThreeOmega sync path")
        #expect(fixture.store.activePackID == nil,
                "a pack whose restore ultimately failed must not be left marked active")
    }

    @MainActor
    @Test("RSM: successful disk reparse does not emit a failure message")
    func rsmSuccessfulReparseDoesNotEmitFailureMessage() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v6b-rsm-valid-\(UUID().uuidString).dat")
        try rsmValidSource.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let fixture = try makePack(sourceIdentity: tempURL.path)
        fixture.store.packRestoreErrorMessage = "stale from a previous attempt"

        fixture.store.loadPack(id: fixture.pack.id) { _, _ in }

        var succeeded = false
        for _ in 0..<200 {
            if fixture.store.renderedImageData != nil {
                succeeded = true
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(succeeded, "restore should have rendered the heatmap from the valid source file")
        #expect(fixture.store.packRestoreErrorMessage == nil,
                "a successful async reparse must not leave a stale or manufactured failure message")
        #expect(fixture.store.analysisMessage == "Loaded: \(fixture.pack.label)")
        #expect(fixture.store.activePackID == fixture.pack.id)
    }
}

@Suite("V6B shared UI integration — no workflow-specific branching")
struct V6BSharedUIIntegrationTests {

    @Test("WorkbenchLoadPackPopover has no PackRestoreFailureReporting-specific or workflow-ID branching")
    func loadPackPopoverHasNoWorkflowSpecificBranching() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root.appendingPathComponent("Sources/SpinLabApp/Features/Workbench/WorkbenchLoadPackPopover.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        #expect(!source.contains("PackRestoreFailureReporting"),
                "the popover must stay protocol-agnostic — restore failures surface generically through analysisMessage")
        #expect(!source.contains("packRestoreErrorMessage"),
                "the popover must not read the restore-time channel directly")
    }
}
