import Foundation
import Testing
@testable import SpinLabApp

/// Regression coverage for two Codex findings on the Library browser/drawer
/// selection-ownership split:
///
/// 1. Browser-focused Detail must be read-only. All Detail mutations target
///    Drawer-owned state, so they must be guarded by one coherent permission
///    concept (`canMutateLibraryDetailSelection`) rather than scattered
///    ad-hoc checks — an accidentally-exposed UI callback must not be able
///    to mutate the Drawer sample while Browser owns Detail focus.
/// 2. Drawer dirty-edit deferral must answer only one question: will this
///    operation change the Drawer sample being edited? Browser navigation
///    never changes Drawer identity, so it must bypass the dirty guard
///    entirely and must never clear the Drawer's edit draft.
@MainActor
@Suite("V5.7.0 Library Detail Mutation Scope + Dirty-Edit Guard")
struct V570LibraryDetailMutationAndDirtyGuardTests {

    // MARK: - 1. Browser-focused Detail: read-only projection, no mutation permission

    @Test("Browser A + Drawer B: Detail resolves to A, mutation permission is false")
    func browserFocused_readOnlyProjection_noMutationPermission() {
        let store = TestFixtures.makeStore()
        store.librarySelectedPrefix = "STO"
        store.librarySelectedBatchId = "B1"
        store.librarySelectedSampleId = "B"

        store.libraryBrowserSelectedPrefix = "PN20"
        store.libraryBrowserSelectedBatchId = "PN20-A"
        store.libraryBrowserSelectedSampleId = "A"

        store.libraryActiveSelectionSource = .browser

        #expect(store.currentSelectionSampleId == "A")
        #expect(!store.canMutateLibraryDetailSelection)
        #expect(!store.canEditSelectedLibrarySample)
    }

    // MARK: - 2. Drawer-focused Detail: mutation permission true, Drawer is the target

    @Test("Drawer B focused: mutation permission is true, Drawer remains the mutation target")
    func drawerFocused_mutationPermissionTrue_drawerIsTarget() {
        let store = TestFixtures.makeStore()
        let sample = TestFixtures.makeSample(id: "B", batchId: "B1")
        store.libraryExistingGroups = [
            "STO": [LibraryPreviewBatchGroup(batchId: "B1", samples: [sample])]
        ]
        store.librarySelectedPrefix = "STO"
        store.librarySelectedBatchId = "B1"
        store.librarySelectedSampleId = "B"
        store.libraryActiveSelectionSource = .drawer

        store.libraryBrowserSelectedPrefix = "PN20"
        store.libraryBrowserSelectedBatchId = "PN20-A"
        store.libraryBrowserSelectedSampleId = "A"

        #expect(store.canMutateLibraryDetailSelection)
        // The mutation target is resolved from the Drawer triple, never Browser.
        #expect(store.selectedExistingDrawerSample()?.id == "B")
        #expect(store.currentSelectionSampleId == "B")
    }

    // MARK: - 3. Drawer B dirty → Browser A: no prompt, Drawer B draft survives unchanged

    @Test("Drawer B dirty → Browser A: no dirty prompt, Browser becomes A, Drawer B draft survives")
    func drawerDirty_browserNavigation_noPromptDraftSurvives() {
        let store = TestFixtures.makeStore()
        store.librarySelectedPrefix = "STO"
        store.librarySelectedBatchId = "B1"
        store.librarySelectedSampleId = "B"
        store.libraryActiveSelectionSource = .drawer

        let draft = TestFixtures.makeDraft(sampleId: "B", substrateTagsText: "dirty")
        let original = TestFixtures.makeDraft(sampleId: "B", substrateTagsText: "clean")
        store.librarySampleEditDraft = draft
        store.libraryState.sampleEditOriginalDraft = original
        #expect(store.librarySampleEditIsDirty)

        store.libraryBrowserSelectedPrefix = "PN20"
        store.libraryBrowserSelectedBatchId = "PN20-A"
        store.libraryBrowserSelectedSampleId = "A"

        let outcome = store.selectBrowserSample()

        guard case .appliedBrowser = outcome else {
            Issue.record("Expected .appliedBrowser (Browser navigation must bypass the dirty guard), got \(outcome)")
            return
        }
        #expect(!store.hasPendingSelectionChange())
        #expect(store.libraryPendingSelectionChangePrompt == nil)
        #expect(store.libraryActiveSelectionSource == .browser)

        // Drawer selection untouched.
        #expect(store.librarySelectedPrefix == "STO")
        #expect(store.librarySelectedBatchId == "B1")
        #expect(store.librarySelectedSampleId == "B")

        // Draft survives, unchanged and still dirty.
        #expect(store.librarySampleEditDraft?.sampleId == "B")
        #expect(store.librarySampleEditDraft?.substrateTagsText == "dirty")
        #expect(store.librarySampleEditIsDirty)
    }

    // MARK: - 4. Drawer B dirty → Drawer C: deferred, prompt appears, Drawer stays B

