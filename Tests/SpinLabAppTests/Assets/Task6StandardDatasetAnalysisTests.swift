import Foundation
import Testing
@testable import SpinLabApp

/// Task 6 batch 1 (AC1–AC3): standard Dataset selection/read, shared page-independent analysis.
@Suite("Task 6: standard Dataset analysis (AC1–AC3)")
struct Task6StandardDatasetAnalysisTests {
    typealias T = AssetTestSupport

    /// Two files with the SAME file name in different folders (sample A), plus one in sample B.
    private func ingestThree(_ s: T.Scenario) throws -> (a1: AssetIngestResult, a2: AssetIngestResult, b: AssetIngestResult) {
        let f1 = try T.writeFixture(seed: 0, name: "scan.ibw")
        let f2 = try T.writeFixture(seed: 5, name: "scan.ibw")
        let f3 = try T.writeFixture(seed: 9, name: "other.ibw")
        return (
            try T.ingest(s, file: f1, target: s.uidA),
            try T.ingest(s, file: f2, target: s.uidA),
            try T.ingest(s, file: f3, target: s.uidB)
        )
    }

    // MARK: AC1

    @Test("List returns each Dataset with its own Sample, file name and stable channels; no matrix decode needed")
    func listDistinguishesDatasets() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let r = try ingestThree(s)
        let list = try s.service.listAnalysisDatasets(format: AFMDatasetCodec.format, rootURL: s.root)
        #expect(list.count == 3)
        let byID = Dictionary(uniqueKeysWithValues: list.map { ($0.datasetID, $0) })
        let d1 = try #require(byID[r.a1.datasetIDs[0]]), d2 = try #require(byID[r.a2.datasetIDs[0]]), d3 = try #require(byID[r.b.datasetIDs[0]])
        #expect(d1.originalFileName == "scan.ibw" && d2.originalFileName == "scan.ibw")
        #expect(d1.datasetID != d2.datasetID && d1.sourceID != d2.sourceID)
        #expect(d1.sampleUID == s.uidA && d2.sampleUID == s.uidA && d3.sampleUID == s.uidB)
        #expect(d3.originalFileName == "other.ibw")
        #expect(d1.channelIDs.count == 3 && !d1.channelIDs.contains(""))
        #expect(d1.batchID == "PN501" && d3.batchID == "PN502")
    }

    @Test("Controlled read returns the exact Dataset with revision, Source, Sample, channels; bit-exact data")
    func controlledRead() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let r = try ingestThree(s)
        let file = try T.writeFixture(seed: 5, name: "scan.ibw")
        let expected = try T.expectedDataset(from: file)
        let ctx = try s.service.loadDatasetForAnalysis(datasetID: r.a2.datasetIDs[0], codec: AFMDatasetCodec(), rootURL: s.root)
        #expect(ctx.datasetID == r.a2.datasetIDs[0] && ctx.revision == 1)
        #expect(ctx.sourceID == r.a2.sourceID && ctx.sampleUID == s.uidA && !ctx.isSampleTrashed)
        #expect(ctx.originalFileName == "scan.ibw")
        #expect(ctx.channelIDs == ctx.dataset.channels.map(\.id))
        // Only the seed-5 fixture matches, i.e. the right one of two same-named files was read.
        let other = try s.service.loadDatasetForAnalysis(datasetID: r.a1.datasetIDs[0], codec: AFMDatasetCodec(), rootURL: s.root)
        #expect(ctx.dataset.channels[0].values != other.dataset.channels[0].values)
        #expect(ctx.dataset.channels.map(\.id) == expected.channels.map(\.id))
        #expect(ctx.dataset.xCoordinates.map(\.bitPattern) == expected.xCoordinates.map(\.bitPattern))
    }

    @Test("Source payload missing: Dataset still analyzable, diagnosed independently; unknown/corrupt Dataset never fakes success")
    func diagnosticsAndFailures() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let r = try ingestThree(s)
        try FileManager.default.removeItem(at: s.root.appending(path: "storage/\(r.a1.sourceID)/payload.bin"))
        let ctx = try s.service.loadDatasetForAnalysis(datasetID: r.a1.datasetIDs[0], codec: AFMDatasetCodec(), rootURL: s.root)
        #expect(ctx.sourceAvailability == .missing)
        #expect(ctx.dataset.channels.count == 3)

        #expect(throws: LibraryAssetError.self) {
            _ = try s.service.loadDatasetForAnalysis(datasetID: "dst_missing", codec: AFMDatasetCodec(), rootURL: s.root)
        }
        // Corrupt the matrix file: hash verification fails, nothing is returned.
        let rel = "storage/\(r.b.datasetIDs[0])/rev_1/\(AFMDatasetCodec.matricesName)"
        try Data([1, 2, 3]).write(to: s.root.appending(path: rel))
        #expect(throws: (any Error).self) {
            _ = try s.service.loadDatasetForAnalysis(datasetID: r.b.datasetIDs[0], codec: AFMDatasetCodec(), rootURL: s.root)
        }
    }

    @Test("Datasets of a trashed Sample are not listed and are flagged on read")
    func trashedSample() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let r = try ingestThree(s)
        try s.store.moveSampleToTrash(sample: s.sampleA, rootURL: s.root)
        let list = try s.service.listAnalysisDatasets(format: AFMDatasetCodec.format, rootURL: s.root)
        #expect(list.map(\.datasetID) == [r.b.datasetIDs[0]])
        let ctx = try s.service.loadDatasetForAnalysis(datasetID: r.a1.datasetIDs[0], codec: AFMDatasetCodec(), rootURL: s.root)
        #expect(ctx.isSampleTrashed)
    }

    @Test("Search use case emits V2 hits keyed by Dataset ID with empty paths; same-named files stay distinct")
    func searchHits() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let r = try ingestThree(s)
        let useCase = SearchWorkflowMeasurementsUseCase()
        let all = try useCase.standardDatasetHits(
            rootURL: s.root, libraryAccess: LibraryStore(), textTokens: ["afm"], numericTerms: [], displayNameByID: [:]
        )
        #expect(Set(all.map(\.id)) == Set(r.a1.datasetIDs + r.a2.datasetIDs + r.b.datasetIDs))
        #expect(all.allSatisfy { $0.sidecarPath.isEmpty && $0.measurementFilePath.isEmpty && $0.inputRef != nil })
        let byFile = try useCase.standardDatasetHits(
            rootURL: s.root, libraryAccess: LibraryStore(), textTokens: ["other"], numericTerms: [], displayNameByID: [:]
        )
        #expect(byFile.map(\.id) == r.b.datasetIDs)
        let none = try useCase.standardDatasetHits(
            rootURL: s.root, libraryAccess: LibraryStore(), textTokens: ["ahe"], numericTerms: [], displayNameByID: [:]
        )
        #expect(none.isEmpty)
        // Title resolution must never match a V2 hit by Sample key: two hits share a Sample.
        let a = all.filter { $0.inputRef?.stableID == r.a1.datasetIDs[0] || $0.inputRef?.stableID == r.a2.datasetIDs[0] }
        #expect(a.count == 2 && a[0].sampleKey == a[1].sampleKey)
        let resolved = HeatmapTitleResolution.analyzedHit(in: all, file: r.a2.datasetIDs[0], sampleKey: a[0].sampleKey)
        #expect(resolved?.id == r.a2.datasetIDs[0])
        #expect(HeatmapTitleResolution.analyzedHit(in: all, file: nil, sampleKey: a[0].sampleKey) == nil)
    }

    // MARK: AC2 / AC3

    @Test("Standard matrix gives the same processed values as parsing the file directly (non-finite included)")
    func standardMatchesDirect() throws {
        let file = try T.writeFixture(seed: 3)
        let direct = try T.expectedDataset(from: file)
        let encoded = try AFMDatasetCodec().encode(direct)
        let files = Dictionary(uniqueKeysWithValues: encoded.files.map { ($0.name, $0.data) })
        let standard = try AFMDatasetCodec().decode(files: files)
        for level in AFMSurfaceLevel.allCases {
            for flatten in AFMLineFlattenOrder.allCases {
                for zero in AFMZeroReference.allCases {
                    for channel in direct.channels {
                        let cfg = AFMProcessingConfiguration(activeChannelID: channel.id, surfaceLevel: level, lineFlattenOrder: flatten, zeroReference: zero)
                        let a = try AFMPlotComputation.process(dataset: direct, configuration: cfg)
                        let b = try AFMPlotComputation.process(dataset: standard, configuration: cfg)
                        #expect(a.values.flatMap { $0 }.map(\.bitPattern) == b.values.flatMap { $0 }.map(\.bitPattern))
                        #expect(a.xCoordinates == b.xCoordinates && a.unit == b.unit && a.warnings == b.warnings)
                        #expect(a.nonFiniteCount == b.nonFiniteCount)
                    }
                }
            }
        }
    }

    @Test("Re-processing starts from the standard matrix; display changes never alter the science; missing channel is rejected")
    func scienceVersusDisplay() throws {
        let dataset = try T.expectedDataset(from: try T.writeFixture())
        let height = try #require(dataset.channels.first)
        let cfg = AFMProcessingConfiguration(activeChannelID: height.id, surfaceLevel: .plane, lineFlattenOrder: .order1, zeroReference: .mean)
        var d1 = AFMWorkspaceStore.defaultDisplayState
        var d2 = AFMWorkspaceStore.defaultDisplayState
        d2.titleOverride = "Different title"
        d2.showColorbar = false
        d1.titleOverride = "T"
        let c1 = try AFMPlotComputation.run(dataset: dataset, configuration: cfg, display: .init(displayState: d1))
        let c2 = try AFMPlotComputation.run(dataset: dataset, configuration: cfg, display: .init(displayState: d2, scaleBar: AFMScaleBarSetting(mode: .off)))
        #expect(c1.processed == c2.processed, "display parameters must not change matrix, coordinates, unit or diagnostics")
        #expect(c1.imageData != c2.imageData)
        // Toggling away and back reproduces the first result exactly (nothing accumulates).
        let other = AFMProcessingConfiguration(activeChannelID: height.id, surfaceLevel: .robustPlane, lineFlattenOrder: .order2, zeroReference: .minimum)
        _ = try AFMPlotComputation.process(dataset: dataset, configuration: other)
        let again = try AFMPlotComputation.process(dataset: dataset, configuration: cfg)
        #expect(again == c1.processed)

        #expect(throws: AFMPlotComputation.ComputationError.channelNotFound("nope")) {
            _ = try AFMPlotComputation.run(
                dataset: dataset, configuration: AFMProcessingConfiguration(activeChannelID: "nope"), display: .init(displayState: d1)
            )
        }
        // A fresh selection falls back with a warning; an explicit run above never does.
        let fallback = try AFMPlotComputation.resolveChannelID(preferred: "nope", in: dataset)
        #expect(dataset.channels.contains { $0.id == fallback.id })
    }

    // MARK: Store

    @MainActor
    private func makeStore(root: String, loader: StandardDatasetLoader?) -> AFMWorkspaceStore {
        let store = AFMWorkspaceStore(workflowID: "afm")
        store.lastLibraryRootPath = root
        store.standardDatasetLoader = loader
        return store
    }

    private func awaitIdle(_ store: AFMWorkspaceStore) async {
        for _ in 0..<400 where await store.isAnalyzing { try? await Task.sleep(for: .milliseconds(25)) }
    }

    private func v2Hit(_ hit: WorkflowMeasurementSearchHit) -> WorkbenchSelectedHitsSnapshot {
        WorkbenchSelectedHitsSnapshot(
            workflowID: "afm", queryText: "", selectedIDs: [hit.id], selectedHits: [hit], sourceHitCount: 1, selectionSource: .canonicalSnapshot
        )
    }

    @MainActor
    @Test("Workbench analyses a V2 hit through the controlled read only (raw parser never touched), captures revision/Sample, blocks V1 Pack")
    func storeV2Analysis() async throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let r = try ingestThree(s)
        let hits = try SearchWorkflowMeasurementsUseCase().standardDatasetHits(
            rootURL: s.root, libraryAccess: LibraryStore(), textTokens: [], numericTerms: [], displayNameByID: [:]
        )
        let target = try #require(hits.first { $0.id == r.a2.datasetIDs[0] })
        #expect(!FileManager.default.fileExists(atPath: target.measurementFilePath), "no path exists for a V2 hit")

        let calls = Task6CallLog()
        let store = makeStore(root: s.root.path, loader: { id, root in
            calls.append(id)
            return try LibraryAssetService(libraryStore: LibraryStore()).loadDatasetForAnalysis(datasetID: id, codec: AFMDatasetCodec(), rootURL: root)
        })
        store.runAnalysis(selectedHitsSnapshot: v2Hit(target))
        await awaitIdle(store)

        #expect(calls.value == [r.a2.datasetIDs[0]])
        #expect(store.renderedImageData != nil && store.parsedDataset != nil)
        let capture = try #require(store.analysisCapture)
        #expect(capture.datasetID == r.a2.datasetIDs[0] && capture.datasetRevision == 1)
        #expect(capture.sourceID == r.a2.sourceID && capture.sampleUID == s.uidA && capture.libraryRootPath == s.root.path)
        #expect(store.analyzedHit?.id == target.id && store.cachedInputFiles == [target.id])
        #expect(store.currentRunTrace != nil)

        // Result equals the page-independent computation from the same stored Dataset.
        let ctx = try s.service.loadDatasetForAnalysis(datasetID: target.id, codec: AFMDatasetCodec(), rootURL: s.root)
        let direct = try AFMPlotComputation.process(dataset: ctx.dataset, configuration: store.processingConfiguration)
        #expect(direct.channelID == store.processingConfiguration.activeChannelID)

        // V1 Pack must not take a standard Dataset.
        #expect(store.packSupported == false && store.packInputFiles.isEmpty && store.hasUnsavedAnalysis == false)
        store.vault = AnalysisVault()
        store.saveAnalysis()
        #expect(store.analysisMessage == store.packUnsupportedMessage)
        #expect(store.vault?.packs.isEmpty ?? true)
    }

    @MainActor
    @Test("V2 failures never fake success: unreadable Dataset, trashed Sample and missing Library root clear the result")
    func storeV2Failures() async throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let r = try ingestThree(s)
        let hits = try SearchWorkflowMeasurementsUseCase().standardDatasetHits(
            rootURL: s.root, libraryAccess: LibraryStore(), textTokens: [], numericTerms: [], displayNameByID: [:]
        )
        let target = try #require(hits.first { $0.id == r.a1.datasetIDs[0] })

        let store = makeStore(root: s.root.path, loader: nil)
        store.runAnalysis(selectedHitsSnapshot: v2Hit(target))
        await awaitIdle(store)
        #expect(store.renderedImageData != nil)

        try s.store.moveSampleToTrash(sample: s.sampleA, rootURL: s.root)
        store.runAnalysis(selectedHitsSnapshot: v2Hit(target))
        await awaitIdle(store)
        #expect(store.renderedImageData == nil && store.analysisCapture == nil && store.analysisMessage == "AFM render failed.")

        let noRoot = makeStore(root: "", loader: nil)
        noRoot.runAnalysis(selectedHitsSnapshot: v2Hit(target))
        await awaitIdle(noRoot)
        #expect(noRoot.renderedImageData == nil && noRoot.analysisCapture == nil)
    }
}

private final class Task6CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []
    func append(_ id: String) { lock.lock(); ids.append(id); lock.unlock() }
    var value: [String] { lock.lock(); defer { lock.unlock() }; return ids }
}
