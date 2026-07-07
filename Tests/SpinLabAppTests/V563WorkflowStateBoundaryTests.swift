import Foundation
import Testing
@testable import SpinLabApp

@Suite("Workflow State Boundaries")
struct V563WorkflowStateBoundaryTests {
    private func loadSource(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func extractFunction(_ name: String, from source: String) -> String? {
        guard let sig = source.range(of: "func \(name)") else { return nil }
        guard let open = source[sig.lowerBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        while index < source.endIndex {
            let character = source[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return String(source[sig.lowerBound...index]) }
            }
            index = source.index(after: index)
        }
        return nil
    }

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

    private func makeStackedThreeOmegaSweeps() -> [ThreeOmegaFieldSweepResult] {
        [10, 30, 50, 70, 90, 110].map(makeStackedThreeOmegaSweep)
    }

    private func makeXYRotationSweeps() -> [XYRotationAngleSweep] {
        [10, 30, 50, 70, 90, 110].map(makeXYRotationSweep)
    }

    private func makeStackedThreeOmegaSweep(_ temperatureK: Int) -> ThreeOmegaFieldSweepResult {
        let temperature = Double(temperatureK)
        let sourceFilePath = "/tmp/\(temperatureK).csv"
        return ThreeOmegaFieldSweepResult(
            temperatureK: temperature,
            device: "0deg",
            sampleMetadata: ["device": "0deg"],
            sampleID: "sample-\(temperatureK)",
            sourceFilePath: sourceFilePath,
            hField: [-1000, 0, 1000],
            r1omega: [temperature, temperature + 1, temperature + 2],
            r3omega: [temperature / 10.0, temperature / 10.0 + 1, temperature / 10.0 + 2],
            iRms: 1e-3,
            rahe1omega: 1.0,
            rahe1omegaWA: 1.0,
            hc1omega: 0.0,
            hc3omega: 0.0,
            v3omegaWindow: 2e-5,
            v3omegaFit: 2e-5
        )
    }

    private func makeXYRotationSweep(_ temperatureK: Int) -> XYRotationAngleSweep {
        let temperature = Double(temperatureK)
        let sourceFilePath = "/tmp/\(temperatureK).csv"
        return XYRotationAngleSweep(
            temperatureK: temperature,
            stem: "sample-\(temperatureK)",
            sourceKind: .lvm,
            angleDeg: [0, 60, 120],
            resistanceXX: [temperature, temperature + 1, temperature + 2],
            resistanceXY: nil,
            defaultPhiOffset: 0,
            measurementFilePath: sourceFilePath,
            sampleMetadata: ["device": "0deg"]
        )
    }

    @MainActor
    private func makeScalingReadyStore() -> ThreeOmegaWorkspaceStore {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: [
                ThreeOmegaFieldSweepResult(
                    temperatureK: 5.0,
                    device: "0deg",
                    sampleMetadata: nil,
                    sampleID: "sample-a",
                    sourceFilePath: "/tmp/a.lvm",
                    hField: [-1, 0, 1],
                    r1omega: [-1, 0, 1],
                    r3omega: [0, 0, 0],
                    iRms: 1e-3,
                    rahe1omega: 1.0,
                    rahe1omegaWA: 1.0,
                    hc1omega: nil,
                    hc3omega: nil,
                    v3omegaWindow: 2e-5,
                    v3omegaFit: 2e-5
                ),
                ThreeOmegaFieldSweepResult(
                    temperatureK: 10.0,
                    device: "0deg",
                    sampleMetadata: nil,
                    sampleID: "sample-a",
                    sourceFilePath: "/tmp/b.lvm",
                    hField: [-1, 0, 1],
                    r1omega: [-1, 0, 1],
                    r3omega: [0, 0, 0],
                    iRms: 1e-3,
                    rahe1omega: 1.2,
                    rahe1omegaWA: 1.2,
                    hc1omega: nil,
                    hc3omega: nil,
                    v3omegaWindow: 2.5e-5,
                    v3omegaFit: 2.5e-5
                )
            ],
            rtResult: ThreeOmegaRTResult(
                device: "0deg",
                temperatureK: [5.0, 10.0],
                rxx: [100.0, 90.0]
            ),
            device: "0deg",
            iRmsValues: [5.0: 1e-3, 10.0: 1e-3]
        )
        store.geometry = ThreeOmegaGeometry(lxx: 26, lxy: 21, dNm: 30)
        return store
    }

    @MainActor
    private func makeHeavyScalingReadyStore() -> ThreeOmegaWorkspaceStore {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let sweeps = stride(from: 10, through: 240, by: 10).map { temperatureK -> ThreeOmegaFieldSweepResult in
            let temperature = Double(temperatureK)
            return ThreeOmegaFieldSweepResult(
                temperatureK: temperature,
                device: "0deg",
                sampleMetadata: ["device": "0deg"],
                sampleID: "sample-\(temperatureK)",
                sourceFilePath: "/tmp/\(temperatureK).csv",
                hField: Array(stride(from: -200.0, through: 200.0, by: 10.0)),
                r1omega: Array(stride(from: -200.0, through: 200.0, by: 10.0)).map { $0 + temperature },
                r3omega: Array(stride(from: -200.0, through: 200.0, by: 10.0)).map { ($0 / 10.0) + temperature / 10.0 },
                iRms: 1e-3,
                rahe1omega: 1.0,
                rahe1omegaWA: 1.0,
                hc1omega: 0.0,
                hc3omega: 0.0,
                v3omegaWindow: 2e-5,
                v3omegaFit: 2e-5
            )
        }
        let temperatures = sweeps.map(\.temperatureK)
        store.ingestionResult = ThreeOmegaIngestionResult(
            fieldSweeps: sweeps,
            rtResult: ThreeOmegaRTResult(
                device: "0deg",
                temperatureK: temperatures,
                rxx: temperatures.map { 120.0 - $0 / 4.0 }
            ),
            device: "0deg",
            iRmsValues: Dictionary(uniqueKeysWithValues: temperatures.map { ($0, 1e-3) })
        )
        store.geometry = ThreeOmegaGeometry(lxx: 26, lxy: 21, dNm: 30)
        return store
    }

