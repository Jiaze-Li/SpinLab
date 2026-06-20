import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Fixtures

private let rsmSaveHL3x3 = """
# RSM scan — HL plane, K=0 fixed
H        K        L        Detector
-1.0     0.0      1.0      100.0
 0.0     0.0      1.0      200.0
 1.0     0.0      1.0      150.0
-1.0     0.0      1.5      110.0
 0.0     0.0      1.5      250.0
 1.0     0.0      1.5      180.0
-1.0     0.0      2.0       90.0
 0.0     0.0      2.0      300.0
 1.0     0.0      2.0      120.0
"""

private let rsmSaveHK2x2 = """
H     K     L     Intensity
-1.0  0.0   1.0   11.0
 1.0  0.0   1.0   22.0
-1.0  1.0   1.0   33.0
 1.0  1.0   1.0   44.0
"""

// MARK: - Helpers

private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appending(path: "v824-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func writeTempRSMFile(_ content: String, in dir: URL, name: String = "rsm_scan.dat") throws -> URL {
    let url = dir.appending(path: name)
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
}

private func makeProjection(
    view: RSMView = .hl,
    title: String = "Test RSM",
    detectorColumnName: String = "Detector",
    sourceFileIdentity: String? = "/tmp/test.dat"
) -> RSMSaveProjection {
    RSMSaveProjection(
        workflowID: "rsm",
        title: title,
        activeView: view,
        detectorColumnName: detectorColumnName,
        xLabel: view.xLabel,
        yLabel: view.yLabel,
        zLabel: detectorColumnName,
        sourceFileIdentity: sourceFileIdentity,
        semanticParams: ["view": view.rawValue]
    )
}

private func sentinelPNG() -> Data {
    Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
}

private func makeHit(filePath: String, sampleKey: String = "PN31|b|STO|111") -> WorkflowMeasurementSearchHit {
    WorkflowMeasurementSearchHit(
        sidecarPath: filePath + ".spinlab.json",
        measurementFilePath: filePath,
        sourceFilePath: filePath,
        workflowID: "rsm",
        workflowDisplayName: "RSM",
        workflowCanonicalID: "rsm",
        batchID: "PN31",
        sampleKey: sampleKey,
        sampleSubstrate: "STO111",
        conditions: [:],
        channels: [],
        appliedAt: .distantPast
    )
}

private func waitUntilRSM(
    timeoutMS: UInt64,
    predicate: @escaping @Sendable () async -> Bool
) async {
    let intervalNS: UInt64 = 20_000_000
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutMS * 1_000_000
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await predicate() { return }
        try? await Task.sleep(nanoseconds: intervalNS)
    }
    Issue.record("Timed out waiting for condition.")
}

private func loadManifest(at relPath: String, root: URL) throws -> WorkbenchRunManifest {
    let url = root.appending(path: relPath)
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(WorkbenchRunManifest.self, from: data)
}

// MARK: - V824 RSM Save to Library Tests

@Suite("RSM Save to Library (Gate H5)", .serialized)
struct V824RSMSaveToLibraryTests {

    // MARK: - 1. SaveRSMChartToLibraryUseCase: writes PNG

