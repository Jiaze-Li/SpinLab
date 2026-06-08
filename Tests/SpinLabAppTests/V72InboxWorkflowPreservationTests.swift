import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V7.2 Inbox Workflow ID Preservation", .serialized)
struct V72InboxWorkflowPreservationTests {

    // MARK: - Pending draft tests (SpinLabAppState routing)

    @Test("unknown workflow ID is preserved in pendingDisplayAutoValues when workflowDefinitions is empty")
    func unknownWorkflowPreservedInAutoValues() {
        let pending = makePending(workflowID: "RT")
        let appState = makeAppState(pendingImports: [pending])

        let draft = appState.pendingDisplayAutoValues(for: pending)

        #expect(draft.workflowID == "RT")
    }

    @Test("unknown workflow ID is preserved in defaultConfirmationDraft when workflowDefinitions is empty")
    func unknownWorkflowPreservedInConfirmationDraft() {
        let pending = makePending(workflowID: "RT")
        let appState = makeAppState(pendingImports: [pending])

        let draft = appState.defaultConfirmationDraft(for: pending)

        #expect(draft.workflowID == "RT")
    }

    @Test("nil workflow ID produces empty string in pendingDisplayAutoValues")
    func nilWorkflowIDProducesEmpty() {
        let pending = makePending(workflowID: nil)
        let appState = makeAppState(pendingImports: [pending])

        let draft = appState.pendingDisplayAutoValues(for: pending)

        #expect(draft.workflowID == "")
    }

    @Test("whitespace-only workflow ID produces empty string in pendingDisplayAutoValues")
    func whitespaceWorkflowIDProducesEmpty() {
        let pending = makePending(workflowID: "   ")
        let appState = makeAppState(pendingImports: [pending])

        let draft = appState.pendingDisplayAutoValues(for: pending)

        #expect(draft.workflowID == "")
    }

    // MARK: - Apply sidecar test (InboxArchiveApplyService)

    @Test("unknown workflow ID is written to sidecar by InboxArchiveApplyService")
    func unknownWorkflowPreservedInApplySidecar() throws {
        let root = try makeTmpDir("wf-apply")
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceDir = root.appendingPathComponent("inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let fileName = "RT_1mA_ch1_PN42_wafer.dat"
        let sourceURL = sourceDir.appendingPathComponent(fileName)
        try Data("spinlab-test".utf8).write(to: sourceURL)

        let sample = LibrarySample(
            id: "PN42||STO|001",
            displayName: "PN42 - STO(001)",
            batchId: "PN42",
            substrateRaw: "STO(001)",
            substrateDisplay: "STO(001)",
            substrateTokens: ["STO", "001"],
            substrateTags: [],
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            updatedAt: .now
        )

        let libraryRoot = root.appendingPathComponent("library", isDirectory: true)
        let store = LibraryStore()
        let drawerRoot = store.drawerRootURL(for: sample, rootURL: libraryRoot)
        try FileManager.default.createDirectory(at: drawerRoot, withIntermediateDirectories: true)

        let index = LibraryIndex(
            createdAt: .now,
            updatedAt: .now,
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [],
            samples: [sample]
        )

        let pending = SpinLabDomain.PendingImport(
            workflow: .amrPhe,
            fileName: fileName,
            sourceFilePath: sourceURL.path,
            originalFilePath: sourceURL.path,
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints(workflowID: "RT")
        )
        let target = SpinLabDomain.RouteTarget(sampleId: sample.id, channels: ["file"])
        let service = InboxArchiveApplyService()

        let result = try service.apply(
            pending: pending,
            targets: [target],
            libraryIndex: index,
            libraryStore: store,
            libraryRootURL: libraryRoot,
            draft: nil,
            workflowDefinitions: []
        )

        #expect(result.copiedTargetCount == 1)

        let measurementsDir = drawerRoot.appendingPathComponent("measurements/RT", isDirectory: true)
        let sidecarURL = measurementsDir.appendingPathComponent(fileName + ".spinlab.json")

        guard let sidecarData = try? Data(contentsOf: sidecarURL) else {
            Issue.record("Sidecar file not found at \(sidecarURL.path)")
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sidecar = try decoder.decode(SpinLabFileSidecar.self, from: sidecarData)

        #expect(sidecar.workflow == "RT")
    }

    // MARK: - Helpers

    private func makePending(workflowID: String?) -> SpinLabDomain.PendingImport {
        SpinLabDomain.PendingImport(
            workflow: .amrPhe,
            fileName: "RT_1mA_ch1_PN42_wafer.dat",
            sourceFilePath: "/tmp/RT_1mA_ch1_PN42_wafer.dat",
            originalFilePath: nil,
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints(workflowID: workflowID)
        )
    }

    private func makeAppState(pendingImports: [SpinLabDomain.PendingImport]) -> SpinLabAppState {
        let persistence = MockPersistenceForV72(pendingImports: pendingImports)
        return SpinLabAppState(
            persistence: persistence,
            libraryArchiveScan: LibraryArchiveScanService(
                rootURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("spinlab-v72-\(UUID().uuidString)", isDirectory: true)
            )
        )
    }

    private func makeTmpDir(_ tag: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-v72-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class MockPersistenceForV72: SpinLabPersistence {
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
