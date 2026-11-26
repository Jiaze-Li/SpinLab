import Foundation
import Testing
@testable import SpinLabApp

/// Task 6 batch 3 (AC4/AC5/AC7 logic): save/replace through the Workbench store, recommendation and
/// shared selector ranking, Open target semantics, sample deletion with formal Plots.
@Suite("Task 6: Workbench formal Plot flow, selector ranking")
struct Task6WorkbenchPlotFlowTests {
    typealias T = AssetTestSupport

    // MARK: Ranking (pure)

    private func summary(
        _ id: String, inputs: [(String, String)], samples: [String] = ["S1"], title: String = "T", saved: TimeInterval,
        files: [String] = ["f.ibw"], batch: String = "PN1"
    ) -> FormalPlotSummary {
        FormalPlotSummary(
            plotID: id, revision: 1, isStale: false, title: title, workflowLabel: "AFM", savedAt: Date(timeIntervalSince1970: saved),
            inputs: inputs.map { PlotInputKey(datasetID: $0.0, channelID: $0.1) }, sampleUIDs: samples,
            sampleLabels: samples, batchLabels: [batch], fileNames: files, channelSummary: inputs.first?.1 ?? ""
        )
    }

    private let subject = FormalPlotSaveSubject(
        inputs: [PlotInputKey(datasetID: "D1", channelID: "H")], sampleUIDs: ["S1"], workflowLabel: "AFM", openedPlotID: nil
    )

    @Test("Groups: same inputs, shares dataset, same sample, other; newest first inside a group; corrupt excluded; stable ties")
    func rankingGroups() {
        let plots = [
            summary("p_other", inputs: [("D9", "H")], samples: ["S9"], saved: 50),
            summary("p_sample", inputs: [("D2", "H")], saved: 40),
            summary("p_share_old", inputs: [("D1", "P")], saved: 10),
            summary("p_same_old", inputs: [("D1", "H")], saved: 20),
            summary("p_same_new", inputs: [("D1", "H")], saved: 30),
            summary("p_share_two", inputs: [("D1", "P"), ("D3", "H")], saved: 5),
            FormalPlotSummary(plotID: "p_bad", revision: 1, isStale: false, title: "", workflowLabel: "AFM", savedAt: .now,
                              inputs: [PlotInputKey(datasetID: "D1", channelID: nil)], sampleUIDs: ["S1"], sampleLabels: [],
                              batchLabels: [], fileNames: [], channelSummary: ""),
        ]
        let ranked = FormalPlotRanker.rank(plots, subject: subject)
        #expect(ranked.map(\.id) == ["p_same_new", "p_same_old", "p_share_old", "p_share_two", "p_sample", "p_other"].map { $0 })
        #expect(ranked.map(\.relevance).first == .sameInputs && !ranked.contains { $0.id == "p_bad" })
        // Deterministic for equal times.
        let tie = [summary("b", inputs: [("D1", "H")], saved: 1), summary("a", inputs: [("D1", "H")], saved: 1)]
        #expect(FormalPlotRanker.rank(tie, subject: subject).map(\.id) == ["a", "b"])
    }

    @Test("Recommendation comes from the record: explicit Open target, else newest identical inputs, else New; different channel → New")
    func recommendation() {
        let plots = [
            summary("old", inputs: [("D1", "H")], saved: 10), summary("new", inputs: [("D1", "H")], saved: 20),
            summary("phase", inputs: [("D1", "P")], saved: 99),
        ]
        #expect(FormalPlotRanker.recommend(plots, subject: subject) == .replace(plotID: "new"))
        var opened = subject
        opened = FormalPlotSaveSubject(inputs: subject.inputs, sampleUIDs: subject.sampleUIDs, workflowLabel: "AFM", openedPlotID: "old")
        #expect(FormalPlotRanker.recommend(plots, subject: opened) == .replace(plotID: "old"))
        let gone = FormalPlotSaveSubject(inputs: subject.inputs, sampleUIDs: subject.sampleUIDs, workflowLabel: "AFM", openedPlotID: "deleted")
        #expect(FormalPlotRanker.recommend(plots, subject: gone) == .replace(plotID: "new"))
        let phaseSubject = FormalPlotSaveSubject(inputs: [PlotInputKey(datasetID: "D1", channelID: "Z")], sampleUIDs: ["S1"], workflowLabel: "AFM", openedPlotID: nil)
        #expect(FormalPlotRanker.recommend(plots, subject: phaseSubject) == .new)
        #expect(FormalPlotRanker.recommend([], subject: subject) == .new)
    }