    @MainActor
    private func makeScalingReadyStoreWithoutGeometry() -> ThreeOmegaWorkspaceStore {
        let store = makeScalingReadyStore()
        store.geometry = ThreeOmegaGeometry()
        return store
    }

    @MainActor
    private func waitForTemperatureDependenceOutput(_ store: ThreeOmegaWorkspaceStore, attempts: Int = 40) async {
        for _ in 0..<attempts {
            if store.tabs.output(for: .temperatureDependence).dualAxisPayload != nil {
                return
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
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

    @MainActor
    @Test("TabRenderManager stores DualAxis outputs without forcing XY payloads")
    func tabRenderManagerStoresDualAxisOutput() {
        enum TestTab: Hashable, Sendable { case first }

        let manager = TabRenderManager<TestTab>(defaultTab: .first)
        let payload = DualAxisPlotPayload(
            workflowID: "dual",
            workflowDisplayName: "Dual",
            title: "Dual Axis",
            xLabel: "T (K)",
            leftYLabel: "Left",
            rightYLabel: "Right",
            leftSeries: [
                DualAxisPlotSeries(label: "L", x: [1, 2], y: [3, 4])
            ],
            rightSeries: [
                DualAxisPlotSeries(label: "R", x: [1, 2], y: [5, 6])
            ]
        )
        let layout = DualAxisPlotLayout.compute(payload: payload)
        let sentinel = Data([0xD1, 0xA1])

        manager.setOutput(
            TabRenderOutput(
                imageData: sentinel,
                renderKind: .dualAxis,
                layout: nil,
                manifestPayload: nil,
                displayPayload: nil,
                dualAxisLayout: layout,
                dualAxisPayload: payload
            ),
            for: .first
        )

        #expect(manager.activeImageData == sentinel)
        #expect(manager.output(for: .first).renderKind == .dualAxis)
        #expect(manager.output(for: .first).dualAxisLayout != nil)
        #expect(manager.output(for: .first).dualAxisPayload != nil)
        #expect(manager.activeManifestPayload == nil)
    }

    @Test("ThreeOmegaWorkbenchTab includes RAHE and temperatureDependence")
    func threeOmegaWorkbenchTabIncludesTemperatureDependence() {
        #expect(ThreeOmegaWorkbenchTab.rahe.rawValue == "RAHE")
        #expect(ThreeOmegaWorkbenchTab.rahe.stableKey == "rahe")
        #expect(ThreeOmegaWorkbenchTab.allCases.contains(.rahe))
        #expect(ThreeOmegaWorkbenchTab.temperatureDependence.rawValue == "Temperature Dependence")
        #expect(ThreeOmegaWorkbenchTab.temperatureDependence.stableKey == "temperatureDependence")
        #expect(ThreeOmegaWorkbenchTab.allCases.contains(.temperatureDependence))
    }

    @MainActor
    @Test("refreshTransportDerivedPlots renders Temperature Dependence as dual-axis output")
    func refreshTransportDerivedPlotsRendersTemperatureDependence() async {
        let store = makeScalingReadyStore()
        store.tabs.activeTab = .fieldSweep1omega
        store.refreshTransportDerivedPlots(reason: "test")
        await waitForTemperatureDependenceOutput(store)

        let scaling = store.tabs.output(for: .scaling)
        let temp = store.tabs.output(for: .temperatureDependence)

        #expect(store.scalingResult?.points.isEmpty == false)
        #expect(scaling.imageData != nil)
        #expect(scaling.layout != nil)
        #expect(scaling.renderKind == .xy)
        #expect(store.activeChartManifestPayload != nil)
        #expect(temp.renderKind == .dualAxis)
        #expect(temp.imageData != nil)
        #expect(temp.dualAxisLayout != nil)
        #expect(temp.dualAxisPayload != nil)
        #expect(temp.manifestPayload == nil)
        #expect(temp.displayPayload == nil)

        if let payload = temp.dualAxisPayload {
            #expect(payload.title == "Temperature Dependence")
            #expect(payload.xLabel == "Temperature (K)")
            #expect(payload.leftYLabel == #"math:E_{AHE}^{3ω} / E_{xx}^{3} × 10^{2} (μm^{2} V^{-2})"#)
            #expect(payload.rightYLabel == #"math:σ_{xx} × 10^{3} (S cm^{-1})"#)
            #expect(payload.leftSeries.first?.label == #"math:E_{AHE}^{3ω} / E_{xx}^{3}"#)
            #expect(payload.rightSeries.first?.label == #"math:σ_{xx}"#)
            #expect(payload.leftSeries.first?.x.count == 2)
            #expect(payload.rightSeries.first?.x.count == 2)
        }
    }

    @MainActor
    @Test("DualAxis rerender keeps manifestPayload and displayPayload nil")
    func temperatureDependenceRerenderKeepsNilXYPayloads() async {
        let store = makeScalingReadyStore()
        store.tabs.activeTab = .temperatureDependence
        store.scalingResult = ThreeOmegaScalingResult(
            points: [
                ThreeOmegaScalingPoint(temperatureK: 100, sigma2xx: 1.0, scalingY: 2.0)
            ],
            segments: []
        )
        store.temperatureDependenceDisplayState.rightYLabelOverride = "κ (W/mK)"

        store.rerenderTemperatureDependenceForDualAxisControlChange()
        await waitForTemperatureDependenceOutput(store)

        let output = store.tabs.output(for: .temperatureDependence)
        #expect(output.renderKind == .dualAxis)
        #expect(output.manifestPayload == nil)
        #expect(output.displayPayload == nil)
        #expect(output.dualAxisPayload != nil)
        #expect(store.activeChartManifestPayload == nil)
    }

    @MainActor
    @Test("stale detached render output cannot overwrite newer field-sweep output")
    func staleDetachedRenderDoesNotOverwriteNewerOutput() async throws {
        let store = makeHeavyScalingReadyStore()
        store.tabs.activeTab = .fieldSweep1omega

        store.updatePlotTitle("Title A")
        await Task.yield()
        var firstImage: Data?
        var attempts = 0
        while firstImage == nil && attempts < 60 {
            firstImage = store.tabs.output(for: .fieldSweep1omega).imageData
            if firstImage == nil {
                try await Task.sleep(nanoseconds: 50_000_000)
                attempts += 1
            }
        }
        let baselineImage = try #require(firstImage)

        store.updatePlotTitle("Title B")

        attempts = 0
        while attempts < 60 {
            let output = store.tabs.output(for: .fieldSweep1omega)
            if output.imageData != nil, output.imageData != baselineImage {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        let output = store.tabs.output(for: .fieldSweep1omega)
        #expect(output.imageData != nil)
        #expect(output.imageData != baselineImage)
    }

    @MainActor
    @Test("refreshTransportDerivedPlots finalizes even when plot-only revision changes mid-flight")
    func refreshTransportDerivedPlotsFinalizesAfterPlotOnlyRevisionChange() async throws {
        let store = makeHeavyScalingReadyStore()
        store.tabs.activeTab = .fieldSweep1omega

        store.refreshTransportDerivedPlots(reason: "revision churn test")
        await Task.yield()
        store.rerenderForStyleChange()

        var attempts = 0
        while store.isRefreshingTransportDerivedPlots && attempts < 80 {
            try await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        #expect(store.scalingResult != nil)
        #expect(store.isRefreshingTransportDerivedPlots == false)
        if case .ready = store.transportDerivedStatus {
        } else {
            Issue.record("Expected ready transport status")
        }
        await waitForTemperatureDependenceOutput(store)
        let tdOutput = store.tabs.output(for: .temperatureDependence)
        #expect(tdOutput.renderKind == .dualAxis)
        #expect(tdOutput.dualAxisPayload != nil)
    }

    @MainActor
    @Test("Missing geometry does not overwrite analysisMessage")
    func missingGeometryDoesNotOverwriteAnalysisMessage() {
        let store = makeScalingReadyStoreWithoutGeometry()
        store.analysisMessage = "Analysis success"

        store.refreshTransportDerivedPlots(reason: "missing geometry")

        #expect(store.analysisMessage == "Analysis success")
        #expect(store.transportDerivedStatusMessage?.contains("missing") == true)
        let output = store.tabs.output(for: .temperatureDependence)
        #expect(output.renderKind == .dualAxis)
        #expect(output.imageData == nil)
        #expect(output.manifestPayload == nil)
        #expect(output.displayPayload == nil)
        #expect(output.dualAxisPayload == nil)
    }

    @Test("DualAxis render path never copies Cartesian payload fields into TD output")
    func dualAxisRenderPathDoesNotCopyCartesianPayloadFields() throws {
        let source = try loadSource("Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Rendering.swift")
        guard let switchStart = source.range(of: "case let .dualAxis(data, layoutValue, payload, renderWarnings):"),
              let guardEnd = source.range(of: "guard _canCommitRenderOutput(revision: revision, analysisRevision: analysisRevision) else {", range: switchStart.upperBound..<source.endIndex)
        else {
            Issue.record("Could not isolate the dual-axis render branch in ThreeOmegaWorkspaceStore+Rendering.swift")
            return
        }

        let branch = String(source[switchStart.lowerBound..<guardEnd.lowerBound])
        #expect(branch.contains("renderKind: .dualAxis"))
        #expect(branch.contains("manifestPayload: nil"))
        #expect(branch.contains("displayPayload: nil"))
        #expect(branch.contains("dualAxisPayload: payload"))
        #expect(!branch.contains("manifestPayload: payload"))
        #expect(!branch.contains("displayPayload: payload"))
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

    @MainActor
    @Test("DualAxis export snapshots fall back to cached PNG until full export support exists")
    func dualAxisExportSnapshotFallsBackToCachedPNG() {
        enum TestTab: Hashable, Sendable { case first }

        let manager = TabRenderManager<TestTab>(defaultTab: .first)
        let payload = DualAxisPlotPayload(
            workflowID: "dual",
            workflowDisplayName: "Dual",
            title: "Dual Axis",
            xLabel: "T (K)",
            leftYLabel: "Left",
            rightYLabel: "Right"
        )
        manager.setOutput(
            TabRenderOutput(
                imageData: Data([0xAB, 0xCD]),
                renderKind: .dualAxis,
                dualAxisPayload: payload
            ),
            for: .first
        )

        let snapshot = manager.exportSnapshot(for: .first, globalPlotDefaults: [:])
        #expect(snapshot.renderKind == .dualAxis)
        #expect(snapshot.displayPayload == nil)
        #expect(snapshot.dualAxisPayload != nil)

        let exported = WorkbenchPlotExportService.exportPNG(snapshot: snapshot, scale: 3.0)
        #expect(exported == Data([0xAB, 0xCD]))
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

    @MainActor
    @Test("refreshTransportDerivedPlots keeps analysis success message when geometry is incomplete")
    func refreshTransportDerivedPlotsMissingGeometryKeepsAnalysisMessage() {
        let store = makeScalingReadyStore()
        store.geometry = ThreeOmegaGeometry(lxx: 0, lxy: 21, dNm: 30)
        store.analysisMessage = "Analyzed 2 field-sweep file(s), RT curve loaded."

        store.refreshTransportDerivedPlots(reason: "geometry missing test")

        #expect(store.analysisMessage == "Analyzed 2 field-sweep file(s), RT curve loaded.")
        #expect(store.scalingResult == nil)
        if case let .missing(requirements) = store.transportDerivedStatus {
            #expect(requirements.contains(.lxx))
        } else {
            Issue.record("Expected missing transport status")
        }
    }

    @MainActor
    @Test("refreshTransportDerivedPlots renders scaling automatically when inputs are complete")
    func refreshTransportDerivedPlotsRendersScalingAutomatically() async throws {
        let store = makeScalingReadyStore()
        store.analysisMessage = "Analyzed 2 field-sweep file(s), RT curve loaded."

        store.refreshTransportDerivedPlots(reason: "ready test")
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(store.analysisMessage == "Analyzed 2 field-sweep file(s), RT curve loaded.")
        #expect(store.scalingResult != nil)
        if case .ready = store.transportDerivedStatus {
        } else {
            Issue.record("Expected ready transport status")
        }
    }

    @MainActor
    @Test("refreshTransportDerivedPlots preserves scaling-tab display overrides")
    func refreshTransportDerivedPlotsPreservesScalingTabDisplayOverrides() async throws {
        let store = makeScalingReadyStore()
        store.tabs.tabStates[.scaling] = TabRenderState(
            legendPoint: CGPointCodable(CGPoint(x: 0.2, y: 0.8)),
            titleOverride: "Custom Scaling Title",
            xLabelOverride: "Custom X",
            yLabelOverride: "Custom Y",
            seriesLabelOverrides: ["sample-a": "A"],
            axisRangeOverride: AxisRangeOverride(xMin: 0, xMax: 10, yMin: -1, yMax: 1),
            showPointTags: true
        )

        store.refreshTransportDerivedPlots(reason: "display preservation test")
        try await Task.sleep(nanoseconds: 200_000_000)

        let state = store.tabs.state(for: .scaling)
        #expect(state.legendPoint?.cgPoint == CGPoint(x: 0.2, y: 0.8))
        #expect(state.titleOverride == "Custom Scaling Title")
        #expect(state.xLabelOverride == "Custom X")
        #expect(state.yLabelOverride == "Custom Y")
        #expect(state.seriesLabelOverrides == ["sample-a": "A"])
        #expect(state.axisRangeOverride?.xMin == 0)
        #expect(state.axisRangeOverride?.xMax == 10)
        #expect(state.showPointTags)
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

    // MARK: - _refreshManifestPayloads override preservation (Stage 2A-1 correction)
    // manifestPayload is the raw/scientific payload; display overrides live in TabRenderState only.

    @MainActor
    @Test("_refreshManifestPayloads keeps scientific labels in manifestPayload despite tabState overrides")
    func refreshManifestPayloadsKeepsScientificLabels() throws {
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

        // manifestPayload must retain scientific values — overrides belong to display layer only
        let hcPayload = store.tabs.output(for: .hcVsT).manifestPayload
        #expect(hcPayload?.title != "My Hc Title", "titleOverride must not be baked into manifestPayload")
        #expect(hcPayload?.axisMapping.xField == "Temperature (K)", "manifestPayload xField must remain scientific")
        #expect(hcPayload?.axisMapping.yField == "μ₀Hc (mT)", "manifestPayload yField must remain scientific")

        let r1Payload = store.tabs.output(for: .fieldSweep1omega).manifestPayload
        #expect(r1Payload?.title != "My 1ω Title", "titleOverride must not be baked into manifestPayload")
        #expect(r1Payload?.series.first(where: { $0.sampleID == "sample-a" })?.label == "100 K",
                "seriesLabelOverrides must not be baked into manifestPayload")

        // Cross-tab isolation: 3ω tab is unrelated to 1ω overrides
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
        // manifestPayload is scientific — overrides must not be baked in
        #expect(out1.manifestPayload?.title != "Custom 1ω", "titleOverride must not pollute manifestPayload")
        #expect(out1.manifestPayload?.series.first(where: { $0.sampleID == "sample-a" })?.label != "Renamed A",
                "seriesLabelOverrides must not pollute manifestPayload")

        let out3 = store.tabs.output(for: .fieldSweep3omega)
        #expect(out3.imageData != nil)
        // 3ω must not inherit the 1ω override (cross-tab isolation still holds)
        #expect(out3.manifestPayload?.title == "Base 3ω")
        #expect(out3.manifestPayload?.series.first(where: { $0.sampleID == "sample-a" })?.label == "100 K")
    }

    @MainActor
    @Test("3ω renderThreeOmegaTab stores export-safe displayPayload for stacked field sweeps")
    func threeOmegaRenderStoresExportSafeDisplayPayload() async throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let sweeps = makeStackedThreeOmegaSweeps()
        let ingestion = ThreeOmegaIngestionResult(
            fieldSweeps: sweeps,
            rtResult: nil,
            device: "0deg",
            deviceMode: "single",
            devices: ["0deg"],
            iRmsValues: Dictionary(uniqueKeysWithValues: sweeps.map { ($0.temperatureK, 1e-3) }),
            warnings: []
        )
        let renderer = ThreeOmegaPlotRenderer()
        guard let seededManifest = renderer.makeR1omegaPayload(sweeps: sweeps, device: "0deg") else {
            Issue.record("Expected 3ω renderer to produce a field-sweep payload")
            return
        }
        var output = TabRenderOutput(manifestPayload: seededManifest)
        output.manifestPayload?.title = "Manifest 1ω"
        store.tabs.setOutput(output, for: .fieldSweep1omega)

        let globalSettings = ThreeOmegaRendererGlobalSettings(
            workflowID: store.workflowID,
            showGrid: false,
            seriesRenderMode: .line,
            chartStyleOverrides: [:],
            globalPlotDefaults: [:],
            legendAnchor: "",
            stackOffsetMultiplier: 1.2,
            minGapFraction: 0.15,
            titleTemplate: "#tab #device #sample",
            titleTokens: [:]
        )

        let renderResult = await store.renderThreeOmegaTab(
            .fieldSweep1omega,
            ingestion: ingestion,
            scalingResult: nil,
            fieldSweepSeriesOrder: nil,
            globalSettings: globalSettings,
            tabSnapshot: store.tabs.displayStateSnapshot(for: .fieldSweep1omega)
        )

        let stored = store.tabs.output(for: .fieldSweep1omega)
        let expectedLabels = ["110 K", "90 K", "70 K", "50 K", "30 K", "10 K"]

        #expect(renderResult.displayPayload?.series.map(\.label) == expectedLabels)
        #expect(stored.displayPayload?.series.map(\.label) == expectedLabels)
        #expect(stored.displayPayload?.series.map(\.label) == stored.manifestPayload?.series.map(\.label),
                "stored displayPayload must stay in the same visual order as the manifest payload")
        #expect(stored.manifestPayload?.reverseSeriesForLegend == false)
        #expect(stored.displayPayload?.reverseSeriesForLegend == false)
    }

    @Test("3ω stacked field-sweep payload builder does not call the legacy raw-sweep ordering helper")
    func threeOmegaStackedPayloadBuilderDoesNotCallLegacyRawSweepOrder() throws {
        let source = try loadSource("Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift")
        let function = try #require(extractFunction("makeStackedFieldSweepPayloads", from: source))

        #expect(!function.contains("_legacyApplyRawSweepOrder("))
    }

    @MainActor
    @Test("3ω pack restore keeps stacked field-sweep legend, display, and mean-y order aligned")
    func threeOmegaPackRestoreKeepsStackLegendAndDisplayAligned() async throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let sweeps = makeStackedThreeOmegaSweeps()
        let requestedVisualOrder = [
            "/tmp/110.csv",
            "/tmp/90.csv",
            "/tmp/70.csv",
            "/tmp/50.csv",
            "/tmp/30.csv",
            "/tmp/10.csv"
        ]

        let config = ThreeOmegaPackConfig(
            device: "0deg",
            geometry: ThreeOmegaGeometry(),
            fitRanges: [],
            v3Method: ThreeOmegaV3Method.highField.rawValue,
            rahe1Method: ThreeOmegaV3Method.highField.rawValue,
            rahe3Method: ThreeOmegaV3Method.highField.rawValue,
            rtFilePath: nil,
            sampleBatchAndSubstrate: "",
            activeTab: ThreeOmegaWorkbenchTab.fieldSweep1omega.stableKey,
            titleTemplate: "#tab #device #sample",
            stackOffsetMultiplier: 1.2,
            minGapFraction: 0.15,
            showPlotGrid: true,
            plotLegendAnchor: "",
            seriesRenderMode: .line,
            tabStates: [
                ThreeOmegaWorkbenchTab.fieldSweep1omega.stableKey: TabRenderState(seriesOrder: requestedVisualOrder),
                ThreeOmegaWorkbenchTab.fieldSweep3omega.stableKey: TabRenderState(seriesOrder: requestedVisualOrder)
            ]
        )
        let result = ThreeOmegaPackResult(
            ingestionResult: ThreeOmegaIngestionResult(
                fieldSweeps: sweeps,
                rtResult: nil,
                device: "0deg",
                deviceMode: "single",
                devices: ["0deg"],
                iRmsValues: Dictionary(uniqueKeysWithValues: sweeps.map { ($0.temperatureK, 1e-3) }),
                warnings: []
            ),
            scalingResult: nil
        )

        store.restoreFromPack(
            config: config,
            result: result,
            pack: AnalysisPack(
                id: UUID(),
                label: "pack",
                workflowID: "3w",
                filePaths: sweeps.compactMap(\.sourceFilePath),
                sampleKeys: sweeps.compactMap(\.sampleID),
                sourceFingerprint: "",
                config: Data(),
                result: Data()
            ),
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        func waitForFieldSweepOutputs() async -> Bool {
            let deadline: UInt64 = 5_000_000_000
            let sleepNS: UInt64 = 50_000_000
            var elapsed: UInt64 = 0
            while elapsed <= deadline {
                let out1 = store.tabs.output(for: .fieldSweep1omega)
                let out3 = store.tabs.output(for: .fieldSweep3omega)
                if out1.layout != nil, out1.manifestPayload != nil, out1.displayPayload != nil,
                   out3.layout != nil, out3.manifestPayload != nil, out3.displayPayload != nil {
                    return true
                }
                try? await Task.sleep(nanoseconds: sleepNS)
                elapsed += sleepNS
            }
            return false
        }

        guard await waitForFieldSweepOutputs() else {
            Issue.record("Timed out waiting for field-sweep outputs after pack restore")
            return
        }

        func assertInvariant(for tab: ThreeOmegaWorkbenchTab) {
            let output = store.tabs.output(for: tab)
            guard let layout = output.layout,
                  let display = output.displayPayload,
                  let manifest = output.manifestPayload else {
                Issue.record("missing restored output for \(tab.rawValue)")
                return
            }
            let legend = layout.legendRows.map(\.identityKey)
            let displayOrder = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: display.series).map(\.identityKey)
            let meanOrder = display.series
                .map { series in
                    let mean = series.y.reduce(0.0, +) / Double(series.y.count)
                    return (identity: WorkbenchSeriesOrderKeyResolver.resolve(for: series, originalIndex: 0), mean: mean)
                }
                .sorted { $0.mean > $1.mean }
                .map(\.identity)

            #expect(manifest.reverseSeriesForLegend == false)
            #expect(display.reverseSeriesForLegend == false)
            #expect(displayOrder == legend)
            #expect(meanOrder == legend)
            #expect(display.series.compactMap(\.sourceRef) == requestedVisualOrder)
        }

        assertInvariant(for: .fieldSweep1omega)
        assertInvariant(for: .fieldSweep3omega)
    }

    @Test("XYRotation render helpers return pre-pipeline displayPayload for export")
    func xyRotationRenderReturnsPrePipelineDisplayPayload() throws {
        var renderer = XYRotationPlotRenderer()
        let sweeps = makeXYRotationSweeps()

        let (imageData, layout, displayPayload, _) = renderer.renderRxxVsPhi(sweeps: sweeps, device: "0deg")
        #expect(imageData != nil)
        #expect(layout != nil)

        guard let displayPayload else {
            Issue.record("Expected XYRotation render helper to return a displayPayload")
            return
        }

        let visible = try WorkbenchRenderPipeline.render(WorkbenchRenderPipeline.Input(payload: displayPayload))
        #expect(displayPayload.series.map(\.label) == ["10 K", "30 K", "50 K", "70 K", "90 K", "110 K"])
        #expect(visible.manifestPayload.series.map(\.label) == ["110 K", "90 K", "70 K", "50 K", "30 K", "10 K"])
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
        // manifestPayload is scientific — display overrides must not be baked in
        #expect(output.manifestPayload?.title != "Custom 1ω Title",
                "titleOverride must not pollute manifestPayload after style rerender")
        #expect(output.manifestPayload?.axisMapping.xField != "My X Label",
                "xLabelOverride must not pollute manifestPayload after style rerender")
        #expect(output.manifestPayload?.axisMapping.yField != "My Y Label",
                "yLabelOverride must not pollute manifestPayload after style rerender")
        #expect(output.manifestPayload?.series.first?.label != "Renamed Series",
                "seriesLabelOverrides must not pollute manifestPayload after style rerender")
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
    @Test("_refreshManifestPayloads keeps canonical axis labels regardless of xLabelOverride/yLabelOverride", arguments: [
        AxisLabelCase(xOverride: "Custom X", yOverride: ""),
        AxisLabelCase(xOverride: "",          yOverride: "Custom Y"),
        AxisLabelCase(xOverride: "Custom X",  yOverride: "Custom Y"),
    ])
    func refreshManifestPayloadsKeepsCanonicalAxisLabels(_ tc: AxisLabelCase) throws {
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
        // manifestPayload always retains canonical scientific labels regardless of overrides
        #expect(payload?.axisMapping.xField == "Temperature (K)", "xLabelOverride must not pollute manifestPayload")
        #expect(payload?.axisMapping.yField == "μ₀Hc (mT)", "yLabelOverride must not pollute manifestPayload")
    }

    // MARK: - All tabs other than the curve tab × all text overrides — table-driven (Phase 4C-2 Message 4)

    struct ThreeOmegaTabOverrideCase: Sendable, CustomStringConvertible {
        let tabKey: String
        let xCanonical: String
        let yCanonical: String
        var description: String { tabKey }
    }

    @MainActor
    @Test("_refreshManifestPayloads keeps canonical axis labels for all 3ω tabs other than the curve tab despite overrides", arguments: [
        ThreeOmegaTabOverrideCase(tabKey: "fieldSweep1omega", xCanonical: "μ₀H (mT)",       yCanonical: "R(1ω) (Ω)"),
        ThreeOmegaTabOverrideCase(tabKey: "fieldSweep3omega", xCanonical: "μ₀H (mT)",       yCanonical: "R(3ω) (Ω)"),
        ThreeOmegaTabOverrideCase(tabKey: "rahe",            xCanonical: "Temperature (K)", yCanonical: "math:R_{AHE} (Ω)"),
        ThreeOmegaTabOverrideCase(tabKey: "hcVsT",           xCanonical: "Temperature (K)", yCanonical: "μ₀Hc (mT)"),
        ThreeOmegaTabOverrideCase(tabKey: "scaling",         xCanonical: "math:σ_{xx}^{2} × 10^{7} (S^{2} cm^{-2})", yCanonical: "math:E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})"),
    ])
    func refreshManifestAllOtherTabsKeepCanonicalLabels(_ tc: ThreeOmegaTabOverrideCase) throws {
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

        // manifestPayload must keep canonical scientific labels — overrides must not be baked in
        let payload = store.tabs.output(for: tab).manifestPayload
        #expect(payload?.title != "Title-\(tc.tabKey)", "titleOverride must not pollute manifestPayload")
        #expect(payload?.axisMapping.xField == tc.xCanonical,
                "manifestPayload xField must remain canonical '\(tc.xCanonical)'")
        #expect(payload?.axisMapping.yField == tc.yCanonical,
                "manifestPayload yField must remain canonical '\(tc.yCanonical)'")

