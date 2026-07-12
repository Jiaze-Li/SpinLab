import Foundation
import Testing
@testable import SpinLabApp

@Suite("Title visibility UI interactions (Gate showTitle Phase 3)")
struct V569TitleVisibilityUIInteractionTests {

    // MARK: - Helpers

    private func waitForCondition(
        timeoutSteps: Int = 40,
        stepNanoseconds: UInt64 = 50_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<timeoutSteps {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: stepNanoseconds)
        }
        return await condition()
    }

    private func makeXYSweep() -> XYRotationAngleSweep {
        XYRotationAngleSweep(
            temperatureK: 80,
            stem: "xy-sample",
            sourceKind: .lvm,
            angleDeg: [0.0, 120.0, 240.0, 360.0],
            resistanceXX: [1.0, 1.1, 0.95, 1.0],
            resistanceXY: [0.1, 0.05, -0.05, 0.1],
            defaultPhiOffset: 0.0,
            measurementFilePath: "/tmp/xy-sample.lvm"
        )
    }

    private func makeTwoPointScalingResult() -> ThreeOmegaScalingResult {
        ThreeOmegaScalingResult(
            points: [
                ThreeOmegaScalingPoint(temperatureK: 10, sigma2xx: 4.0, scalingY: 3.0),
                ThreeOmegaScalingPoint(temperatureK: 20, sigma2xx: 9.0, scalingY: 1.0)
            ],
            segments: [
                ThreeOmegaScalingSegment(
                    id: UUID(),
                    tLo: 10,
                    tHi: 20,
                    alpha: 1.0,
                    beta: 2.0,
                    rSquared: 0.99,
                    pointCount: 2,
                    participatingXValues: [4.0, 9.0]
                )
            ],
            warnings: []
        )
    }

    private func makeRSMText() -> String {
        """
        H K L Detector
        0.0 0.0 0.0 1.0
        1.0 0.0 0.0 2.0
        0.0 0.0 1.0 3.0
        1.0 0.0 1.0 4.0
        """
    }

    // MARK: - Cartesian XY

    @MainActor
    @Test("XY title toggle defaults on, rerenders the active tab, and stays tab-isolated across restore")
    func xyTitleToggleRerendersAndRestoresPerTabState() async throws {
        let store = XYRotationWorkspaceStore(workflowID: WorkflowKey.xyRotation.rawValue)
        store.ingestionResult = XYRotationIngestionResult(
            sweeps: [makeXYSweep()],
            device: "0deg",
            warnings: []
        )
        store.tabs.activeTab = .rxxVsPhi
        store.tabs.tabStates[.rxxVsPhi] = TabRenderState(showTitle: true)
        store.tabs.tabStates[.rxyVsPhi] = TabRenderState(showTitle: true)

        #expect(store.tabs.state(for: .rxxVsPhi).showTitle, "Title checkbox must default to on")

        store.tabs.updateShowTitle(false)
        store.rerenderForStyleChange()

        let rerendered = await waitForCondition {
            store.tabs.output(for: .rxxVsPhi).layout?.showTitle == false
        }
        #expect(rerendered, "Toggling Title off must trigger a rerender for the active tab")
        #expect(store.tabs.state(for: .rxxVsPhi).showTitle == false)
        #expect(store.tabs.output(for: .rxxVsPhi).layout?.showTitle == false)
        #expect(store.tabs.state(for: .rxyVsPhi).showTitle == true)

        store.tabs.activeTab = .rxyVsPhi
        store.rerenderForStyleChange()
        let switched = await waitForCondition {
            store.tabs.output(for: .rxyVsPhi).layout?.showTitle == true
        }
        #expect(switched)
        #expect(store.tabs.state(for: .rxxVsPhi).showTitle == false)
        #expect(store.tabs.state(for: .rxyVsPhi).showTitle == true)

        let hit = WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/xy-sample.lvm.spinlab.json",
            measurementFilePath: "/tmp/xy-sample.lvm",
            sourceFilePath: "/tmp/xy-sample.lvm",
            workflowID: WorkflowKey.xyRotation.rawValue,
            workflowDisplayName: "XY Rotation",
            workflowCanonicalID: WorkflowKey.xyRotation.rawValue,
            batchID: "PN31",
            sampleKey: "PN31|b|STO|111",
            sampleSubstrate: "STO111",
            conditions: [:],
            channels: ["ch1"],
            appliedAt: .distantPast
        )
        let config = XYRotationPackConfig(
            phiOffsetOverrides: [:],
            centerBaseline: false,
            linearDetrend: false,
            activeTab: XYRotationWorkbenchTab.rxxVsPhi.rawValue,
            titleTemplate: "#tab",
            stackOffsetMultiplier: 0.0,
            minGapFraction: 0.15,
            showPlotGrid: true,
            showAuxiliaryLine180: false,
            legendAnchor: "",
            seriesRenderMode: .line,
            chartStyleOverrides: [:],
            tabStates: [
                XYRotationWorkbenchTab.rxxVsPhi.rawValue: TabRenderState(showTitle: false),
                XYRotationWorkbenchTab.rxyVsPhi.rawValue: TabRenderState(showTitle: true)
            ],
            cachedSearchResults: [hit],
            selectedSearchResultIDs: [],
            searchQueryText: ""
        )
        let result = XYRotationPackResult(ingestionResult: store.ingestionResult!)
        let pack = try AnalysisPack(
            label: "XY Title Visibility",
            workflowID: WorkflowKey.xyRotation.rawValue,
            filePaths: ["/tmp/xy-sample.lvm"],
            sampleKeys: [hit.sampleKey],
            config: config,
            result: result
        )

        let restored = XYRotationWorkspaceStore(workflowID: WorkflowKey.xyRotation.rawValue)
        restored.restoreFromPack(
            config: config,
            result: result,
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )
        #expect(restored.tabs.state(for: .rxxVsPhi).showTitle == false)
        #expect(restored.tabs.state(for: .rxyVsPhi).showTitle == true)
    }

    // MARK: - DualAxis

    @MainActor
    @Test("DualAxis title toggle defaults on, rerenders, and survives pack restore")
    func dualAxisTitleToggleRerendersAndRestores() async throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.scalingResult = makeTwoPointScalingResult()
        store.temperatureDependenceDisplayState = DualAxisDisplayState(showTitle: true)

        #expect(store.temperatureDependenceDisplayState.showTitle, "Title checkbox must default to on")

        store.temperatureDependenceDisplayState.showTitle = false
        store.rerenderTemperatureDependenceForDualAxisControlChange()

        let rerendered = await waitForCondition {
            store.tabs.output(for: .temperatureDependence).dualAxisLayout?.showTitle == false
        }
        #expect(rerendered, "Toggling Title off must trigger a rerender for the DualAxis tab")
        #expect(store.temperatureDependenceDisplayState.showTitle == false)
        #expect(store.tabs.output(for: .temperatureDependence).dualAxisLayout?.showTitle == false)

        let config = ThreeOmegaPackConfig(
            device: "0deg",
            geometry: ThreeOmegaGeometry(),
            fitRanges: [],
            v3Method: ThreeOmegaV3Method.highField.rawValue,
            rahe1Method: ThreeOmegaV3Method.highField.rawValue,
            rahe3Method: ThreeOmegaV3Method.highField.rawValue,
            rtFilePath: nil,
            sampleBatchAndSubstrate: "",
            activeTab: ThreeOmegaWorkbenchTab.temperatureDependence.rawValue,
            titleTemplate: "#tab",
            stackOffsetMultiplier: 0.0,
            minGapFraction: 0.15,
            showPlotGrid: true,
            plotLegendAnchor: "",
            seriesRenderMode: .line,
            tabStates: [:],
            chartStyleOverrides: [:],
            temperatureDependenceDisplayState: DualAxisDisplayStateSnapshot(showTitle: false),
            cachedSearchResults: [],
            selectedSearchResultIDs: [],
            selectedRTHit: nil,
            rtQuery: "",
            searchQueryText: ""
        )
        let packResult = ThreeOmegaPackResult(
            ingestionResult: ThreeOmegaIngestionResult(
                fieldSweeps: [],
                rtResult: nil,
                device: "0deg",
                deviceMode: "single",
                devices: [],
                iRmsValues: [:],
                warnings: []
            ),
            scalingResult: makeTwoPointScalingResult()
        )
        let pack = try AnalysisPack(
            label: "3ω Title Visibility",
            workflowID: WorkflowKey.threeOmega.rawValue,
            filePaths: [],
            sampleKeys: [],
            config: config,
            result: packResult
        )

        let restored = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        restored.restoreFromPack(
            config: config,
            result: packResult,
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )
        #expect(restored.temperatureDependenceDisplayState.showTitle == false)
    }

    // MARK: - Heatmap

    @MainActor
    @Test("Heatmap title toggle defaults on, rerenders, and survives pack restore")
    func heatmapTitleToggleRerendersAndRestores() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rsm-title-visibility-\(UUID().uuidString).txt")
        try makeRSMText().write(to: tempURL, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let makeConfig: (Bool) -> RSMPackConfig = { showTitle in
            RSMPackConfig(
                packState: RSMPackState(
                    sourceFileIdentity: tempURL.path,
                    detectorColumnName: "Detector",
                    activeView: .hl
                ),
                displayState: HeatmapTabRenderState(showTitle: showTitle),
                cachedSearchResults: [],
                searchQueryText: ""
            )
        }
        let result = RSMPackResult()
        let pack = try AnalysisPack(
            label: "RSM Title Visibility",
            workflowID: WorkflowKey.rsm.rawValue,
            filePaths: [tempURL.path],
            sampleKeys: ["sample-1"],
            config: makeConfig(true),
            result: result
        )

        let restored = RSMWorkspaceStore(workflowID: WorkflowKey.rsm.rawValue)
        restored.restoreFromPack(
            config: makeConfig(true),
            result: result,
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )
        let initialRendered = await waitForCondition {
            restored.renderedImageData != nil
        }
        #expect(initialRendered)
        let initialImageData = restored.renderedImageData
        #expect(restored.heatmapDisplayState.showTitle)

        restored.updateHeatmapShowTitle(false)
        let rerendered = await waitForCondition {
            restored.heatmapDisplayState.showTitle == false && restored.renderedImageData != initialImageData
        }
        #expect(rerendered, "Toggling Title off must trigger a rerender for the heatmap tab")
        #expect(restored.heatmapDisplayState.showTitle == false)

        let restoredPack = RSMWorkspaceStore(workflowID: WorkflowKey.rsm.rawValue)
        restoredPack.restoreFromPack(
            config: makeConfig(false),
            result: result,
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )
        let restoredMatch = await waitForCondition {
            restoredPack.heatmapDisplayState.showTitle == false && restoredPack.renderedImageData != nil
        }
        #expect(restoredMatch)
        #expect(restoredPack.heatmapDisplayState.showTitle == false)
    }
}