    @Test("Drawer B dirty → Drawer C: selection change deferred, prompt appears, Drawer stays B")
    func drawerDirty_drawerNavigationDifferentSample_defersWithPrompt() {
        let store = TestFixtures.makeStore()
        store.librarySelectedPrefix = "STO"
        store.librarySelectedBatchId = "B1"
        store.librarySelectedSampleId = "B"
        store.libraryActiveSelectionSource = .drawer

        let draft = TestFixtures.makeDraft(sampleId: "B", substrateTagsText: "dirty")
        let original = TestFixtures.makeDraft(sampleId: "B", substrateTagsText: "clean")
        store.librarySampleEditDraft = draft
        store.libraryState.sampleEditOriginalDraft = original

        let outcome = store.selectExistingDrawer(prefix: "STO", batchId: "B1", sampleId: "C")

        guard case .deferred = outcome else {
            Issue.record("Expected .deferred, got \(outcome)")
            return
        }
        #expect(store.hasPendingSelectionChange())
        #expect(store.libraryPendingSelectionChangePrompt != nil)

        // Drawer selection has not moved yet.
        #expect(store.librarySelectedSampleId == "B")
        #expect(store.libraryActiveSelectionSource == .drawer)
        #expect(store.librarySampleEditDraft?.sampleId == "B")
    }

    // MARK: - 5. Drawer B dirty → Browser A → Drawer B: no prompt either way, draft survives, edit continues

    @Test("Drawer B dirty → Browser A → Drawer B: no prompt for either transition, draft survives")
    func drawerDirty_browserThenBackToSameDrawer_noPromptEitherWay() {
        let store = TestFixtures.makeStore()
        let sample = TestFixtures.makeSample(id: "B", batchId: "B1")
        store.libraryExistingGroups = [
            "STO": [LibraryPreviewBatchGroup(batchId: "B1", samples: [sample])]
        ]
        store.librarySelectedPrefix = "STO"
        store.librarySelectedBatchId = "B1"
        store.librarySelectedSampleId = "B"
        store.libraryActiveSelectionSource = .drawer

        let draft = TestFixtures.makeDraft(sampleId: "B", substrateTagsText: "dirty")
        let original = TestFixtures.makeDraft(sampleId: "B", substrateTagsText: "clean")
        store.librarySampleEditDraft = draft
        store.libraryState.sampleEditOriginalDraft = original

        store.libraryBrowserSelectedPrefix = "PN20"
        store.libraryBrowserSelectedBatchId = "PN20-A"
        store.libraryBrowserSelectedSampleId = "A"

        // Browser A
        _ = store.selectBrowserSample()
        #expect(!store.hasPendingSelectionChange())
        #expect(store.librarySampleEditDraft?.sampleId == "B")

        // Back to Drawer B (identical drawer identity — a no-op reselect)
        let outcome = store.selectExistingDrawer(prefix: "STO", batchId: "B1", sampleId: "B")

        guard case .appliedDrawer = outcome else {
            Issue.record("Expected .appliedDrawer (same-identity reselect must not defer), got \(outcome)")
            return
        }
        #expect(!store.hasPendingSelectionChange())
        #expect(store.libraryPendingSelectionChangePrompt == nil)
        #expect(store.libraryActiveSelectionSource == .drawer)

        // Original dirty draft survives and editing can continue.
        #expect(store.librarySampleEditDraft?.sampleId == "B")
        #expect(store.librarySampleEditDraft?.substrateTagsText == "dirty")
        #expect(store.librarySampleEditIsDirty)
    }

    // MARK: - 6. Browser-focused Detail cannot invoke a Drawer-targeted destructive mutation (disk-real)

