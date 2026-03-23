import Foundation
import Testing
@testable import SpinLabApp

@Suite("V2.1.3 Inbox Closed Loop")
struct V213InboxClosedLoopTests {
    @Test("editing routing draft without save does not change route plan")
    func unsavedDraftDoesNotMutateRoutePlan() {
        let pending = makePending(idSeed: "A", fileName: "RT_1mA_ch2_PN41_STO001_AMR.dat", defaultSampleKey: "PN41")
        let persistence = MockPersistenceForV213(pendingImports: [pending])
        let appState = makeAppState(persistence: persistence)

        let before = appState.pendingRoutePlan(for: pending)
        var draft = appState.routingDraft(for: pending)
        draft.defaultSampleKey = "PN40"
        let after = appState.pendingRoutePlan(for: pending)

        #expect(before.targets.first?.sampleKey == "PN41 - STO(001)")
        #expect(after.targets.first?.sampleKey == "PN41 - STO(001)")
    }

    @Test("save routing draft updates route plan and status")
    func saveRoutingDraftUpdatesRoute() {
        let pending = makePending(idSeed: "A", fileName: "RT_1mA_ch2_PN41_STO001_AMR.dat", defaultSampleKey: "PN41")
        let persistence = MockPersistenceForV213(pendingImports: [pending])
        let appState = makeAppState(persistence: persistence)

        var draft = appState.routingDraft(for: pending)
        draft.defaultSampleKey = "PN40"
        appState.saveRoutingDraft(draft, for: pending.id)

        let plan = appState.pendingRoutePlan(for: pending)
        #expect(plan.status == .applyReady)
        #expect(plan.targets.first?.sampleKey == "PN40 - STO(001)")
    }

    @Test("switching pending items keeps routing state isolated")
    func pendingRoutingIsolation() {
        let pendingA = makePending(idSeed: "A", fileName: "RT_1mA_ch2_PN41_STO001_AMR.dat", defaultSampleKey: "PN41")
        let pendingB = makePending(idSeed: "B", fileName: "RT_1mA_ch2_PN48_STO111_AMR.dat", defaultSampleKey: "PN48")
        let persistence = MockPersistenceForV213(pendingImports: [pendingA, pendingB])
        let appState = makeAppState(persistence: persistence)

        var draftA = appState.routingDraft(for: pendingA)
        draftA.defaultSampleKey = "PN40"
        appState.saveRoutingDraft(draftA, for: pendingA.id)

        let planA = appState.pendingRoutePlan(for: pendingA)
        let planB = appState.pendingRoutePlan(for: pendingB)
        let draftB = appState.routingDraft(for: pendingB)

        #expect(planA.targets.first?.sampleKey == "PN40 - STO(001)")
        #expect(planB.targets.first?.sampleKey == "PN48 - STO(111)")
        #expect(draftB.defaultSampleKey == "PN48 - STO(111)")
    }

    @Test("clear imports only clears pending queue")
    func clearImportsOnlyClearsPending() {
        let pending = makePending(idSeed: "A", fileName: "RT_1mA_ch2_PN41_STO001_AMR.dat", defaultSampleKey: "PN41")
        let persistence = MockPersistenceForV213(pendingImports: [pending])
        persistence.archivedRecordsValue = [makeArchivedRecord()]
        let appState = makeAppState(persistence: persistence)

        appState.clearPendingImports()

        #expect(appState.pendingImports.isEmpty)
        #expect(appState.archivedRecords.count == 1)
    }