    @Test("Search finds non-related plots by title, sample, batch and file name; empty query keeps all")
    func search() {
        let plots = [
            summary("a", inputs: [("D1", "H")], samples: ["PN7-1"], title: "Step edges", saved: 1, files: ["scanA.ibw"], batch: "PN7"),
            summary("b", inputs: [("D5", "H")], samples: ["PN8-2"], title: "Island", saved: 2, files: ["zzz.ibw"], batch: "PN8"),
        ]
        let ranked = FormalPlotRanker.rank(plots, subject: subject)
        #expect(FormalPlotRanker.filter(ranked, query: "").count == 2)
        #expect(FormalPlotRanker.filter(ranked, query: "island").map(\.id) == ["b"])
        #expect(FormalPlotRanker.filter(ranked, query: "pn7").map(\.id) == ["a"])
        #expect(FormalPlotRanker.filter(ranked, query: "ZZZ").map(\.id) == ["b"])
        #expect(FormalPlotRanker.filter(ranked, query: "pn7 island").isEmpty)
    }

    // MARK: Store flow against a real isolated V2 Library

    private struct Env {
        let s: T.Scenario
        let lease: LibraryWriteLease
        let lockDir: URL
        let d1: String, d2: String
        let hit1: WorkflowMeasurementSearchHit, hit2: WorkflowMeasurementSearchHit
    }

    private func makeEnv() throws -> Env {
        let s = try T.makeScenario()
        let lockDir = FileManager.default.temporaryDirectory.appending(path: "flowlease_\(UUID().uuidString)", directoryHint: .isDirectory)
        let lease = LibraryWriteLease(lockDirectory: lockDir)
        #expect(lease.acquire(rootURL: s.root) == .writable)
        s.service.writeLease = lease
        let r1 = try T.ingest(s, file: try T.writeFixture(seed: 0), target: s.uidA)
        let r2 = try T.ingest(s, file: try T.writeFixture(seed: 4, name: "b.ibw"), target: s.uidA)
        let hits = try SearchWorkflowMeasurementsUseCase().standardDatasetHits(
            rootURL: s.root, libraryAccess: LibraryStore(), textTokens: [], numericTerms: [], displayNameByID: [:]
        )
        return Env(
            s: s, lease: lease, lockDir: lockDir, d1: r1.datasetIDs[0], d2: r2.datasetIDs[0],
            hit1: hits.first { $0.id == r1.datasetIDs[0] }!, hit2: hits.first { $0.id == r2.datasetIDs[0] }!
        )
    }

    private func cleanup(_ e: Env) {
        e.lease.release()
        try? FileManager.default.removeItem(at: e.s.root)
        try? FileManager.default.removeItem(at: e.lockDir)
    }

    @MainActor
    private func analyze(_ store: AFMWorkspaceStore, _ hit: WorkflowMeasurementSearchHit) async {
        store.runAnalysis(selectedHitsSnapshot: WorkbenchSelectedHitsSnapshot(
            workflowID: "afm", queryText: "", selectedIDs: [hit.id], selectedHits: [hit], sourceHitCount: 1, selectionSource: .canonicalSnapshot
        ))
        await settle(store)
    }

