import Foundation
import Testing
@testable import SpinLabApp

/// Task 12: candidates produced by a real AHE Analyze run and their invalidation.
@MainActor
@Suite("Task 12 AHE store candidates", .serialized)
struct Task12AHEStoreCandidateTests {

    private let header = "Comment,Time Stamp (sec),Status (code),Temperature (K),Magnetic Field (Oe),Sample Position (deg),Bridge 1 Resistivity (Ohm),Bridge 1 Excitation (uA),Bridge 2 Resistivity (Ohm),Bridge 2 Excitation (uA),Bridge 3 Resistivity (Ohm),Bridge 3 Excitation (uA),Bridge 4 Resistivity (Ohm),Bridge 4 Excitation (uA),Bridge 1 Std. Dev. (Ohm),Bridge 2 Std. Dev. (Ohm),Bridge 3 Std. Dev. (Ohm),Bridge 4 Std. Dev. (Ohm),Number of Readings,Bridge 1 Resistance (Ohms),Bridge 2 Resistance (Ohms),Bridge 3 Resistance (Ohms),Bridge 4 Resistance (Ohms)"

    private func makeDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "spinlab-t12-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A small hysteresis-like loop; `bridge2` also fills Bridge 2 so a second channel has data.
    private func loop(bridge2: Bool) -> String {
        let fields: [Double] = [-5000, -2500, -500, 0, 500, 2500, 5000, 2500, 500, 0, -500, -2500]
        let rows = fields.enumerated().map { index, h -> String in
            let r = (h > 0 ? 0.2 : -0.2) + h * 1e-5 + (index > 6 ? 0.02 : 0)
            let b2 = bridge2 ? "\(r * 2)" : ""
            return ",\(index),4449,80.0,\(h),0,\(r),500,\(b2),\(bridge2 ? "500" : ""),,,,,,,,,25,\(r),\(b2),,"
        }
        return "[Header]\nTITLE, test\nBYAPP, Resistivity, 2.1, 1.0\nINFO, Ohm, Sample1 Units\n[Data]\n\(header)\n" + rows.joined(separator: "\n")
    }