    @Test("batch recompute route refreshes parsed hints")
    func batchRecomputeRouteRefreshesHints() {
        let stale = SpinLabDomain.PendingImport(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            workflow: .amrPhe,
            fileName: "RT_2mA_ch2_PN99_STO111_AMR.dat",
            sourceFilePath: "/tmp/RT_2mA_ch2_PN99_STO111_AMR.dat",
            originalFilePath: nil,
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints(
                defaultSampleKey: "PN41",
                channelHints: [SpinLabDomain.ParsedChannelHint(channel: "ch2", sampleID: nil, tags: ["STO001"])],
                substrateTags: ["STO001"]
            )
        )
        let persistence = MockPersistenceForV213(pendingImports: [stale])
        let appState = makeAppState(persistence: persistence)

        appState.recomputeAllPendingParsedHints()
        guard let updated = appState.pendingImports.first(where: { $0.id == stale.id }) else {
            Issue.record("Updated pending import not found")
            return
        }
        let plan = appState.pendingRoutePlan(for: updated)

        #expect(updated.parsedHints.defaultSampleKey == "PN99")
        #expect(plan.targets.first?.sampleKey == "PN99 - STO(111)")
    }

    private func makeAppState(persistence: MockPersistenceForV213) -> SpinLabAppState {
        SpinLabAppState(
            persistence: persistence,
            managedStorage: SpinLabManagedStorage(
                rootURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("spinlab-v213-\(UUID().uuidString)", isDirectory: true)
            )
        )
    }

    private func makePending(idSeed: String, fileName: String, defaultSampleKey: String) -> SpinLabDomain.PendingImport {
        let id: UUID
        switch idSeed {
        case "A":
            id = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        case "B":
            id = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        default:
            id = UUID()
        }

        let substrateTag = fileName.lowercased().contains("sto111") ? "STO111" : "STO001"
        return SpinLabDomain.PendingImport(
            id: id,
            workflow: .amrPhe,
            fileName: fileName,
            sourceFilePath: "/tmp/\(fileName)",
            originalFilePath: nil,
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints(
                defaultSampleKey: defaultSampleKey,
                channelHints: [SpinLabDomain.ParsedChannelHint(channel: "ch2", sampleID: nil, tags: [substrateTag])],
                substrateTags: [substrateTag]
            )
        )
    }

    private func makeArchivedRecord() -> SpinLabDomain.ArchivedRecord {
        let sample = SpinLabDomain.Sample(name: "PN40 - STO(001)")
        let measurement = SpinLabDomain.Measurement(
            name: "RT",
            sampleID: sample.id,
            sourceFilePath: "/tmp/RT.dat"
        )
        let dataset = SpinLabDomain.Dataset(
            measurementID: measurement.id,
            sourceFilePath: "/tmp/RT.dat",
            columns: ["x", "y"],
            series: []
        )
        return SpinLabDomain.ArchivedRecord(
            workflow: .amrPhe,
            project: nil,
            batch: SpinLabDomain.Batch(name: "PN40"),
            sample: sample,
            device: nil,
            measurement: measurement,
            dataset: dataset,
            latestResult: nil
        )
    }
}

private final class MockPersistenceForV213: SpinLabPersistence {
    var pendingImportsValue: [SpinLabDomain.PendingImport]
    var archivedRecordsValue: [SpinLabDomain.ArchivedRecord] = []
    var projectsValue: [SpinLabDomain.Project] = []
    var interactionSnapshotValue: SpinLabInteractionSnapshot = SpinLabInteractionSnapshot()

    init(pendingImports: [SpinLabDomain.PendingImport]) {
        self.pendingImportsValue = pendingImports
    }

    func loadPendingImports() -> [SpinLabDomain.PendingImport] { pendingImportsValue }
    func savePendingImports(_ imports: [SpinLabDomain.PendingImport]) { pendingImportsValue = imports }
    func loadArchivedRecords() -> [SpinLabDomain.ArchivedRecord] { archivedRecordsValue }
    func saveArchivedRecords(_ records: [SpinLabDomain.ArchivedRecord]) { archivedRecordsValue = records }
    func loadProjects() -> [SpinLabDomain.Project] { projectsValue }
    func saveProjects(_ projects: [SpinLabDomain.Project]) { projectsValue = projects }
    func loadInteractionSnapshot() -> SpinLabInteractionSnapshot { interactionSnapshotValue }
    func saveInteractionSnapshot(_ snapshot: SpinLabInteractionSnapshot) { interactionSnapshotValue = snapshot }
}