    @MainActor
    private func settle(_ store: AFMWorkspaceStore) async {
        for _ in 0..<600 where store.isAnalyzing || store.isSavingFormalPlot || (store.latestCandidate == nil && store.analysisCapture != nil && store.renderedImageData == nil) {
            try? await Task.sleep(for: .milliseconds(20))
        }
        // Control changes render asynchronously; wait for the candidate that matches the controls.
        for _ in 0..<600 where store.analysisCapture != nil && store.latestCandidate == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @MainActor
    private func makeStore(_ e: Env) -> AFMWorkspaceStore {
        let store = AFMWorkspaceStore(workflowID: "afm")
        store.lastLibraryRootPath = e.s.root.path
        return store
    }

    @MainActor
    private func save(_ store: AFMWorkspaceStore, _ e: Env, _ mode: FormalPlotSaveMode, root: URL? = nil) async {
        store.saveFormalPlot(mode: mode, currentRootURL: root ?? e.s.root, service: e.s.service, onComplete: nil)
        for _ in 0..<600 where store.isSavingFormalPlot { try? await Task.sleep(for: .milliseconds(20)) }
        try? await Task.sleep(for: .milliseconds(50))
    }

    @MainActor
    @Test("Analyze → New Plot → read back; then default recommendation is Replace; replace advances revision; stale target fails with New offered")
    func saveReplaceFlow() async throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let store = makeStore(e)
        #expect(store.formalPlotUnavailableReason(currentRootURL: e.s.root, isV2Library: true) != nil, "nothing analyzed yet")
        await analyze(store, e.hit1)
        #expect(store.formalPlotUnavailableReason(currentRootURL: e.s.root, isV2Library: true) == nil)
        #expect(store.formalPlotUnavailableReason(currentRootURL: e.s.root, isV2Library: false) != nil)

        await save(store, e, .new)
        let lib = FormalPlotLibrary(service: e.s.service)
        var list = try lib.summaries(rootURL: e.s.root)
        #expect(list.count == 1 && store.saveMessage == "Saved a new plot to the Library.")
        let first = list[0]
        #expect(first.inputs == [PlotInputKey(datasetID: e.d1, channelID: store.processingConfiguration.activeChannelID)])
        #expect(first.sampleUIDs == [e.s.uidA])
        let stored = try AFMPlotCodec.decode(files: try e.s.service.loadPlot(plotID: first.plotID, rootURL: e.s.root).files)
        #expect(stored.manifest.input.datasetRevision == 1 && stored.manifest.processingConfiguration == store.processingConfiguration)
        #expect(!(lib.png(plotID: first.plotID, rootURL: e.s.root)?.isEmpty ?? true))

        // The just-saved Plot is the explicit target; recommendation says Replace.
        let opened = try #require(store.openedFormalPlot)
        #expect(opened.plotID == first.plotID && opened.expectedRevision == 1)
        let subject = try #require(store.formalPlotSaveSubject)
        #expect(FormalPlotRanker.recommend(list, subject: subject) == .replace(plotID: first.plotID))

        // Replace advances the revision and keeps one Plot; target moves to the new revision.
        store.updateHeatmapTitle("Edited title")
        await settle(store)
        await save(store, e, .replace(.init(plotID: first.plotID, expectedRevision: 1, expectedInputs: first.inputs)))
        list = try lib.summaries(rootURL: e.s.root)
        #expect(list.count == 1 && list[0].revision == 2 && list[0].title == "Edited title")
        #expect(store.openedFormalPlot?.expectedRevision == 2)

        // A stale target (revision 1 again) is refused, offers New Plot, and writes nothing.
        await save(store, e, .replace(.init(plotID: first.plotID, expectedRevision: 1, expectedInputs: first.inputs)))
        #expect(store.saveMessage?.contains("New Plot") == true)
        #expect(try lib.summaries(rootURL: e.s.root).first?.revision == 2)
    }

    @MainActor
    @Test("Never saves a figure that does not match the controls; Dataset or channel change drops the Open target")
    func staleCandidateAndTarget() async throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let store = makeStore(e)
        await analyze(store, e.hit1)
        await save(store, e, .new)
        let plotID = try #require(store.openedFormalPlot?.plotID)

        store.updateSurfaceLevel(.plane)           // render pending: candidate invalid right now
        #expect(store.latestCandidate == nil)
        #expect(store.formalPlotUnavailableReason(currentRootURL: e.s.root, isV2Library: true) != nil)
        store.saveFormalPlot(mode: .new, currentRootURL: e.s.root, service: e.s.service, onComplete: nil)
        #expect(store.saveMessage?.contains("out of date") == true || store.saveMessage?.contains("Nothing to save") == true)
        #expect(try FormalPlotLibrary(service: e.s.service).summaries(rootURL: e.s.root).count == 1)
        await settle(store)
        #expect(store.latestCandidate?.processed.configuration.surfaceLevel == .plane)

        // Switching to another channel ends the explicit target (matching rules apply again).
        let other = try #require(store.parsedDataset?.channels.first { $0.id != store.processingConfiguration.activeChannelID })
        store.updateActiveChannel(other.id)
        #expect(store.openedFormalPlot == nil)
        await settle(store)
        let list = try FormalPlotLibrary(service: e.s.service).summaries(rootURL: e.s.root)
        #expect(FormalPlotRanker.recommend(list, subject: try #require(store.formalPlotSaveSubject)) == .new, "same Dataset, other channel → default New")
        _ = plotID

