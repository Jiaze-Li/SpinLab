import Foundation
import Testing
@testable import SpinLabApp

/// PR #191 — Save and Switch must decide on the REAL save outcome.
/// Every test drives the real `saveAndContinuePendingLibrarySelectionChange()` against a real
/// on-disk Library; nothing clears the draft or commits navigation by hand.
@MainActor
@Suite("PR191 Save and Switch outcome", .serialized, .rulesGlobalState)
struct PR191SaveAndSwitchOutcomeTests {

    private func makeAppState() -> SpinLabAppState {
        SpinLabAppState(
            persistence: LocalPersistenceStub(),
            libraryArchiveScan: LibraryArchiveScanService(
                rootURL: FileManager.default.temporaryDirectory
                    .appending(path: "pr191-scan-\(UUID().uuidString)", directoryHint: .isDirectory)
            )
        )
    }

    private func makeSample(_ id: String) -> LibrarySample {
        LibrarySample(
            id: id, displayName: "Sample \(id)", batchId: "B1",
            substrateRaw: "", substrateDisplay: "", substrateTokens: [],
            substrateTags: [], metadata: [:], orderedMetadata: [],
            numericTags: [:], numericDisplay: [:],
            sourceSheetName: nil, sourceRowNumber: nil, updatedAt: Date()
        )
    }

    private struct Fixture {
        var root: URL
        var appState: SpinLabAppState
        var sampleAFile: URL
    }

    /// Real Library (B1: A, C) on disk, editing session opened on A, navigation to C deferred.
    private func makeDirtyEditOnA() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pr191-save-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let appState = makeAppState()
        let store = appState.library.libraryStore
        let batch = LibraryBatch(
            id: "B1", displayName: "B1", sheetName: "STO", metadata: [:], numericTags: [:],
            numericDisplay: [:], sampleKeys: ["A", "C"], updatedAt: Date()
        )
        try store.createDrawer(for: makeSample("A"), batch: batch, rootURL: root)
        try store.createDrawer(for: makeSample("C"), batch: batch, rootURL: root)
        let index = try store.syncIndexFromFilesystem(rootURL: root)
        let lib = appState.library
        lib.librarySettings.rootPath = root.path
        lib.libraryExistingGroups = ["PN": [LibraryPreviewBatchGroup(batchId: "B1", samples: index.samples.sorted { $0.id < $1.id })]]
        appState.selectedArea = .library
        appState.navigate(to: .libraryDrawer(prefix: "PN", batchId: "B1", sampleId: "A"))
        lib.libraryActiveSelectionSource = .drawer
        let onDisk = try #require(index.samples.first { $0.id == "A" })
        lib.beginEditingSelectedLibrarySample(selectedSample: onDisk)
        var draft = try #require(lib.librarySampleEditDraft)
        draft.substrateTagsText = "edited-tag"
        lib.librarySampleEditDraft = draft
        #expect(lib.librarySampleEditIsDirty)
        let result = appState.navigate(to: .libraryDrawer(prefix: "PN", batchId: "B1", sampleId: "C"))
        #expect(result != .committed, "dirty draft must defer the navigation")
        #expect(lib.hasPendingSelectionChange())
        let file = store.sampleDirectoryURL(root, batchID: "B1", sampleKey: "A").appending(path: "sample.json")
        return Fixture(root: root, appState: appState, sampleAFile: file)
    }

    @Test("Saved with a Registry sync warning: navigation proceeds, warning is kept, success is not claimed for the registry")
    func savedWithRegistryWarningSwitches() throws {
        let f = try makeDirtyEditOnA()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let lib = f.appState.library

        f.appState.saveAndContinuePendingLibrarySelectionChange()

        let saved = try String(contentsOf: f.sampleAFile, encoding: .utf8)
        #expect(saved.contains("edited-tag"), "the sample file must really be saved")
        #expect(lib.librarySelectedSampleId == "C", "a saved sample must switch")
        #expect(lib.currentRoute == .sampleWorkspace(prefix: "PN", batchId: "B1"))
        #expect(lib.librarySampleEditDraft == nil)
        #expect(!lib.hasPendingSelectionChange())
        // The warning is not lost and the registry is not reported as synced.
        let warning = lib.librarySampleEditError ?? ""
        #expect(warning.contains("registry source not found"))
        let message = lib.librarySampleEditMessage ?? ""
        #expect(message.contains("已保存样品编辑"))
        #expect(message.contains("同步警告"))
        #expect(!message.contains("Metadata 写回 XLSX：成功"), "must not claim a successful registry sync")
    }

    @Test("Real write failure: nothing switches, Draft, selection and pending navigation are kept, no false success")
    func realWriteFailureKeepsEverything() throws {
        let f = try makeDirtyEditOnA()
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: f.sampleAFile.path)
            try? FileManager.default.removeItem(at: f.root)
        }
        let lib = f.appState.library
        let before = try Data(contentsOf: f.sampleAFile)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: f.sampleAFile.path)

        f.appState.saveAndContinuePendingLibrarySelectionChange()

        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: f.sampleAFile.path)
        #expect(try Data(contentsOf: f.sampleAFile) == before, "refused write must not change the file")
        #expect(lib.librarySelectedSampleId == "A", "selection must stay on the edited sample")
        #expect(lib.librarySampleEditDraft?.substrateTagsText == "edited-tag", "the Draft must be kept")
        #expect(lib.librarySampleEditIsDirty)
        #expect(lib.hasPendingSelectionChange(), "the request stays for retry")
        #expect(lib.librarySampleEditError != nil)
        #expect(!(lib.librarySampleEditMessage ?? "").contains("已保存"), "no false success message")
    }

    @Test("Control: once the write works again, the kept request completes through the same real path")
    func retryAfterFailureCompletes() throws {
        let f = try makeDirtyEditOnA()
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: f.sampleAFile.path)
            try? FileManager.default.removeItem(at: f.root)
        }
        let lib = f.appState.library
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: f.sampleAFile.path)
        f.appState.saveAndContinuePendingLibrarySelectionChange()
        #expect(lib.librarySelectedSampleId == "A")
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: f.sampleAFile.path)

        f.appState.saveAndContinuePendingLibrarySelectionChange()

        #expect(try String(contentsOf: f.sampleAFile, encoding: .utf8).contains("edited-tag"))
        #expect(lib.librarySelectedSampleId == "C")
        #expect(!lib.hasPendingSelectionChange())
    }
}
