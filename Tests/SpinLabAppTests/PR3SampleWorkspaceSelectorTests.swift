import Foundation
import Testing
@testable import SpinLabApp

/// PR 3 phase 1 — Sample Workspace selector.
@MainActor
@Suite("PR3 Sample Workspace selector", .serialized, .rulesGlobalState)
struct PR3SampleWorkspaceSelectorTests {

    private func sample(_ id: String, name: String? = nil, batch: String = "PN1", substrate: String = "STO") -> LibrarySample {
        LibrarySample(
            id: id, displayName: name ?? id, batchId: batch, substrateRaw: substrate, substrateDisplay: substrate,
            substrateTokens: [], substrateTags: [], metadata: [:], numericTags: [:],
            numericDisplay: [:], updatedAt: Date()
        )
    }

    @Test("selector style adapts to sample count", arguments: [(0, LibrarySampleSelectorModel.Style.empty), (1, .single), (2, .chips), (6, .chips), (7, .menu), (40, .menu)])
    func styleByCount(count: Int, expected: LibrarySampleSelectorModel.Style) {
        let samples = (0..<count).map { sample("S\($0)") }
        #expect(LibrarySampleSelectorModel(samples: samples).style == expected)
    }

    @Test("duplicate titles are disambiguated by sample key; unique titles are not")
    func disambiguation() {
        let m = LibrarySampleSelectorModel(samples: [
            sample("PN1/a", name: "STO"), sample("PN1/b", name: "STO"), sample("PN1/c", name: "LAO")
        ])
        #expect(m.options[0].subtitle == "PN1/a")
        #expect(m.options[1].subtitle == "PN1/b")
        #expect(m.options[2].subtitle == nil)
    }

    @Test("empty display name falls back to substrate then key")
    func titleFallback() {
        #expect(LibrarySampleSelectorModel.baseTitle(for: sample("k", name: " ", substrate: "LAO")) == "LAO")
        #expect(LibrarySampleSelectorModel.baseTitle(for: sample("k", name: "", substrate: "")) == "k")
    }

    @Test("menu filter matches title and key case-insensitively")
    func filtering() {
        let m = LibrarySampleSelectorModel(samples: (0..<8).map { sample("PN1/s\($0)", name: "Film \($0)") })
        #expect(m.filtered(by: "").count == 8)
        #expect(m.filtered(by: "film 3").map(\.id) == ["PN1/s3"])
        #expect(m.filtered(by: "PN1/S7").map(\.id) == ["PN1/s7"])
        #expect(m.filtered(by: "zzz").isEmpty)
    }

    @Test("selection outside the batch is invalid, never substituted")
    func validity() {
        let m = LibrarySampleSelectorModel(samples: [sample("a"), sample("b")])
        #expect(m.isValidSelection("a"))
        #expect(!m.isValidSelection("other-batch-sample"))
        #expect(!m.isValidSelection(nil))
    }

    @Test("Batch entry auto-selects the first sample; switching goes through the guarded route")
    func batchEntryAndSwitch() {
        let s = SpinLabAppState()
        let lib = s.library
        lib.librarySettings.rootPath = nil
        lib.libraryExistingGroups = ["PN": [
            LibraryPreviewBatchGroup(batchId: "PN1", samples: [sample("PN1-a"), sample("PN1-b")]),
            LibraryPreviewBatchGroup(batchId: "PN2", samples: [])
        ]]
        s.selectedArea = .library
        s.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN1", sampleId: nil))
        #expect(lib.librarySelectedSampleId == "PN1-a")
        #expect(lib.currentRoute == .sampleWorkspace(prefix: "PN", batchId: "PN1"))

        s.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN1", sampleId: "PN1-b"))
        #expect(lib.librarySelectedSampleId == "PN1-b")

        func draft(_ t: String) -> LibrarySampleEditDraft {
            LibrarySampleEditDraft(sampleId: "PN1-b", batchId: "PN1", baseUpdatedAt: Date(), substrateTagsText: t,
                                   numericValues: [], metadataValues: [])
        }
        lib.libraryState.sampleEditOriginalDraft = draft("clean")
        lib.librarySampleEditDraft = draft("dirty")
        s.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN1", sampleId: "PN1-a"))
        #expect(lib.librarySelectedSampleId == "PN1-b", "dirty draft defers the switch")
    }

    @Test("an unknown sample never selects a different batch's sample")
    func unknownSampleDegrades() {
        let s = SpinLabAppState()
        let lib = s.library
        lib.librarySettings.rootPath = nil
        lib.libraryExistingGroups = ["PN": [LibraryPreviewBatchGroup(batchId: "PN1", samples: [sample("PN1-a")])]]
        s.selectedArea = .library
        s.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN1", sampleId: "ghost"))
        #expect(lib.librarySelectedSampleId != "ghost")
        #expect(lib.currentRoute == .management)
    }

    // MARK: - Phase 2 structure

    private func source(_ rel: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
    }

    @Test("Sample Workspace Primary hosts the plots grid and no management/search/publish controls; Detail no longer hosts it")
    func primaryOwnsPlotsDetailDoesNot() throws {
        let primary = try source("Sources/SpinLabApp/Features/Library/LibrarySampleWorkspacePrimaryView.swift")
        #expect(primary.contains("SamplePlotsOverviewSection("))
        for forbidden in ["LibrarySettingsSectionView", "RegistryWorkspaceSectionView", "publishWebLibrary", "syncLibraryBackup", "searchWorkspace"] {
            #expect(!primary.contains(forbidden), "\(forbidden) must not appear in the Sample Workspace page")
        }
        let detail = try source("Sources/SpinLabApp/Features/Library/LibraryDetailView.swift")
        #expect(!detail.contains("SamplePlotsOverviewSection("))
        #expect(detail.contains("MeasurementDataSectionView("))
        #expect(detail.contains("LibraryMeasurementsDoneSection("))
    }

    @Test("Sample switching writes no selection directly; it uses the guarded transaction")
    func selectorUsesTransaction() throws {
        let primary = try source("Sources/SpinLabApp/Features/Library/LibrarySampleWorkspacePrimaryView.swift")
        #expect(primary.contains("selectExistingDrawer("))
        #expect(!primary.contains("librarySelectedSampleId = "))
        #expect(!primary.contains("librarySelectedBatchId = "))
    }
}
