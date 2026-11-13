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
        try? FileManager.default.removeItem(at: settingsURL(for: url))
    }

    /// Settings live next to the temp library, never in the developer's real Application Support (F002).
    private func settingsURL(for root: URL) -> URL {
        root.deletingLastPathComponent()
            .appending(path: root.lastPathComponent + "-library_settings.json")
    }

    private func makeAppState(root: URL) -> SpinLabAppState {
        SpinLabAppState(
            environment: .live(),
            rulesBookSettings: RulesBookSettings(),
            librarySettingsStore: LibrarySettingsStore(settingsURL: settingsURL(for: root))
        )
    }

    // MARK: - AC1: Creation Without XLSX & Navigation in UI

    @Test("Create native sample without XLSX via appState, auto-navigate, and browse in Sample Workspace")
    func createNativeSampleWithoutXLSXAndNavigate() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)

        let appState = makeAppState(root: root)
        appState.updateLibraryRoot(to: root)

        // Verify initial state has no XLSX and empty existing groups
        #expect(appState.library.librarySettings.registrySourcePath == nil)
        #expect(appState.library.libraryExistingGroups.isEmpty)

        // User submits CreateNativeSampleDraft
        let draft = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateDescription: "STO(001)",
            displayName: "My Native Sample"
        )
        let outcome = appState.createNativeSample(draft: draft)

        guard case let .success(sample, batch, _) = outcome else {
            Issue.record("Expected successful sample creation, got \(outcome)")
            return
        }

        #expect(sample.id == sample.sampleUID)
        #expect(sample.id.hasPrefix("smp_"))
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

        let appState = makeAppState(root: root)
        appState.updateLibraryRoot(to: root)

        // Create first sample
        let draft1 = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateDescription: "STO(001)"
        )
        guard case let .success(sampleS1, _, _) = appState.createNativeSample(draft: draft1) else {
            Issue.record("S1 creation failed")
            return
        }

        // Create second sample in same batch
        let draft2 = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateDescription: "LAO(001)"
        )
        guard case let .success(sampleS2, _, _) = appState.createNativeSample(draft: draft2) else {
            Issue.record("S2 creation failed")
            return
        }

        let batchGroup = appState.library.libraryExistingGroups["PN"]?.first(where: { $0.batchId == "PN110" })
        #expect(batchGroup?.samples.count == 2)

        // Switch to S1
        appState.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN110", sampleId: sampleS1.id))
        #expect(appState.library.librarySelectedSampleId == sampleS1.id)

        // Switch to S2
        appState.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN110", sampleId: sampleS2.id))
        #expect(appState.library.librarySelectedSampleId == sampleS2.id)
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
            let appState1 = makeAppState(root: root)
            appState1.updateLibraryRoot(to: root)

            let draft = CreateNativeSampleDraft(
                batchId: "PN110",
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
            let appState2 = makeAppState(root: root)
            appState2.updateLibraryRoot(to: root)

            let groups = appState2.library.libraryExistingGroups["PN"]
            #expect(groups != nil)
            let batchGroup = groups?.first(where: { $0.batchId == "PN110" })
            #expect(batchGroup != nil)

            let restoredSample = batchGroup?.samples.first(where: { $0.sampleUID == originalSampleUID })
            #expect(restoredSample != nil)
            #expect(restoredSample?.sampleUID == originalSampleUID)
            #expect(restoredSample?.persistentIdentity == originalSampleUID)
            #expect(restoredSample?.displayName == "Persistent Sample")
            #expect(restoredSample?.origin == "native")
        }
    }

    // MARK: - K3 / K4: identical attributes coexist; a re-submitted form creates one sample

    @Test("Identical batch and substrate create two samples; re-submitting one form creates only one")
    func identicalAttributesCoexistAndResubmitIsIdempotent() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)

        let appState = makeAppState(root: root)
        appState.updateLibraryRoot(to: root)

        let draftA = CreateNativeSampleDraft(batchId: "PN110", substrateDescription: "STO(001)", displayName: "Same Name")
        guard case let .success(a, _, _) = appState.createNativeSample(draft: draftA) else {
            Issue.record("A creation failed"); return
        }
        // Double click on the same form: same UID submitted again.
        guard case let .success(aAgain, _, _) = appState.createNativeSample(draft: draftA) else {
            Issue.record("Re-submit should return the existing sample"); return
        }
        #expect(aAgain.id == a.id)

        // A second form with identical attributes is a different sample.
        let draftB = CreateNativeSampleDraft(batchId: "PN110", substrateDescription: "STO(001)", displayName: "Same Name")
        guard case let .success(b, _, _) = appState.createNativeSample(draft: draftB) else {
            Issue.record("B creation failed"); return
        }
        #expect(b.id != a.id)

        let batchGroup = appState.library.libraryExistingGroups["PN"]?.first(where: { $0.batchId == "PN110" })
        #expect(batchGroup?.samples.count == 2)
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
        #expect(!sheetSource.contains("CreateSampleSheet.SubstrateIdentityTextField"))
        #expect(sheetSource.contains("CreateSampleSheet.SubmitButton"))
    }
}