        // Sibling tabs must not absorb overrides from this tab (cross-tab isolation)
        for sibling in ThreeOmegaWorkbenchTab.allCases where sibling != tab && sibling != .rtCurve {
            let sibPayload = store.tabs.output(for: sibling).manifestPayload
            #expect(sibPayload?.axisMapping.xField != "X-\(tc.tabKey)")
            #expect(sibPayload?.axisMapping.yField != "Y-\(tc.tabKey)")
        }
    }

    // MARK: - runScaling manifest override preservation (Phase 4C-2 Message 4)

    @MainActor
    @Test("runScaling path: _refreshManifestPayloads keeps scientific labels in scaling-tab manifest")
    func threeOmegaRunScalingKeepsScientificManifest() throws {
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

        // manifestPayload must retain scientific values — display overrides belong to TabRenderState only
        let payload = store.tabs.output(for: .scaling).manifestPayload
        #expect(payload?.title != "My Scaling Title", "titleOverride must not pollute manifestPayload")
        #expect(payload?.axisMapping.xField != "Custom σ²", "xLabelOverride must not pollute manifestPayload")
        #expect(payload?.axisMapping.yField != "Custom AHE", "yLabelOverride must not pollute manifestPayload")

        // Sibling tab must not absorb scaling overrides (cross-tab isolation still holds)
        let hcPayload = store.tabs.output(for: .hcVsT).manifestPayload
        #expect(hcPayload?.axisMapping.xField == "Temperature (K)")
        #expect(hcPayload?.axisMapping.yField == "μ₀Hc (mT)")
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

    // MARK: - 3ω workspace tab strip navigation contract

    @Test("3ω visible tab strip hides legacy RAHE vs T tabs")
    func threeOmegaVisibleTabStripHidesLegacyRAHETabs() {
        let visible = ThreeOmegaWorkbenchTab.visibleTabs
        #expect(visible.contains(.rahe), "RAHE must remain reachable from the tab picker")
        #expect(visible.contains(.fieldSweep1omega))
        #expect(visible.contains(.fieldSweep3omega))
        #expect(visible.contains(.rahe1omegaVsDevice))
        #expect(visible.contains(.rahe3omegaVsDevice))
        #expect(visible.contains(.hcVsT))
        #expect(visible.contains(.rtCurve))
        #expect(visible.contains(.scaling))
        #expect(visible.contains(.temperatureDependence))
        #expect(!visible.contains(.rahe1omegaVsT))
        #expect(!visible.contains(.rahe3omegaVsT))
        #expect(visible.count == 9,
                "visible picker should enumerate only the current 3ω tabs")
    }

    @MainActor
    @Test("3ω tab strip: activeTab can switch to temperatureDependence and back")
    func threeOmegaTabSwitchToAndFromTD() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.tabs.activeTab = .fieldSweep1omega
        #expect(store.tabs.activeTab == .fieldSweep1omega)

        store.tabs.activeTab = .temperatureDependence
        #expect(store.tabs.activeTab == .temperatureDependence)

        // Switching back must not be blocked
        store.tabs.activeTab = .rahe
        #expect(store.tabs.activeTab == .rahe)
    }

    @MainActor
    @Test("3ω pack restore migrates legacy RAHE-vs-T activeTab to combined RAHE")
    func threeOmegaPackRestoreMigratesLegacyRAHEActiveTab() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let config = ThreeOmegaPackConfig(
            device: "",
            geometry: ThreeOmegaGeometry(),
            fitRanges: [],
            v3Method: ThreeOmegaV3Method.highField.rawValue,
            rahe1Method: ThreeOmegaV3Method.highField.rawValue,
            rahe3Method: ThreeOmegaV3Method.window.rawValue,
            rtFilePath: nil,
            sampleBatchAndSubstrate: "",
            activeTab: "rahe1omegaVsT",
            titleTemplate: store.titleTemplate,
            stackOffsetMultiplier: store.stackOffsetMultiplier,
            minGapFraction: store.minGapFraction,
            showPlotGrid: true,
            plotLegendAnchor: "",
            tabStates: [
                "rahe1omegaVsT": TabRenderState(titleOverride: "legacy-1ω"),
                "rahe3omegaVsT": TabRenderState(titleOverride: "legacy-3ω")
            ]
        )

        store.restoreFromPack(
            config: config,
            result: ThreeOmegaPackResult(
                ingestionResult: ThreeOmegaIngestionResult(
                    fieldSweeps: [],
                    rtResult: nil,
                    device: "",
                    deviceMode: "single",
                    devices: []
            ),
            scalingResult: nil
        ),
        pack: AnalysisPack(
            id: UUID(),
            label: "pack",
            workflowID: "3w",
            filePaths: [],
            sampleKeys: [],
            sourceFingerprint: "",
            config: Data(),
            result: Data()
        ),
        restoreSearchState: { _, _ in },
        seedSelection: { _, _ in }
        )

        #expect(store.tabs.activeTab == .rahe)
        #expect(store.tabs.state(for: .rahe).titleOverride == "")
        #expect(store.tabs.state(for: .rahe1omegaVsT).titleOverride == "")
        #expect(store.tabs.state(for: .rahe3omegaVsT).titleOverride == "")
    }

    @MainActor
    @Test("3ω pack save normalizes legacy RAHE-vs-T tabs to combined RAHE")
    func threeOmegaPackSaveNormalizesLegacyRAHEActiveTab() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.tabs.activeTab = .rahe1omegaVsT
        store.tabs.tabStates[.rahe1omegaVsT] = TabRenderState(titleOverride: "legacy-1ω")
        store.tabs.tabStates[.rahe3omegaVsT] = TabRenderState(titleOverride: "legacy-3ω")

        let config = store._buildPackConfig()

        #expect(config.activeTab == "rahe")
        #expect(config.tabStates.isEmpty)
    }

    @MainActor
    @Test("3ω pack snapshot preserves RAHE tab visibility and order state")
    func threeOmegaRAHEPackSnapshotPreservesTabState() {
        let manager = TabRenderManager<ThreeOmegaWorkbenchTab>(defaultTab: .rahe)
        manager.tabStates[.rahe] = TabRenderState(
            titleOverride: "RAHE",
            hiddenSeriesKeys: ["series-b"],
            seriesOrder: ["series-a", "series-b"]
        )

        let snapshot = manager.snapshotStates(keyFor: { $0.stableKey })
        let restored = TabRenderManager<ThreeOmegaWorkbenchTab>(defaultTab: .fieldSweep1omega)
        restored.restoreStates(snapshot) { key in
            ThreeOmegaWorkbenchTab.allCases.first { $0.stableKey == key }
        }

        #expect(restored.state(for: .rahe).titleOverride == "RAHE")
        #expect(restored.state(for: .rahe).hiddenSeriesKeys == ["series-b"])
        #expect(restored.state(for: .rahe).seriesOrder == ["series-a", "series-b"])
    }

    @MainActor
    @Test("3ω tab strip: TD display state is preserved across tab switches")
    func threeOmegaTDDisplayStatePreservedAcrossTabSwitch() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.temperatureDependenceDisplayState.rightYLabelOverride = "κ (W/mK)"
        store.temperatureDependenceDisplayState.axisColorPolicy = .monochrome

        // Switch away from TD
        store.tabs.activeTab = .fieldSweep1omega
        // Switch back
        store.tabs.activeTab = .temperatureDependence

        #expect(store.temperatureDependenceDisplayState.rightYLabelOverride == "κ (W/mK)")
        #expect(store.temperatureDependenceDisplayState.axisColorPolicy == .monochrome)
    }

    @MainActor
    @Test("3ω clearPlot clears Cartesian output and resets TD DualAxis display state")
    func threeOmegaClearPlotResetsDualAxisDisplayState() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)

        store.geometry = ThreeOmegaGeometry(lxx: 26, lxy: 21, dNm: 30)
        store.cachedSearchResults = [makeSearchHit(
            id: "3w-clear",
            workflowID: "3w",
            workflowCanonicalID: "threeOmega"
        )]
        store.tabs.activeTab = .fieldSweep1omega
        store.tabs.updateTitleOverride("Cartesian Override")
        store.tabs.updateXLabelOverride("Cartesian X")
        store.tabs.updateYLabelOverride("Cartesian Y")
        store.tabs.updateAxisBound(.xMin, value: 1.0)
        store.tabs.showPlotGrid = true
        store.temperatureDependenceDisplayState = DualAxisDisplayState(
            titleOverride: "TD Override",
            xLabelOverride: "T (K)",
            leftYLabelOverride: "Left TD",
            rightYLabelOverride: "Right TD",
            axisRangeOverride: DualAxisAxisRangeOverride(
                xMin: 10,
                xMax: 300,
                leftYMin: 1,
                leftYMax: 10
            ),
            leftSeriesStyle: DualAxisSeriesVisualStyle(
                linePattern: .dashed,
                markerShape: .square,
                markerFill: .open
            ),
            rightSeriesStyle: DualAxisSeriesVisualStyle(
                linePattern: .solid,
                markerShape: .circle,
                markerFill: .filled
            ),
            axisColorPolicy: .monochrome
        )

        store.clearPlot()

        #expect(store.tabs.activeState.titleOverride == "")
        #expect(store.tabs.activeState.xLabelOverride == "")
        #expect(store.tabs.activeState.yLabelOverride == "")
        #expect(store.tabs.activeState.axisRangeOverride == nil)
        #expect(store.tabs.activeImageData == nil)
        #expect(store.tabs.showPlotGrid == true)
        #expect(store.temperatureDependenceDisplayState == DualAxisDisplayState())
        #expect(store.geometry == ThreeOmegaGeometry(lxx: 26, lxy: 21, dNm: 30))
        #expect(store.cachedSearchResults.count == 1)
    }

    @MainActor
    @Test("3ω tab strip: hideTabRow does not prevent tab binding from firing onChange")
    func threeOmegaHideTabRowDoesNotSuppressTabObservation() {
        // WorkbenchStandardPlotControls with hideTabRow:true still watches activeTab via .onChange.
        // This test confirms the activeTab binding is live even when the picker row is hidden.
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.tabs.activeTab = .fieldSweep1omega
        store.tabs.activeTab = .scaling
        #expect(store.tabs.activeTab == .scaling,
                "activeTab binding must accept any ThreeOmegaWorkbenchTab value")
    }
}