    private func hit(file: URL, key: String = "PN31|o|STO|111", channels: [String] = ["ch1"], temp: String = "80K") -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/\(key)-\(file.lastPathComponent).spinlab.json",
            measurementFilePath: file.path, sourceFilePath: file.path,
            workflowID: "ahe", workflowDisplayName: "AHE", workflowCanonicalID: "ahe",
            batchID: "PN31", sampleKey: key, sampleSubstrate: "STO111",
            conditions: ["temperature": temp], channels: channels, appliedAt: .distantPast)
    }

    private func run(_ store: AHEWorkspaceStore, hits: [WorkflowMeasurementSearchHit]) async throws {
        store.cachedSearchResults = hits
        store.runAnalysis(selectedHitsSnapshot: WorkbenchSelectedHitsSnapshot(
            workflowID: WorkflowKey.ahe.rawValue, queryText: "", selectedIDs: Set(hits.map(\.id)),
            selectedHits: hits, sourceHitCount: hits.count, selectionSource: .canonicalSnapshot))
        try await settle(store)
    }

    private func settle(_ store: AHEWorkspaceStore) async throws {
        var attempts = 0
        while store.isPlotRendering && attempts < 200 {
            try await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }
    }

    private func independentMetrics(_ store: AHEWorkspaceStore, key: String) throws -> AHEExtractedMetric {
        let corrected = AHEBackgroundCorrectionUseCase().correctedSeries(try #require(store.ingestionResult).series)
        return try #require(try ExtractAHEMetricsUseCase.extractAHEMetricsPerSeries(from: corrected).get()[key])
    }

    @Test("a real Analyze run offers Hc and R_AHE equal to the unchanged extractor output, with source and conditions")
    func candidateMatchesExtractor() async throws {
        let dir = try makeDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "a.dat"); try loop(bridge2: false).write(to: file, atomically: true, encoding: .utf8)
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        store.librarySessionProvider = { "session-1" }
        let h = hit(file: file)
        try await run(store, hits: [h])

        let expected = try independentMetrics(store, key: h.sampleKey)
        let hcOffer = store.resultOffer(sampleKey: h.sampleKey, metric: .hc)
        let raheOffer = store.resultOffer(sampleKey: h.sampleKey, metric: .rAHE)
        let hc = try #require(hcOffer.candidates.first)
        let rahe = try #require(raheOffer.candidates.first)
        #expect(hc.value == expected.hc && hc.unit == "T" && hc.origin == .computed)
        #expect(rahe.value == expected.rAHE && rahe.unit == "Ω")
        #expect(hc.conditions == ["temperature": "80K"])
        #expect(hc.inputSummary == "a.dat · ch1")
        #expect(hc.sourceBatchID == "PN31" && hc.sourceSampleKey == h.sampleKey)
        #expect(store.isCurrent(hc) && store.isCurrent(rahe))
        #expect(hcOffer.candidates.count == 1, "no override, so only the computed value")
    }

    @Test("two channels of one Sample are refused with a reason")
    func multiChannelRefused() async throws {
        let dir = try makeDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "a.dat"); try loop(bridge2: true).write(to: file, atomically: true, encoding: .utf8)
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        store.librarySessionProvider = { "session-1" }
        let h = hit(file: file, channels: ["ch1", "ch2"])
        try await run(store, hits: [h])
        let offer = store.resultOffer(sampleKey: h.sampleKey, metric: .hc)
        #expect(offer.candidates.isEmpty)
        #expect(offer.unavailableReason?.contains("2 curves") == true)
    }

    @Test("when the first input yields no curve, conditions come from the input that actually produced the curve")
    func conditionsFromSurvivor() async throws {
        let dir = try makeDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let bad = dir.appending(path: "bad.dat"); try "not a PPMS file".write(to: bad, atomically: true, encoding: .utf8)
        let good = dir.appending(path: "good.dat"); try loop(bridge2: false).write(to: good, atomically: true, encoding: .utf8)
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        store.librarySessionProvider = { "session-1" }
        let first = hit(file: bad, temp: "10K"), second = hit(file: good, temp: "80K")
        try await run(store, hits: [first, second])
        let candidate = try #require(store.resultOffer(sampleKey: first.sampleKey, metric: .hc).candidates.first)
        #expect(candidate.conditions == ["temperature": "80K"])
        #expect(candidate.inputSummary == "good.dat · ch1")
    }

    @Test("a new run, clear, cancel and Pack restore make earlier candidates stale")
    func invalidation() async throws {
        let dir = try makeDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "a.dat"); try loop(bridge2: false).write(to: file, atomically: true, encoding: .utf8)
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        store.librarySessionProvider = { "session-1" }
        let h = hit(file: file)
        try await run(store, hits: [h])
        let first = try #require(store.resultOffer(sampleKey: h.sampleKey, metric: .hc).candidates.first)
        #expect(store.isCurrent(first))

        // Run start: stale immediately and no offer while rendering.
        store.runAnalysis(selectedHitsSnapshot: WorkbenchSelectedHitsSnapshot(
            workflowID: WorkflowKey.ahe.rawValue, queryText: "", selectedIDs: [h.id], selectedHits: [h],
            sourceHitCount: 1, selectionSource: .canonicalSnapshot))
        #expect(store.isPlotRendering)
        #expect(!store.isCurrent(first))
        #expect(store.resultOffer(sampleKey: h.sampleKey, metric: .hc).candidates.isEmpty)
        try await settle(store)
        let second = try #require(store.resultOffer(sampleKey: h.sampleKey, metric: .hc).candidates.first)
        #expect(second.runToken != first.runToken && !store.isCurrent(first) && store.isCurrent(second))

        // Cancel.
        store.runAnalysis(selectedHitsSnapshot: WorkbenchSelectedHitsSnapshot(
            workflowID: WorkflowKey.ahe.rawValue, queryText: "", selectedIDs: [h.id], selectedHits: [h],
            sourceHitCount: 1, selectionSource: .canonicalSnapshot))
        store.cancelInflightWork()
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(!store.isCurrent(second))

        // Clear.
        try await run(store, hits: [h])
        let third = try #require(store.resultOffer(sampleKey: h.sampleKey, metric: .rAHE).candidates.first)
        store.clearPlot()
        #expect(!store.isCurrent(third))
        #expect(store.resultOffer(sampleKey: h.sampleKey, metric: .rAHE).candidates.isEmpty)
    }

    @Test("Pack restore with a cached ingestion never produces a candidate, even for a previously analysed Sample")
    func packRestoreProducesNoCandidate() async throws {
        let dir = try makeDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "a.dat"); try loop(bridge2: false).write(to: file, atomically: true, encoding: .utf8)
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        store.librarySessionProvider = { "session-1" }
        let h = hit(file: file)
        try await run(store, hits: [h])
        let before = try #require(store.resultOffer(sampleKey: h.sampleKey, metric: .hc).candidates.first)

        let ingestion = try #require(store.ingestionResult)
        let config = AHEPackConfig(titleTemplate: "#tab #sample", showPlotGrid: false)
        let result = AHEPackResult(ingestionResult: ingestion)
        let pack = try AnalysisPack(label: "p", workflowID: "ahe", filePaths: [file.path], sampleKeys: [h.sampleKey], config: config, result: result)
        store.restoreFromPack(config: config, result: result, pack: pack, restoreSearchState: { _, _ in }, seedSelection: { _, _ in })
        #expect(!store.isCurrent(before))
        #expect(store.resultOffer(sampleKey: h.sampleKey, metric: .hc).candidates.isEmpty)
        #expect(store.resultOffer(sampleKey: h.sampleKey, metric: .rAHE).unavailableReason != nil)
    }

    @Test("override candidates need a finite value from the current run; edits and re-analysis make them stale")
    func overrideCandidates() async throws {
        let dir = try makeDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "a.dat"); try loop(bridge2: false).write(to: file, atomically: true, encoding: .utf8)
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        store.librarySessionProvider = { "session-1" }
        let h = hit(file: file)
        try await run(store, hits: [h])

        store.updateHcCandidate(rawValue: "nan", rawReason: "x")
        #expect(store.resultOffer(sampleKey: h.sampleKey, metric: .hc).candidates.count == 1, "nan is not a candidate")
        store.updateHcCandidate(rawValue: "inf", rawReason: "x")
        #expect(store.resultOffer(sampleKey: h.sampleKey, metric: .hc).candidates.count == 1)

        store.updateHcCandidate(rawValue: "0.012", rawReason: "checked by eye")
        let offer = store.resultOffer(sampleKey: h.sampleKey, metric: .hc)
        #expect(offer.candidates.count == 2)
        let computed = offer.candidates[0], corrected = offer.candidates[1]
        #expect(computed.origin == .computed)
        #expect(corrected.origin == .manualOverride(reason: "checked by eye") && corrected.value == 0.012)
        #expect(store.isCurrent(computed) && store.isCurrent(corrected))
        #expect(store.resultOffer(sampleKey: h.sampleKey, metric: .rAHE).candidates.count == 1, "Hc override does not leak to R_AHE")

        // Editing the override makes the older panel input stale; the computed value too (panel was opened with both).
        store.updateHcCandidate(rawValue: "0.013", rawReason: "again")
        #expect(!store.isCurrent(corrected))

        // Re-analysis: the draft belongs to the old run and is not offered next to the new computed value.
        let kept = try #require(store.resultOffer(sampleKey: h.sampleKey, metric: .hc).candidates.last)
        try await run(store, hits: [h])
        #expect(!store.isCurrent(kept))
        #expect(store.resultOffer(sampleKey: h.sampleKey, metric: .hc).candidates.count == 1)
    }

    @Test("switching Library after Analyze makes the earlier candidates unavailable")
    func librarySwitchInvalidates() async throws {
        let dir = try makeDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "a.dat"); try loop(bridge2: false).write(to: file, atomically: true, encoding: .utf8)
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        var session: String? = "session-1"
        store.librarySessionProvider = { session }
        let h = hit(file: file)
        try await run(store, hits: [h])
        let candidate = try #require(store.resultOffer(sampleKey: h.sampleKey, metric: .hc).candidates.first)
        #expect(store.isCurrent(candidate))
        session = "session-2"
        #expect(store.resultOffer(sampleKey: h.sampleKey, metric: .hc).candidates.isEmpty)
        #expect(!store.isCurrent(candidate))
        session = nil
        #expect(store.resultOffer(sampleKey: h.sampleKey, metric: .hc).candidates.isEmpty)
    }
}
