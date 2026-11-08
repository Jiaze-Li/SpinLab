import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("Native Sample UI & Integrated Acceptance")
struct NativeSampleUITests {
    private func makeTempLibrary() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "spinlab-native-ui-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - AC1: Creation Without XLSX & Navigation in UI

    @Test("Create native sample without XLSX via appState, auto-navigate, and browse in Sample Workspace")
    func createNativeSampleWithoutXLSXAndNavigate() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)

        let appState = SpinLabAppState()
        appState.updateLibraryRoot(to: root)

        // Verify initial state has no XLSX and empty existing groups
        #expect(appState.library.librarySettings.registrySourcePath == nil)
        #expect(appState.library.libraryExistingGroups.isEmpty)

        // User submits CreateNativeSampleDraft
        let draft = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateIdentity: "Piece-1",
            substrateDescription: "STO(001)",
            displayName: "My Native Sample"
        )
        let outcome = appState.createNativeSample(draft: draft)

        guard case let .success(sample, batch, _) = outcome else {
            Issue.record("Expected successful sample creation, got \(outcome)")
            return
        }

        #expect(sample.id == "PN110_Piece-1")
        #expect(sample.displayName == "My Native Sample")
        #expect(sample.origin == "native")
        #expect(batch.id == "PN110")

        // UI state assertions:
        // 1. Existing groups populated
        let existingGroups = appState.library.libraryExistingGroups["PN"]
        #expect(existingGroups != nil)
        let batchGroup = existingGroups?.first(where: { $0.batchId == "PN110" })
        #expect(batchGroup != nil)
        #expect(batchGroup?.samples.contains(where: { $0.id == sample.id }) == true)

        // 2. Navigation automatically opened the new sample drawer
        #expect(appState.library.librarySelectedPrefix == "PN")
        #expect(appState.library.librarySelectedBatchId == "PN110")
        #expect(appState.library.librarySelectedSampleId == sample.id)
        #expect(appState.library.currentRoute == .sampleWorkspace(prefix: "PN", batchId: "PN110"))

        // 3. User feedback message set
        #expect(appState.library.libraryDrawerMessage?.contains("My Native Sample") == true)
        #expect(appState.library.libraryDrawerError == nil)
    }

    // MARK: - AC1 & AC2: Multiple Samples & Switching

    @Test("Create multiple samples in same batch, browse and switch between them")
    func createMultipleSamplesAndSwitch() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)

        let appState = SpinLabAppState()
        appState.updateLibraryRoot(to: root)

        // Create first sample
        let draft1 = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateIdentity: "S1",
            substrateDescription: "STO(001)"
        )
        _ = appState.createNativeSample(draft: draft1)

        // Create second sample in same batch
        let draft2 = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateIdentity: "S2",
            substrateDescription: "LAO(001)"
        )
        _ = appState.createNativeSample(draft: draft2)

        let batchGroup = appState.library.libraryExistingGroups["PN"]?.first(where: { $0.batchId == "PN110" })
        #expect(batchGroup?.samples.count == 2)

        // Switch to S1
        appState.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN110", sampleId: "PN110_S1"))
        #expect(appState.library.librarySelectedSampleId == "PN110_S1")

        // Switch to S2
        appState.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN110", sampleId: "PN110_S2"))
        #expect(appState.library.librarySelectedSampleId == "PN110_S2")
    }

    // MARK: - AC2: App Restart Simulation & State Stability

    @Test("Simulate App restart: samples, identities and relationships are intact and consistent")
    func appRestartPreservesSamplesAndIdentities() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)

        var originalSampleUID: String = ""

        // Session 1: Create sample and close app
        do {
            let appState1 = SpinLabAppState()
            appState1.updateLibraryRoot(to: root)

            let draft = CreateNativeSampleDraft(
                batchId: "PN110",
                substrateIdentity: "S1",
                substrateDescription: "STO(001)",
                displayName: "Persistent Sample"
            )
            let outcome = appState1.createNativeSample(draft: draft)
            guard case let .success(sample, _, _) = outcome else {
                Issue.record("Session 1 creation failed")
                return
            }
            originalSampleUID = sample.sampleUID ?? ""
            #expect(!originalSampleUID.isEmpty)
        }

        // Session 2: Launch a new App instance pointing to the same library root
        do {
            let appState2 = SpinLabAppState()
            appState2.updateLibraryRoot(to: root)

            let groups = appState2.library.libraryExistingGroups["PN"]
            #expect(groups != nil)
            let batchGroup = groups?.first(where: { $0.batchId == "PN110" })
            #expect(batchGroup != nil)

            let restoredSample = batchGroup?.samples.first(where: { $0.id == "PN110_S1" })
            #expect(restoredSample != nil)
            #expect(restoredSample?.sampleUID == originalSampleUID)
            #expect(restoredSample?.persistentIdentity == originalSampleUID)
            #expect(restoredSample?.displayName == "Persistent Sample")
            #expect(restoredSample?.origin == "native")
            #expect(restoredSample?.substrateIdentity == "S1")
        }
    }

    // MARK: - AC4 & AC5: UI Error Feedback on Duplicate Creation

    @Test("Duplicate sample creation sets error feedback in UI and does not corrupt library")
    func duplicateSampleCreationUIFeedback() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)

        let appState = SpinLabAppState()
        appState.updateLibraryRoot(to: root)

        let draft = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateIdentity: "S1",
            displayName: "Sample One"
        )
        let outcome1 = appState.createNativeSample(draft: draft)
        guard case .success = outcome1 else {
            Issue.record("Initial creation failed")
            return
        }

        // Attempt duplicate
        let outcome2 = appState.createNativeSample(draft: draft)
        guard case let .failure(error) = outcome2 else {
            Issue.record("Expected failure for duplicate")
            return
        }

        #expect(appState.library.libraryDrawerError?.contains("already exists") == true)
        guard case .duplicateSample = error else {
            Issue.record("Expected .duplicateSample error")
            return
        }

        // Verify count remains 1
        let batchGroup = appState.library.libraryExistingGroups["PN"]?.first(where: { $0.batchId == "PN110" })
        #expect(batchGroup?.samples.count == 1)
    }

    // MARK: - UI Static Structure Contract

    private func source(_ rel: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
    }

    @Test("Verify New Sample entry points and sheet accessibility identifiers")
    func verifyUIEntryPointsAndIdentifiers() throws {
        let primarySource = try source("Sources/SpinLabApp/Features/Library/LibrarySampleWorkspacePrimaryView.swift")
        #expect(primarySource.contains("SampleWorkspace.NewSampleButton"))
        #expect(primarySource.contains("SampleWorkspace.EmptyStateCreateButton"))
        #expect(primarySource.contains("CreateNativeSampleSheetView("))

        let managementSource = try source("Sources/SpinLabApp/Features/Library/LibraryPrimaryView.swift")
        #expect(managementSource.contains("Library.NewSampleButton"))
        #expect(managementSource.contains("CreateNativeSampleSheetView("))

        let sheetSource = try source("Sources/SpinLabApp/Features/Library/CreateNativeSampleSheetView.swift")
        #expect(sheetSource.contains("CreateSampleSheet.Title"))
        #expect(sheetSource.contains("CreateSampleSheet.BatchModePicker"))
        #expect(sheetSource.contains("CreateSampleSheet.SubstrateIdentityTextField"))
        #expect(sheetSource.contains("CreateSampleSheet.SubmitButton"))
    }
}
