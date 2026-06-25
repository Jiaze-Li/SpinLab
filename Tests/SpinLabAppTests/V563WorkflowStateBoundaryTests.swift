import Foundation
import Testing
@testable import SpinLabApp

@Suite("Workflow State Boundaries")
struct V563WorkflowStateBoundaryTests {
    private func makeSearchHit(
        id: String = "hit-1",
        sampleKey: String = "PN31|b|STO|111",
        workflowID: String = "ahe",
        workflowCanonicalID: String = "ahe"
    ) -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/\(id).spinlab.json",
            measurementFilePath: "/tmp/\(id).dat",
            sourceFilePath: "/tmp/\(id).dat",
            workflowID: workflowID,
            workflowDisplayName: "AHE",
            workflowCanonicalID: workflowCanonicalID,
            batchID: "PN31",
            sampleKey: sampleKey,
            sampleSubstrate: "STO111",
            conditions: ["temperature": "80K"],
            channels: ["ch1"],
            appliedAt: .distantPast
        )
    }

    @MainActor
    @Test("TabRenderManager owns plot outputs; activeImageData is a projection")
    func tabRenderManagerActiveImageDataIsProjection() {
        enum TestTab: Hashable, Sendable { case first }

        let manager = TabRenderManager<TestTab>(defaultTab: .first)
        #expect(manager.activeImageData == nil)
        #expect(manager.activeLayout == nil)

        manager.setOutput(
            TabRenderOutput(
                imageData: Data([0x01, 0x02]),
                layout: nil,
                manifestPayload: nil
            ),
            for: .first
        )

        #expect(manager.activeImageData == Data([0x01, 0x02]))
        #expect(manager.output(for: .first).imageData == Data([0x01, 0x02]))

        manager.clearOutputs()
        #expect(manager.activeImageData == nil)
        #expect(manager.output(for: .first).imageData == nil)
    }

    @Test("Reorderable payloads use stable sourceRef identity")
    func reorderablePayloadUsesStableSourceRefIdentity() throws {
        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "test",
            title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [
                WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0, 1], sourceRef: "/tmp/a.csv", sampleID: "sample-a"),
                WorkbenchPlotSeries(label: "B", x: [0, 1], y: [1, 2], sourceRef: "/tmp/b.csv", sampleID: "sample-b")
            ],
            seriesReorderable: true
        )

        #expect(payload.series.allSatisfy { ($0.sourceRef?.isEmpty == false) })

        var input = WorkbenchRenderPipeline.Input(payload: payload)
        input.seriesOrder = ["/tmp/a.csv", "/tmp/b.csv"]
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.warnings.isEmpty)
    }

    @Test("LibraryRootAccess requires bookmark-backed discovery in sandboxed mode")
    func libraryRootAccessRequiresBookmarkForSandboxedDiscovery() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "spinlab-boundary-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let settings = LibrarySettings(
            rootPath: root.path,
            rootBookmarkData: nil,
            registryInternalPath: nil,
            registrySourcePath: nil,
            backupPath: nil,
            backupLastSyncedAt: nil,
            allowedBatchPrefixes: [],
            lastRefreshAt: nil
        )

        let status = LibraryRootAccess().resolveRootURL(settings: settings, sandboxed: true)
        #expect(status == .missingBookmark)
    }

    @MainActor
    @Test("Canvas-facing reads project canonical tab output")
    func canvasFacingReadsProjectCanonicalTabOutput() {
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        let adapterEmpty = WorkbenchReadAdapter(store: store)
        #expect(adapterEmpty.activeImageData == nil)

        store.tabs.setOutput(
            TabRenderOutput(
                imageData: Data([0xAA]),
                layout: nil,
                manifestPayload: nil
            ),
            for: .ahe
        )

        let adapter = WorkbenchReadAdapter(store: store)
        #expect(adapter.activeImageData == Data([0xAA]))
        #expect(store.tabs.activeImageData == Data([0xAA]))

        store.tabs.clearOutputs()
        let afterClear = WorkbenchReadAdapter(store: store)
        #expect(afterClear.activeImageData == nil)
    }

    @Test("WorkbenchPlotCanvas exposes no series reorder API surface")
    func plotCanvasDoesNotExposeSeriesReorderSurface() {
        let canvas = WorkbenchPlotCanvas(imageData: nil)
        let labels = Mirror(reflecting: canvas).children.compactMap(\.label)

        #expect(!labels.contains("onSeriesOrderCommit"))
        #expect(!labels.contains("seriesOrderPayload"))
        #expect(!labels.contains("seriesReorderable"))
        #expect(!labels.contains(where: { $0.localizedCaseInsensitiveContains("reorder") }))
    }

    @Test("Reorderable payloads require unique series identity keys")
    func reorderablePayloadRequiresUniqueSeriesIdentityKeys() {
        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "test",
            title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [
                WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0, 1], sourceRef: "/tmp/a.csv", sampleID: "sample-a"),
                WorkbenchPlotSeries(label: "B", x: [0, 1], y: [1, 2], sourceRef: "/tmp/b.csv", sampleID: "sample-a")
            ],
            seriesReorderable: true
        )

        let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: payload.series)
        #expect(Set(identities.map(\.identityKey)).count == identities.count)
        #expect(identities.map(\.identityKey) == ["/tmp/a.csv", "/tmp/b.csv"])
    }

    // MARK: - rerenderFieldSweepTabs override isolation (Phase 4 fix)

    @MainActor
    @Test("rerenderFieldSweepTabs does not clear per-tab title and label overrides from tabStates")
    func rerenderFieldSweepTabsPreservesTabStateOverrides() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.tabs.tabStates[.fieldSweep1omega] = TabRenderState(
            titleOverride: "Custom 1ω Title",
            xLabelOverride: "My X",
            yLabelOverride: "My Y",
            seriesLabelOverrides: ["sample-a": "Sample A"]
        )
        store.tabs.tabStates[.fieldSweep3omega] = TabRenderState(
            titleOverride: "Custom 3ω Title"
        )
        // ingestionResult is nil → early return; verifies tabStates are never touched by this path
        store.rerenderFieldSweepTabs()
        let s1 = store.tabs.state(for: .fieldSweep1omega)
        let s3 = store.tabs.state(for: .fieldSweep3omega)
        #expect(s1.titleOverride == "Custom 1ω Title")
        #expect(s1.xLabelOverride == "My X")
        #expect(s1.yLabelOverride == "My Y")
        #expect(s1.seriesLabelOverrides == ["sample-a": "Sample A"])
        #expect(s3.titleOverride == "Custom 3ω Title")
    }

    @MainActor
    @Test("rerenderFieldSweepTabs tab state overrides are isolated per tab")
    func rerenderFieldSweepTabsOverridesAreTabIsolated() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.tabs.tabStates[.fieldSweep1omega] = TabRenderState(
            titleOverride: "Only 1ω",
            seriesLabelOverrides: ["sample-a": "A"]
        )
        // 3ω starts with no overrides
        store.rerenderFieldSweepTabs()
        let s1 = store.tabs.state(for: .fieldSweep1omega)
        let s3 = store.tabs.state(for: .fieldSweep3omega)
        #expect(s1.titleOverride == "Only 1ω")
        #expect(s1.seriesLabelOverrides == ["sample-a": "A"])
        #expect(s3.titleOverride == "")
        #expect(s3.seriesLabelOverrides.isEmpty)
    }

    // MARK: - runScaling override preservation (Phase 4B fix)

    @MainActor
    @Test("runScaling does not clear scaling-tab text overrides from tabStates")
    func runScalingPreservesScalingTabTextOverrides() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.tabs.tabStates[.scaling] = TabRenderState(
            titleOverride: "My Scaling Title",
            xLabelOverride: "Custom X",
            yLabelOverride: "Custom Y"
        )
        // ingestionResult is nil → early return; verifies tabStates are never touched by this path
        store.runScaling()
        let state = store.tabs.state(for: .scaling)
        #expect(state.titleOverride == "My Scaling Title")
        #expect(state.xLabelOverride == "Custom X")
        #expect(state.yLabelOverride == "Custom Y")
    }

    // MARK: - clearStates lifecycle (Phase 4 boundary doc)

    @MainActor
    @Test("clearStates preserves legendPoint and seriesOrder; wipes text overrides")
    func clearStatesPreservesSeriesOrderAndLegendPointOnly() {
        enum TestTab: Hashable, Sendable { case first }
        let manager = TabRenderManager<TestTab>(defaultTab: .first)
        manager.tabStates[.first] = TabRenderState(
            legendPoint: CGPointCodable(CGPoint(x: 0.5, y: 0.5)),
            titleOverride: "My Title",
            xLabelOverride: "X",
            yLabelOverride: "Y",
            seriesLabelOverrides: ["a": "A"],
            seriesOrder: ["key1", "key2"]
        )
        manager.clearStates()
        let state = manager.state(for: .first)
        #expect(state.legendPoint?.cgPoint == CGPoint(x: 0.5, y: 0.5))
        #expect(state.seriesOrder == ["key1", "key2"])
        #expect(state.titleOverride == "")
        #expect(state.xLabelOverride == "")
        #expect(state.yLabelOverride == "")
        #expect(state.seriesLabelOverrides.isEmpty)
    }

    // MARK: - fieldSweepSeriesOrder symmetry

    @MainActor
    @Test("setFieldSweepSeriesOrder writes the same order to both field-sweep tabs")
    func setFieldSweepSeriesOrderWritesBothTabs() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let order = ["key-a|0", "key-b|1"]
        store.setFieldSweepSeriesOrder(order)
        #expect(store.tabs.state(for: .fieldSweep1omega).seriesOrder == order)
        #expect(store.tabs.state(for: .fieldSweep3omega).seriesOrder == order)
    }

    // MARK: - _refreshManifestPayloads override preservation (Phase 4C-2 fix)

    @MainActor
    @Test("_refreshManifestPayloads applies tabState title and series-label overrides to rebuilt manifests")
    func refreshManifestPayloadsAppliesTabStateOverrides() throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let sweep = ThreeOmegaFieldSweepResult(
            temperatureK: 100,
            device: "0deg",
            sampleMetadata: ["device": "0deg"],
            sampleID: "sample-a",
            sourceFilePath: "/tmp/sample-a.csv",
            hField: [-1000, 0, 1000],
            r1omega: [-1, 0, 1],
            r3omega: [-2, 0, 2],
            iRms: 1e-3,
            rahe1omega: 1.0,
            rahe1omegaWA: 1.0,
            hc1omega: 0.0,
            hc3omega: 0.0,
            v3omegaWindow: 2e-5,
            v3omegaFit: 2e-5
        )
        store.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: [sweep],
            rtResult: nil,
            device: "0deg",
            deviceMode: "single",
            devices: ["0deg"],
            iRmsValues: [100: 1e-3],
            warnings: []
        )
        store.cachedInputFiles = ["/tmp/sample-a.csv"]

        store.tabs.tabStates[.hcVsT] = TabRenderState(
            titleOverride: "My Hc Title",
            xLabelOverride: "My X Axis",
            yLabelOverride: "My Y Axis"
        )
        store.tabs.tabStates[.fieldSweep1omega] = TabRenderState(
            titleOverride: "My 1ω Title",
            seriesLabelOverrides: ["sample-a": "Renamed Series"]
        )

        store._refreshManifestPayloads()

        let hcPayload = store.tabs.output(for: .hcVsT).manifestPayload
        #expect(hcPayload?.title == "My Hc Title")
        #expect(hcPayload?.axisMapping.xField == "My X Axis")
        #expect(hcPayload?.axisMapping.yField == "My Y Axis")

        let r1Payload = store.tabs.output(for: .fieldSweep1omega).manifestPayload
        #expect(r1Payload?.title == "My 1ω Title")
        #expect(r1Payload?.series.first(where: { $0.sampleID == "sample-a" })?.label == "Renamed Series")

        // Tabs without overrides are unaffected
        let r3Payload = store.tabs.output(for: .fieldSweep3omega).manifestPayload
        #expect(r3Payload?.title != "My 1ω Title")
    }

    // MARK: - rerenderFieldSweepTabs manifest parity (Phase 4C-2 fix)

    @MainActor
    @Test("rerenderFieldSweepTabs patches each tab's manifest with its own overrides, no cross-tab bleed")
    func rerenderFieldSweepTabsDoesNotBleed1omegaOverrideInto3omega() async throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let sweep = ThreeOmegaFieldSweepResult(
            temperatureK: 100,
            device: "0deg",
            sampleMetadata: ["device": "0deg"],
            sampleID: "sample-a",
            sourceFilePath: "/tmp/sample-a.csv",
            hField: [-1000, 0, 1000],
            r1omega: [-1, 0, 1],
            r3omega: [-2, 0, 2],
            iRms: 1e-3,
            rahe1omega: 1.0,
            rahe1omegaWA: 1.0,
            hc1omega: 0.0,
            hc3omega: 0.0,
            v3omegaWindow: 2e-5,
            v3omegaFit: 2e-5
        )
        store.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: [sweep],
            rtResult: nil,
            device: "0deg",
            deviceMode: "single",
            devices: ["0deg"],
            iRmsValues: [100: 1e-3],
            warnings: []
        )
        // Seed base manifests (simulate post-analysis state)
        let base1 = WorkbenchPlotPayload(
            workflowID: "3w", workflowDisplayName: "3w",
            title: "Base 1ω",
            axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R(1ω) (Ω)"),
            series: [WorkbenchPlotSeries(label: "100 K", x: [], y: [], sourceRef: "/tmp/sample-a.csv", sampleID: "sample-a")],
            seriesReorderable: true
        )
        let base3 = WorkbenchPlotPayload(
            workflowID: "3w", workflowDisplayName: "3w",
            title: "Base 3ω",
            axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R(3ω) (Ω)"),
            series: [WorkbenchPlotSeries(label: "100 K", x: [], y: [], sourceRef: "/tmp/sample-a.csv", sampleID: "sample-a")],
            seriesReorderable: true
        )
        store.tabs.setOutput(TabRenderOutput(imageData: nil, layout: nil, manifestPayload: base1), for: .fieldSweep1omega)
        store.tabs.setOutput(TabRenderOutput(imageData: nil, layout: nil, manifestPayload: base3), for: .fieldSweep3omega)

        // Only 1ω has overrides; 3ω is untouched
        store.tabs.tabStates[.fieldSweep1omega] = TabRenderState(
            titleOverride: "Custom 1ω",
            seriesLabelOverrides: ["sample-a": "Renamed A"]
        )

        store.rerenderFieldSweepTabs()

        var attempts = 0
        while store.tabs.output(for: .fieldSweep1omega).layout == nil && attempts < 40 {
            try await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        let out1 = store.tabs.output(for: .fieldSweep1omega)
        #expect(out1.imageData != nil)
        #expect(out1.manifestPayload?.title == "Custom 1ω")
        #expect(out1.manifestPayload?.series.first(where: { $0.sampleID == "sample-a" })?.label == "Renamed A")

        let out3 = store.tabs.output(for: .fieldSweep3omega)
        #expect(out3.imageData != nil)
        // 3ω must not inherit the 1ω override
        #expect(out3.manifestPayload?.title == "Base 3ω")
        #expect(out3.manifestPayload?.series.first(where: { $0.sampleID == "sample-a" })?.label == "100 K")
    }

    @MainActor
    @Test("3ω active-tab style rerender keeps payload identity and reflects active overrides")
    func threeOmegaActiveTabRerenderPreservesPayloadContract() async throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.tabs.activeTab = .fieldSweep1omega

        let sweep = ThreeOmegaFieldSweepResult(
            temperatureK: 100,
            device: "0deg",
            sampleMetadata: ["device": "0deg"],
            sampleID: "sample-a",
            sourceFilePath: "/tmp/sample-a.csv",
            hField: [-1000, 0, 1000],
            r1omega: [-1, 0, 1],
            r3omega: [-2, 0, 2],
            iRms: 1e-3,
            rahe1omega: 1.0,
            rahe1omegaWA: 1.0,
            hc1omega: 0.0,
            hc3omega: 0.0,
            v3omegaWindow: 2e-5,
            v3omegaFit: 2e-5
        )
        store.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: [sweep],
            rtResult: nil,
            device: "0deg",
            deviceMode: "single",
            devices: ["0deg"],
            iRmsValues: [100: 1e-3],
            warnings: []
        )

        let baseManifest = WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: "Base Title",
            axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R(1ω) (Ω)"),
            series: [
                WorkbenchPlotSeries(
                    label: "100 K",
                    x: [0, 1],
                    y: [0, 1],
                    sourceRef: "/tmp/sample-a.csv",
                    sampleID: "sample-a"
                )
            ],
            semanticParams: ["tabKey": ThreeOmegaWorkbenchTab.fieldSweep1omega.stableKey],
            seriesReorderable: true
        )
        store.tabs.setOutput(
            TabRenderOutput(
                imageData: Data([0x01]),
                layout: nil,
                manifestPayload: baseManifest
            ),
            for: .fieldSweep1omega
        )

        store.tabs.tabStates[.fieldSweep1omega] = TabRenderState(
            titleOverride: "Custom 1ω Title",
            xLabelOverride: "My X Label",
            yLabelOverride: "My Y Label",
            seriesLabelOverrides: ["sample-a": "Renamed Series"]
        )

        store.rerenderForStyleChange()

        var attempts = 0
        while store.tabs.activeLayout == nil && attempts < 40 {
            try await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        let output = store.tabs.output(for: .fieldSweep1omega)
        #expect(output.imageData != nil)
        #expect(output.layout != nil)
        #expect(output.manifestPayload != nil)
        #expect(output.manifestPayload?.series.allSatisfy { ($0.sourceRef?.isEmpty == false) } == true)
        #expect(output.manifestPayload?.title == "Custom 1ω Title")
        #expect(output.manifestPayload?.axisMapping.xField == "My X Label")
        #expect(output.manifestPayload?.axisMapping.yField == "My Y Label")
        #expect(output.manifestPayload?.series.first?.label == "Renamed Series")
    }

    // MARK: - Axis label override parity — table-driven (Phase 4C-2 extension)

    struct AxisLabelCase: Sendable, CustomStringConvertible {
        let xOverride: String
        let yOverride: String
        var description: String {
            let x = xOverride.isEmpty ? "default" : "'\(xOverride)'"
            let y = yOverride.isEmpty ? "default" : "'\(yOverride)'"
            return "x=\(x) y=\(y)"
        }
    }

    @MainActor
    @Test("_refreshManifestPayloads reflects axis label overrides for all combinations", arguments: [
        AxisLabelCase(xOverride: "Custom X", yOverride: ""),
        AxisLabelCase(xOverride: "",          yOverride: "Custom Y"),
        AxisLabelCase(xOverride: "Custom X",  yOverride: "Custom Y"),
    ])
    func refreshManifestPayloadsReflectsAxisLabelOverrides(_ tc: AxisLabelCase) throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let sweep = ThreeOmegaFieldSweepResult(
            temperatureK: 100,
            device: "0deg",
            sampleMetadata: ["device": "0deg"],
            sampleID: "sample-a",
            sourceFilePath: "/tmp/sample-a.csv",
            hField: [-1000, 0, 1000],
            r1omega: [-1, 0, 1],
            r3omega: [-2, 0, 2],
            iRms: 1e-3,
            rahe1omega: 1.0,
            rahe1omegaWA: 1.0,
            hc1omega: 0.0,
            hc3omega: 0.0,
            v3omegaWindow: 2e-5,
            v3omegaFit: 2e-5
        )
        store.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: [sweep],
            rtResult: nil,
            device: "0deg",
            deviceMode: "single",
            devices: ["0deg"],
            iRmsValues: [100: 1e-3],
            warnings: []
        )
        store.cachedInputFiles = ["/tmp/sample-a.csv"]

        store.tabs.tabStates[.hcVsT] = TabRenderState(
            xLabelOverride: tc.xOverride,
            yLabelOverride: tc.yOverride
        )

        store._refreshManifestPayloads()

        let payload = store.tabs.output(for: .hcVsT).manifestPayload
        // Override present → manifest reflects it; absent → canonical default is preserved.
        if !tc.xOverride.isEmpty {
            #expect(payload?.axisMapping.xField == tc.xOverride)
        } else {
            #expect(payload?.axisMapping.xField == "T (K)")
        }
        if !tc.yOverride.isEmpty {
            #expect(payload?.axisMapping.yField == tc.yOverride)
        } else {
            #expect(payload?.axisMapping.yField == "Hc (Oe)")
        }
    }

    // MARK: - All non-RT tabs × all text overrides — table-driven (Phase 4C-2 Message 4)

    struct ThreeOmegaTabOverrideCase: Sendable, CustomStringConvertible {
        let tabKey: String
        let xCanonical: String
        let yCanonical: String
        var description: String { tabKey }
    }

    @MainActor
    @Test("_refreshManifestPayloads preserves text overrides for all non-RT 3ω tabs", arguments: [
        ThreeOmegaTabOverrideCase(tabKey: "fieldSweep1omega", xCanonical: "H (T)",        yCanonical: "R(1ω) (Ω)"),
        ThreeOmegaTabOverrideCase(tabKey: "fieldSweep3omega", xCanonical: "H (T)",        yCanonical: "R(3ω) (Ω)"),
        ThreeOmegaTabOverrideCase(tabKey: "rahe1omegaVsT",   xCanonical: "T (K)",         yCanonical: "RAHE(1ω) (Ω)"),
        ThreeOmegaTabOverrideCase(tabKey: "rahe3omegaVsT",   xCanonical: "T (K)",         yCanonical: "RAHE(3ω) (Ω)"),
        ThreeOmegaTabOverrideCase(tabKey: "hcVsT",           xCanonical: "T (K)",         yCanonical: "Hc (Oe)"),
        ThreeOmegaTabOverrideCase(tabKey: "scaling",         xCanonical: "σ²_xx (S²/m²)", yCanonical: "E(3ω)_AHE / (E³_xx · σ_xx)"),
    ])
    func refreshManifestAllNonRTTabsPreserveTextOverrides(_ tc: ThreeOmegaTabOverrideCase) throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let sweep = ThreeOmegaFieldSweepResult(
            temperatureK: 100, device: "0deg",
            sampleMetadata: ["device": "0deg"], sampleID: "sample-a",
            sourceFilePath: "/tmp/sample-a.csv",
            hField: [-1000, 0, 1000], r1omega: [-1, 0, 1], r3omega: [-2, 0, 2],
            iRms: 1e-3, rahe1omega: 1.0, rahe1omegaWA: 1.0,
            hc1omega: 0.0, hc3omega: 0.0, v3omegaWindow: 2e-5, v3omegaFit: 2e-5
        )
        store.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: [sweep], rtResult: nil, device: "0deg",
            deviceMode: "single", devices: ["0deg"], iRmsValues: [100: 1e-3], warnings: []
        )
        store.cachedInputFiles = ["/tmp/sample-a.csv"]

        guard let tab = ThreeOmegaWorkbenchTab.allCases.first(where: { $0.stableKey == tc.tabKey }) else {
            Issue.record("Unknown tabKey: \(tc.tabKey)")
            return
        }

        store.tabs.tabStates[tab] = TabRenderState(
            titleOverride: "Title-\(tc.tabKey)",
            xLabelOverride: "X-\(tc.tabKey)",
            yLabelOverride: "Y-\(tc.tabKey)"
        )

        store._refreshManifestPayloads()

        let payload = store.tabs.output(for: tab).manifestPayload
        #expect(payload?.title == "Title-\(tc.tabKey)")
        #expect(payload?.axisMapping.xField == "X-\(tc.tabKey)")
        #expect(payload?.axisMapping.yField == "Y-\(tc.tabKey)")

        // Sibling tabs must not inherit overrides from this tab
        for sibling in ThreeOmegaWorkbenchTab.allCases where sibling != tab && sibling != .rtCurve {
            let sibPayload = store.tabs.output(for: sibling).manifestPayload
            #expect(sibPayload?.axisMapping.xField != "X-\(tc.tabKey)")
            #expect(sibPayload?.axisMapping.yField != "Y-\(tc.tabKey)")
        }
    }

    // MARK: - runScaling manifest override preservation (Phase 4C-2 Message 4)

    @MainActor
    @Test("runScaling path: _refreshManifestPayloads reflects scaling-tab text overrides in rebuilt manifest")
    func threeOmegaRunScalingPreservesManifestOverrides() throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let sweep = ThreeOmegaFieldSweepResult(
            temperatureK: 100, device: "0deg",
            sampleMetadata: ["device": "0deg"], sampleID: "sample-a",
            sourceFilePath: "/tmp/sample-a.csv",
            hField: [-1000, 0, 1000], r1omega: [-1, 0, 1], r3omega: [-2, 0, 2],
            iRms: 1e-3, rahe1omega: 1.0, rahe1omegaWA: 1.0,
            hc1omega: 0.0, hc3omega: 0.0, v3omegaWindow: 2e-5, v3omegaFit: 2e-5
        )
        store.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: [sweep], rtResult: nil, device: "0deg",
            deviceMode: "single", devices: ["0deg"], iRmsValues: [100: 1e-3], warnings: []
        )
        store.cachedInputFiles = ["/tmp/sample-a.csv"]

        store.tabs.tabStates[.scaling] = TabRenderState(
            titleOverride: "My Scaling Title",
            xLabelOverride: "Custom σ²",
            yLabelOverride: "Custom AHE"
        )

        // Direct call mirrors what runScaling executes after its async compute phase
        store._refreshManifestPayloads()

        let payload = store.tabs.output(for: .scaling).manifestPayload
        #expect(payload?.title == "My Scaling Title")
        #expect(payload?.axisMapping.xField == "Custom σ²")
        #expect(payload?.axisMapping.yField == "Custom AHE")

        // Sibling tab must not absorb scaling overrides
        let hcPayload = store.tabs.output(for: .hcVsT).manifestPayload
        #expect(hcPayload?.axisMapping.xField == "T (K)")
        #expect(hcPayload?.axisMapping.yField == "Hc (Oe)")
    }

    // MARK: - _rebuildOverlayManifestPayloads override preservation (Phase 4C-2 Message 4)

    @MainActor
    @Test("_rebuildOverlayManifestPayloads applies per-tab overrides independently for RAHE1ω and RAHE3ω")
    func threeOmegaRAHEOverlayPreservesManifestOverrides() throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let sweep = ThreeOmegaFieldSweepResult(
            temperatureK: 100, device: "0deg",
            sampleMetadata: ["device": "0deg"], sampleID: "sample-a",
            sourceFilePath: "/tmp/sample-a.csv",
            hField: [-1000, 0, 1000], r1omega: [-1, 0, 1], r3omega: [-2, 0, 2],
            iRms: 1e-3, rahe1omega: 1.0, rahe1omegaWA: 1.0,
            hc1omega: 0.0, hc3omega: 0.0, v3omegaWindow: 2e-5, v3omegaFit: 2e-5
        )
        store.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: [sweep], rtResult: nil, device: "0deg",
            deviceMode: "single", devices: ["0deg"], iRmsValues: [100: 1e-3], warnings: []
        )

        store.tabs.tabStates[.rahe1omegaVsT] = TabRenderState(
            titleOverride: "My RAHE1 Title",
            xLabelOverride: "RAHE1 X",
            yLabelOverride: "RAHE1 Y"
        )
        store.tabs.tabStates[.rahe3omegaVsT] = TabRenderState(
            titleOverride: "My RAHE3 Title",
            xLabelOverride: "RAHE3 X",
            yLabelOverride: "RAHE3 Y"
        )

        let groups: [(label: String, sweeps: [ThreeOmegaFieldSweepResult], sourceFiles: [String])] = [
            (label: "group-a", sweeps: [sweep], sourceFiles: ["/tmp/sample-a.csv"])
        ]
        store._rebuildOverlayManifestPayloads(groups: groups)

        let rahe1Payload = store.tabs.output(for: .rahe1omegaVsT).manifestPayload
        #expect(rahe1Payload?.title == "My RAHE1 Title")
        #expect(rahe1Payload?.axisMapping.xField == "RAHE1 X")
        #expect(rahe1Payload?.axisMapping.yField == "RAHE1 Y")

        let rahe3Payload = store.tabs.output(for: .rahe3omegaVsT).manifestPayload
        #expect(rahe3Payload?.title == "My RAHE3 Title")
        #expect(rahe3Payload?.axisMapping.xField == "RAHE3 X")
        #expect(rahe3Payload?.axisMapping.yField == "RAHE3 Y")

        // Cross-tab isolation: each RAHE tab has its own distinct overrides
        #expect(rahe1Payload?.title != rahe3Payload?.title)
        #expect(rahe1Payload?.axisMapping.xField != rahe3Payload?.axisMapping.xField)
        #expect(rahe1Payload?.axisMapping.yField != rahe3Payload?.axisMapping.yField)
    }

    @MainActor
    @Test("Editing plot title does not mutate canonical search query/results/running/message")
    func editingPlotTitleDoesNotMutateSearchShellState() {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        let wfs = WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence)
        )
        let hits = [makeSearchHit()]

        wfs.setSearchQueryText("ahe pn31 80k", for: .ahe)
        wfs.restoreSearchState(results: hits, queryText: "ahe pn31 80k", for: .ahe)
        wfs.aheWorkspace.cachedSearchResults = hits
        wfs.aheWorkspace.updatePlotTitle("Edited title")

        #expect(wfs.searchQueryText(for: .ahe) == "ahe pn31 80k")
        #expect(wfs.searchResultsList(for: .ahe) == hits)
        #expect(wfs.isSearchRunning(for: .ahe) == false)
        #expect(wfs.searchMessage(for: .ahe) == "Restored from analysis pack (1 hit(s)).")
    }

    @MainActor
    @Test("Editing legend does not mutate canonical search query/results")
    func editingLegendDoesNotMutateSearchShellState() {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        let wfs = WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence)
        )
        let hits = [makeSearchHit()]

        wfs.setSearchQueryText("ahe pn31", for: .ahe)
        wfs.restoreSearchState(results: hits, queryText: "ahe pn31", for: .ahe)
        wfs.aheWorkspace.cachedSearchResults = hits
        wfs.aheWorkspace.updateLegendPoint(CGPoint(x: 0.2, y: 0.8))

        #expect(wfs.searchQueryText(for: .ahe) == "ahe pn31")
        #expect(wfs.searchResultsList(for: .ahe) == hits)
    }

    @MainActor
    @Test("rerenderForStyleChange does not mutate canonical search query/results/selection")
    func rerenderForStyleChangeDoesNotMutateSearchOrSelection() {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        let wfs = WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence)
        )
        let hit = makeSearchHit(id: "hit-rerender")
        let hits = [hit]

        wfs.setSearchQueryText("ahe rerender", for: .ahe)
        wfs.restoreSearchState(results: hits, queryText: "ahe rerender", for: .ahe)
        wfs.aheWorkspace.cachedSearchResults = hits
        wfs.seedSelection([hit.id], for: .ahe)

        wfs.aheWorkspace.rerenderForStyleChange()

        #expect(wfs.searchQueryText(for: .ahe) == "ahe rerender")
        #expect(wfs.searchResultsList(for: .ahe) == hits)
        #expect(wfs.selectedSearchResultIDs(for: .ahe) == [hit.id])
    }

    @MainActor
    @Test("Selection toggle does not mutate canonical query text")
    func selectionToggleDoesNotMutateQueryText() {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        let wfs = WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence)
        )
        let hit = makeSearchHit(id: "hit-select")
        let hits = [hit]

        wfs.setSearchQueryText("ahe selection invariant", for: .ahe)
        wfs.restoreSearchState(results: hits, queryText: "ahe selection invariant", for: .ahe)
        wfs.aheWorkspace.cachedSearchResults = hits

        wfs.toggleSearchHitSelection(hit.id, for: .ahe)
        #expect(wfs.searchQueryText(for: .ahe) == "ahe selection invariant")
        #expect(wfs.selectedSearchResultIDs(for: .ahe).contains(hit.id))
    }
}