    @Test("Browser-focused deleteAppliedMeasurement is a no-op; Drawer-focused deletes for real")
    func browserFocused_deleteAppliedMeasurement_isNoOp_diskReal() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(
            path: "v570-detail-mutation-scope-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let sampleDir = root.appending(path: "batches/STO/B1/samples/B/measurements/AHE")
        try fm.createDirectory(at: sampleDir, withIntermediateDirectories: true)
        let dataFileURL = sampleDir.appending(path: "run1.dat")
        try Data("measurement data".utf8).write(to: dataFileURL)
        let sidecarURL = sampleDir.appending(path: "run1.dat.spinlab.json")
        let sidecar = SpinLabFileSidecar(
            workflow: "AHE",
            workflowDisplayName: "AHE",
            channels: [],
            sourceFilePath: "/original/run1.dat",
            appliedAt: Date(),
            ruleSnapshot: SidecarRuleSnapshot(
                ruleSetVersion: 0,
                ruleSetFingerprint: "test:fixture",
                appliedAt: Date(),
                fields: SidecarRuleFields(sampleID: nil, conditions: [:], substrateTags: [])
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(sidecar).write(to: sidecarURL)

        let measurement = AppliedMeasurement(
            id: sidecarURL.path,
            workflow: "AHE",
            workflowDisplayName: "AHE",
            conditions: [:],
            appliedAt: Date(),
            sourceFileName: "run1.dat"
        )

        let store = TestFixtures.makeStore()
        store.librarySettings.rootPath = root.path
        store.librarySelectedPrefix = "STO"
        store.librarySelectedBatchId = "B1"
        store.librarySelectedSampleId = "B"

        // Browser-focused: Detail may be displaying a different (Browser) sample,
        // but the mutation callback still targets Drawer B's measurement. It must
        // not fire at all.
        store.libraryActiveSelectionSource = .browser
        store.deleteAppliedMeasurement(measurement)
        #expect(fm.fileExists(atPath: sidecarURL.path), "Browser-focused Detail must not delete the Drawer-owned measurement")
        #expect(fm.fileExists(atPath: dataFileURL.path))

        // Drawer-focused: the same call now legitimately targets Drawer B.
        store.libraryActiveSelectionSource = .drawer
        store.deleteAppliedMeasurement(measurement)
        #expect(!fm.fileExists(atPath: sidecarURL.path), "Drawer-focused Detail must be able to delete its own measurement")
        #expect(!fm.fileExists(atPath: dataFileURL.path))
    }

    // MARK: - 7. Browser-focused createMeasurementSet is a no-op (in-memory)

    @Test("Browser-focused createMeasurementSet does not mutate Drawer's measurement sets")
    func browserFocused_createMeasurementSet_isNoOp() {
        let store = TestFixtures.makeStore()
        let sample = TestFixtures.makeSample(id: "B", batchId: "B1")
        store.libraryExistingGroups = [
            "STO": [LibraryPreviewBatchGroup(batchId: "B1", samples: [sample])]
        ]
        store.librarySettings.rootPath = FileManager.default.temporaryDirectory.path
        store.librarySelectedPrefix = "STO"
        store.librarySelectedBatchId = "B1"
        store.librarySelectedSampleId = "B"
        store.libraryActiveSelectionSource = .browser

        store.createMeasurementSet(name: "New Set", workflow: "AHE", initialMember: nil)

        let unchanged = store.libraryExistingGroups["STO"]?
            .first(where: { $0.batchId == "B1" })?
            .samples
            .first(where: { $0.id == "B" })
        #expect(unchanged?.measurementSets.isEmpty == true)
    }

    // MARK: - 8. Browser-focused deleteMetricRecord is a no-op (disk-real)

    @Test("Browser-focused deleteMetricRecord does not touch Drawer's measurement_data.json")
    func browserFocused_deleteMetricRecord_isNoOp_diskReal() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(
            path: "v570-detail-mutation-scope-metric-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let record = WorkbenchMetricRecord(
            recordID: UUID().uuidString,
            sampleKey: "B",
            displayKey: "B",
            workflowID: "AHE",
            metric: "Hc",
            value: 0.05,
            canonicalUnit: "T",
            conditions: [:],
            generatedAt: Date(timeIntervalSince1970: 1_712_146_400),
            runID: UUID().uuidString,
            overrideInfo: nil
        )
        var dataStore = WorkbenchMeasurementDataStore()
        dataStore.append(record)

        let dir = root.appending(path: "samples/B/_spinlab", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(dataStore).write(to: dir.appending(path: "measurement_data.json"))

        let identityKey = WorkbenchMetricIdentity.makeIdentityKey(
            sampleKey: "B", workflowID: "AHE", metric: "Hc", conditions: [:]
        )

        let store = TestFixtures.makeStore()
        store.librarySettings.rootPath = root.path
        store.librarySelectedPrefix = "STO"
        store.librarySelectedBatchId = "B1"
        store.librarySelectedSampleId = "B"

        store.libraryActiveSelectionSource = .browser
        store.deleteMetricRecord(identityKey: identityKey)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stillThere = try decoder.decode(
            WorkbenchMeasurementDataStore.self,
            from: Data(contentsOf: dir.appending(path: "measurement_data.json"))
        )
        #expect(stillThere.records.count == 1, "Browser-focused Detail must not delete the Drawer-owned metric record")

        store.libraryActiveSelectionSource = .drawer
        store.deleteMetricRecord(identityKey: identityKey)

        let afterDrawerDelete = try decoder.decode(
            WorkbenchMeasurementDataStore.self,
            from: Data(contentsOf: dir.appending(path: "measurement_data.json"))
        )
        #expect(afterDrawerDelete.records.isEmpty, "Drawer-focused Detail must be able to delete its own metric record")
    }
}

// MARK: - Test fixtures

private enum TestFixtures {
    @MainActor
    static func makeStore() -> LibraryFeatureStore {
        let store = LibraryFeatureStore()
        store.librarySettings.rootPath = nil
        return store
    }

    static func makeSample(id: String, batchId: String) -> LibrarySample {
        LibrarySample(
            id: id,
            displayName: id,
            batchId: batchId,
            substrateRaw: "",
            substrateDisplay: "",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            updatedAt: Date()
        )
    }

    static func makeDraft(sampleId: String, substrateTagsText: String) -> LibrarySampleEditDraft {
        LibrarySampleEditDraft(
            sampleId: sampleId,
            batchId: "B1",
            baseUpdatedAt: Date(),
            substrateTagsText: substrateTagsText,
            numericValues: [],
            metadataValues: []
        )
    }
}