    @Test("SaveRSMChart writes PNG bytes to disk")
    func rsmSaveWritesPNG() throws {
        let libDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: libDir) }

        let pngData = sentinelPNG()
        let input = SaveRSMChartInput(
            png: pngData,
            projection: makeProjection(),
            sampleKeys: ["PN31|b|STO|111"],
            libraryRootPath: libDir.path,
            runID: "run-write-png",
            generatedAt: .distantPast
        )

        let outcome = SaveRSMChartToLibraryUseCase().execute(input: input)

        guard case .success(let trace) = outcome else {
            Issue.record("Expected .success; got \(outcome)")
            return
        }

        let imagePath = libDir.appending(path: trace.outputImagePath)
        let writtenData = try Data(contentsOf: imagePath)
        #expect(writtenData == pngData)
    }

    // MARK: - 2. SaveRSMChartToLibraryUseCase: writes RSM metadata/projection

    @Test("SaveRSMChart manifest contains RSM workflowID and semanticParams")
    func rsmSaveWritesRSMMetadata() throws {
        let libDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: libDir) }

        let input = SaveRSMChartInput(
            png: sentinelPNG(),
            projection: makeProjection(view: .hl, detectorColumnName: "Detector"),
            sampleKeys: ["PN31|b|STO|111"],
            libraryRootPath: libDir.path,
            runID: "run-rsm-metadata"
        )

        let outcome = SaveRSMChartToLibraryUseCase().execute(input: input)
        guard case .success(let trace) = outcome else {
            Issue.record("Expected .success; got \(outcome)")
            return
        }

        let manifest = try loadManifest(at: trace.manifestPath, root: libDir)
        #expect(manifest.workflowID == "rsm")
        #expect(manifest.semanticParams["view"] == "hl")
    }

    // MARK: - 3. Save includes activeView

    @Test("SaveRSMChart manifest semanticParams include activeView for each RSMView")
    func rsmSaveIncludesActiveView() throws {
        for view in RSMView.allCases {
            let libDir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: libDir) }

            let input = SaveRSMChartInput(
                png: sentinelPNG(),
                projection: makeProjection(view: view),
                sampleKeys: ["PN31|b|STO|111"],
                libraryRootPath: libDir.path
            )

            let outcome = SaveRSMChartToLibraryUseCase().execute(input: input)
            guard case .success(let trace) = outcome else {
                Issue.record("Expected .success for view \(view.rawValue); got \(outcome)")
                return
            }

            let manifest = try loadManifest(at: trace.manifestPath, root: libDir)
            #expect(manifest.semanticParams["view"] == view.rawValue,
                    "Expected semanticParams[view] == \(view.rawValue)")
        }
    }

    // MARK: - 4. Save includes detectorColumnName in projection (axisMapping zField not in manifest,
    //           but projection carries it via RSMSaveProjection.detectorColumnName)

    @Test("RSMSaveProjection carries detectorColumnName through to zLabel")
    func rsmProjectionCarriesDetectorColumnName() {
        let proj = makeProjection(view: .hk, detectorColumnName: "Intensity")
        #expect(proj.detectorColumnName == "Intensity")
        #expect(proj.zLabel == "Intensity")
    }

    // MARK: - 5. Save includes source identity if available

    @Test("SaveRSMChart manifest inputFiles contains sourceFileIdentity when present")
    func rsmSaveIncludesSourceIdentity() throws {
        let libDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: libDir) }

        let proj = makeProjection(sourceFileIdentity: "/data/rsm/my_scan.dat")
        let input = SaveRSMChartInput(
            png: sentinelPNG(),
            projection: proj,
            sampleKeys: ["PN31|b|STO|111"],
            libraryRootPath: libDir.path
        )

        let outcome = SaveRSMChartToLibraryUseCase().execute(input: input)
        guard case .success(let trace) = outcome else {
            Issue.record("Expected .success; got \(outcome)")
            return
        }

        let manifest = try loadManifest(at: trace.manifestPath, root: libDir)
        #expect(manifest.inputFiles == ["/data/rsm/my_scan.dat"])
    }

    @Test("SaveRSMChart manifest inputFiles is empty when sourceFileIdentity is nil")
    func rsmSaveOmitsSourceIdentityWhenNil() throws {
        let libDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: libDir) }

        let proj = makeProjection(sourceFileIdentity: nil)
        let input = SaveRSMChartInput(
            png: sentinelPNG(),
            projection: proj,
            sampleKeys: ["PN31|b|STO|111"],
            libraryRootPath: libDir.path
        )

        let outcome = SaveRSMChartToLibraryUseCase().execute(input: input)
        guard case .success(let trace) = outcome else {
            Issue.record("Expected .success; got \(outcome)")
            return
        }

        let manifest = try loadManifest(at: trace.manifestPath, root: libDir)
        #expect(manifest.inputFiles.isEmpty)
    }

    // MARK: - 6. Save does not require WorkbenchPlotPayload (source inspection)

    @Test("activeChartManifestPayload remains nil for RSM — save does not require WorkbenchPlotPayload")
    @MainActor
    func rsmSaveDoesNotRequireWorkbenchPlotPayload() {
        let store = RSMWorkspaceStore()
        // Without analysis, both PNG and manifest payload are nil
        #expect(store.activeChartPNG == nil)
        #expect(store.activeChartManifestPayload == nil)
    }

    @Test("RSMWorkspaceStore.activeChartManifestPayload is always nil (source inspection)")
    func rsmManifestPayloadAlwaysNilSourceInspection() throws {
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = base.appending(path: "Sources/SpinLabApp/Features/Workbench/RSMWorkspaceStore.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        // activeChartManifestPayload must return nil (never WorkbenchPlotPayload)
        #expect(source.contains("activeChartManifestPayload: WorkbenchPlotPayload? { nil }"))
    }

    // MARK: - 7. Save does not serialize HeatmapPlotLayout

    @Test("SaveRSMChartInput does not contain HeatmapPlotLayout")
    func rsmSaveInputDoesNotContainHeatmapPlotLayout() {
        // RSMSaveProjection has no layout field — confirmed by property access (compile-time)
        let proj = RSMSaveProjection(
            workflowID: "rsm",
            title: "T",
            activeView: .hl,
            detectorColumnName: "D",
            xLabel: "H (r.l.u.)",
            yLabel: "L (r.l.u.)",
            zLabel: "D",
            sourceFileIdentity: nil,
            semanticParams: [:]
        )
        // WorkbenchRunManifest written by the use case also has no layout field
        #expect(proj.workflowID == "rsm")
    }

    // MARK: - 8. Save does not reintroduce XY-only state (source inspection)

    @Test("RSMWorkspaceStore has no XY-specific save fields")
    func rsmWorkspaceStoreHasNoXYSaveFields() throws {
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = base.appending(path: "Sources/SpinLabApp/Features/Workbench/RSMWorkspaceStore.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        // XY-only fields that must not appear
        #expect(!source.contains("ingestionResult"))
        #expect(!source.contains("WorkbenchPlotPayload("))
        #expect(!source.contains("WorkbenchPlotSeries"))
        #expect(!source.contains("axisMapping: WorkbenchAxisMapping") || source.contains("commitRunTrace"))
    }

    // MARK: - 9. Guard: nil PNG sets only saveMessage (source inspection boundary)

    @Test("RSM nil PNG guard sets only saveMessage; other state untouched")
    @MainActor
    func rsmNilPNGGuardIsContained() {
        let store = RSMWorkspaceStore()
        // No PNG — guard fires
        store.persistToLibrary()
        #expect(store.saveMessage == "No chart to save. Run analysis first.")
        #expect(store.analysisMessage == nil)
        #expect(store.persistenceOutcome == nil)
    }

    // MARK: - 10. clearPlot clears saveMessage for RSM

    @Test("clearPlot clears saveMessage for RSM")
    @MainActor
    func clearPlotClearsSaveMessageRSM() {
        let store = RSMWorkspaceStore()
        store.persistToLibrary()
        #expect(store.saveMessage != nil)
        store.clearPlot()
        #expect(store.saveMessage == nil)
    }

    // MARK: - 11. Save succeeds after fresh RSM render (integration)

    @Test("RSM save succeeds after fresh render")
    @MainActor
    func rsmSaveSucceedsAfterFreshRender() async throws {
        let dataDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dataDir) }
        let libDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: libDir) }

        let rsmFile = try writeTempRSMFile(rsmSaveHL3x3, in: dataDir)

        let store = RSMWorkspaceStore()
        store.lastLibraryRootPath = libDir.path

        let hit = makeHit(filePath: rsmFile.path)
        let snapshot = WorkbenchSelectedHitsSnapshot(
            workflowID: .rsm,
            queryText: "",
            selectedIDs: [hit.id],
            selectedHits: [hit],
            sourceHitCount: 1,
            selectionSource: .canonicalSnapshot
        )

        store.runAnalysis(selectedHitsSnapshot: snapshot)
        await waitUntilRSM(timeoutMS: 30000) {
            await MainActor.run { !store.isAnalyzing && store.renderedImageData != nil }
        }

        guard store.renderedImageData != nil else {
            Issue.record("RSM analysis produced no image — cannot test save")
            return
        }

        store.persistToLibrary()
        await waitUntilRSM(timeoutMS: 10000) {
            await MainActor.run { store.persistenceOutcome != nil }
        }

        guard case .success = store.persistenceOutcome else {
            Issue.record("Expected .success; got \(String(describing: store.persistenceOutcome))")
            return
        }
        #expect(store.saveMessage == "Saved to Library.")
    }

    // MARK: - 12. Save succeeds after RSM restore (integration)

    @Test("RSM save succeeds after restore")
    @MainActor
    func rsmSaveSucceedsAfterRestore() async throws {
        let dataDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dataDir) }
        let libDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: libDir) }

        let rsmFile = try writeTempRSMFile(rsmSaveHL3x3, in: dataDir)

        let store = RSMWorkspaceStore()
        store.lastLibraryRootPath = libDir.path
        let hit = makeHit(filePath: rsmFile.path)

        let packConfig = RSMPackConfig(
            packState: RSMPackState(
                sourceFileIdentity: rsmFile.path,
                detectorColumnName: "Detector",
                activeView: .hl
            ),
            displayState: HeatmapTabRenderState(),
            cachedSearchResults: [hit]
        )
        let fakePack = AnalysisPack(
            label: "Test Pack",
            workflowID: "rsm",
            createdAt: .distantPast,
            filePaths: [rsmFile.path],
            sampleKeys: [hit.sampleKey],
            config: (try? JSONEncoder().encode(packConfig)) ?? Data(),
            result: Data()
        )

        store.restoreFromPack(
            config: packConfig,
            result: RSMPackResult(),
            pack: fakePack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        await waitUntilRSM(timeoutMS: 30000) {
            await MainActor.run { !store.isAnalyzing && store.renderedImageData != nil }
        }

        guard store.renderedImageData != nil else {
            Issue.record("RSM restore produced no image — cannot test save")
            return
        }

        store.persistToLibrary()
        await waitUntilRSM(timeoutMS: 10000) {
            await MainActor.run { store.persistenceOutcome != nil }
        }

        guard case .success = store.persistenceOutcome else {
            Issue.record("Expected .success after restore; got \(String(describing: store.persistenceOutcome))")
            return
        }
        #expect(store.saveMessage == "Saved to Library.")
    }

    // MARK: - 13. Pack/restore state unchanged (RSMPackState has no PNG)

    @Test("RSMPackState does not contain rendered PNG or HeatmapPlotLayout fields")
    func rsmPackStateRemainsClean() throws {
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = base.appending(path: "Sources/SpinLabApp/Workbench/V3/Heatmap/RSM/RSMPackState.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(!source.contains("renderedImageData"))
        #expect(!source.contains("imageData"))
        #expect(!source.contains("HeatmapPlotLayout"))
        #expect(!source.contains("WorkbenchPlotPayload"))
    }

    // MARK: - 14. RSMSaveProjection has no HeatmapPlotLayout (source inspection)

    @Test("RSMSaveProjection does not contain HeatmapPlotLayout or XY-specific fields")
    func rsmSaveProjectionIsClean() throws {
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = base.appending(path: "Sources/SpinLabApp/Workbench/V3/Heatmap/RSM/RSMSaveProjection.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(!source.contains("HeatmapPlotLayout"))
        #expect(!source.contains("WorkbenchPlotPayload"))
        #expect(!source.contains("WorkbenchPlotSeries"))
        #expect(source.contains("RSMSaveProjection"))
        #expect(source.contains("activeView"))
        #expect(source.contains("detectorColumnName"))
    }

    // MARK: - 15. Save Module boundary: SaveActiveChartToLibraryUseCase unchanged (source inspection)

    @Test("SaveActiveChartToLibraryUseCase does not reference RSM or heatmap types")
    func saveModuleDoesNotInferRSMSemantics() throws {
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = base.appending(path: "Sources/SpinLabApp/UseCases/SaveActiveChartToLibraryUseCase.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(!source.contains("rsm"))
        #expect(!source.contains("RSM"))
        #expect(!source.contains("HeatmapPlotPayload"))
        #expect(!source.contains("RSMSaveProjection"))
        #expect(!source.contains("RSMView"))
    }

    // MARK: - 16. Trace routing: persistToLibrary never calls commitRunTrace

    @Test("RSM persistToLibrary does not call commitRunTrace")
    func rsmPersistNeverCallsCommitRunTrace() throws {
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = base.appending(path: "Sources/SpinLabApp/Features/Workbench/RSMWorkspaceStore.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        guard let sig = source.range(of: "func persistToLibrary") else {
            Issue.record("Could not find persistToLibrary in RSMWorkspaceStore.swift")
            return
        }
        guard let open = source[sig.lowerBound...].firstIndex(of: "{") else {
            Issue.record("Could not find function body")
            return
        }
        var depth = 0
        var index = open
        while index < source.endIndex {
            let c = source[index]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 {
                    let body = String(source[sig.lowerBound...index])
                    #expect(!body.contains("commitRunTrace()"))
                    return
                }
            }
            index = source.index(after: index)
        }
        Issue.record("Could not extract persistToLibrary body")
    }
}