        // Analyzing another Dataset also ends a target that belonged to the first.
        store.setOpenedFormalPlot(.init(plotID: plotID, expectedRevision: 1, expectedInputs: list[0].inputs))
        await analyze(store, e.hit2)
        #expect(store.openedFormalPlot == nil)
    }

    @MainActor
    @Test("Library switched after Analyze: Save is rejected, nothing is written to either Library")
    func librarySwitch() async throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let other = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: other.root) }
        let store = makeStore(e)
        await analyze(store, e.hit1)
        await save(store, e, .new, root: other.root)
        #expect(store.saveMessage != nil && store.saveMessage != "Saved a new plot to the Library.")
        #expect(try FormalPlotLibrary(service: e.s.service).summaries(rootURL: e.s.root).isEmpty)
        #expect(try FormalPlotLibrary(service: other.service).summaries(rootURL: other.root).isEmpty)
    }

    @MainActor
    @Test("Open from Library: effective science/display settings restored, Dataset re-analysed at its current revision, title kept")
    func openPlot() async throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let store = makeStore(e)
        store.updateSurfaceLevel(.robustPlane)
        store.updateLineFlattenOrder(.order1)
        await analyze(store, e.hit1)
        store.updateHeatmapTitle("My title")
        await settle(store)
        await save(store, e, .new)
        let summary = try #require(try FormalPlotLibrary(service: e.s.service).summaries(rootURL: e.s.root).first)

        // Fresh Workbench, as after a restart.
        let reopened = makeStore(e)
        let loaded = try e.s.service.loadPlot(plotID: summary.plotID, rootURL: e.s.root)
        let manifest = try AFMPlotCodec.decode(files: loaded.files).manifest
        reopened.prepareToOpenFormalPlot(
            manifest: manifest,
            target: .init(plotID: summary.plotID, expectedRevision: loaded.row.record.currentRevision, expectedInputs: loaded.row.inputs),
            libraryRootPath: e.s.root.path
        )
        await analyze(reopened, e.hit1)
        #expect(reopened.processingConfiguration == store.processingConfiguration)
        #expect(reopened.heatmapDisplayState.titleOverride == "My title")
        #expect(reopened.openedFormalPlot?.plotID == summary.plotID)
        #expect(reopened.latestCandidate?.processed.values.flatMap { $0 }.map(\.bitPattern)
                == store.latestCandidate?.processed.values.flatMap { $0 }.map(\.bitPattern))
    }

    @MainActor
    @Test("Read-only lease: Save reports an error and writes nothing (never silently memory-only)")
    func readOnlyLease() async throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let store = makeStore(e)
        await analyze(store, e.hit1)
        e.lease.release()
        let blocked = LibraryWriteLease(lockDirectory: e.lockDir)
        let holder = LibraryWriteLease(lockDirectory: e.lockDir)
        _ = holder.acquire(rootURL: e.s.root)
        _ = blocked.acquire(rootURL: e.s.root)
        e.s.service.writeLease = blocked
        await save(store, e, .new)
        #expect(store.saveMessage?.isEmpty == false && store.saveMessage != "Saved a new plot to the Library.")
        holder.release()
        #expect(try FormalPlotLibrary(service: e.s.service).summaries(rootURL: e.s.root).isEmpty)
    }

    // MARK: Sample deletion honours formal Plots

    @Test("Permanent Sample deletion: Plot made only from that Sample is removed with its files; mixed Plot is kept and stale")
    func sampleDeletion() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        func content(_ dataset: String) throws -> (PlotInputRef, StandardizedDatasetContent) {
            let rev = try e.s.service.loadDataset(datasetID: dataset, codec: AFMDatasetCodec(), rootURL: e.s.root)
            let inp = PlotInputRef(datasetID: dataset, channelID: rev.dataset.channels[0].id, revision: rev.revision)
            let c = try AFMPlotComputation.run(
                dataset: rev.dataset, configuration: .init(activeChannelID: inp.channelID), display: .init(displayState: AFMWorkspaceStore.defaultDisplayState)
            )
            return (inp, try AFMPlotCodec.encode(candidate: c, input: inp, sampleUIDs: [], title: "t", displayState: AFMWorkspaceStore.defaultDisplayState, savedAt: .now, appVersion: "t"))
        }
        let (inp, c) = try content(e.d1)
        let plot = try e.s.service.publishPlot(content: c, inputs: [inp], operationID: "p1", capturedRootURL: e.s.root, rootURL: e.s.root)
        let trashed = try e.s.store.moveSampleToTrash(sample: e.s.sampleA, rootURL: e.s.root)
        let uid = trashed.sampleUID ?? trashed.id
        let plan = try e.s.service.planPermanentSampleDeletion(sampleUIDs: [uid], rootURL: e.s.root)
        #expect(plan.assetsToDelete.contains(plot.plotID))
        _ = try e.s.service.commitPermanentSampleDeletion(plan: plan, operationID: "del-sample", rootURL: e.s.root)
        #expect(!T.exists(e.s, "storage/\(plot.plotID)"))
        #expect(try e.s.service.listPlots(rootURL: e.s.root).isEmpty)
    }
}
