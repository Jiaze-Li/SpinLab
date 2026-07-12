import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.1.2 Routing Draft", .serialized)
struct V212RoutingDraftTests {
    @Test("save routing draft recomputes route with new default sample")
    func saveRoutingDraftRecomputesWithDefaultSample() {
        let pending = makePendingImport()
        let persistence = MockPersistenceForRoutingDraft(pendingImports: [pending])
        let appState = SpinLabAppState(
            persistence: persistence,
            libraryArchiveScan: LibraryArchiveScanService(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("spinlab-routing-draft-\(UUID().uuidString)", isDirectory: true))
        )
        // SpinLabAppState.init reconfigures the global RuleLoader from its own
        // (unconfigured-in-tests) RulesBookSettings, so the bundled Rules Book
        // must be applied after construction to take effect.
        let savedPaths = configureBundledRules()
        defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }
        appState.refreshPendingDrawerMatches()

        let before = appState.pendingRoutePlan(for: pending)
        #expect(before.targets.first?.sampleId == "PN41||STO|001")

        var draft = appState.routingDraft(for: pending)
        draft.fileSampleKey = "PN40"
        appState.saveRoutingDraft(draft, for: pending.id)

        let after = appState.pendingRoutePlan(for: pending)
        #expect(after.targets.first?.sampleId == "PN40||STO|001")
    }

    @Test("channel sample override takes precedence for that channel token")
    func channelSampleOverrideTakesPrecedence() {
        let pending = makePendingImport()
        let persistence = MockPersistenceForRoutingDraft(pendingImports: [pending])
        let appState = SpinLabAppState(
            persistence: persistence,
            libraryArchiveScan: LibraryArchiveScanService(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("spinlab-routing-draft-\(UUID().uuidString)", isDirectory: true))
        )

        var draft = appState.routingDraft(for: pending)
        draft.fileSampleKey = "PN40"
        draft.channelSampleKeyOverrides["ch2"] = "PN14"
        appState.saveRoutingDraft(draft, for: pending.id)

        let plan = appState.pendingRoutePlan(for: pending)
        #expect(plan.targets.first?.sampleId == "PN14")
        #expect(plan.unresolvedChannels.isEmpty)
    }

    @Test("routing draft dirty flag reflects unsaved changes")
    func routingDraftDirtyState() {
        let pending = makePendingImport()
        let persistence = MockPersistenceForRoutingDraft(pendingImports: [pending])
        let appState = SpinLabAppState(
            persistence: persistence,
            libraryArchiveScan: LibraryArchiveScanService(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("spinlab-routing-draft-\(UUID().uuidString)", isDirectory: true))
        )

        var draft = appState.routingDraft(for: pending)
        #expect(appState.isRoutingDraftDirty(draft, for: pending) == false)

        draft.fileSampleKey = "PN40"
        #expect(appState.isRoutingDraftDirty(draft, for: pending) == true)

        appState.saveRoutingDraft(draft, for: pending.id)
        #expect(appState.isRoutingDraftDirty(draft, for: pending) == false)
    }

    @Test("revert to parsed baseline restores original route")
    func revertToParsedBaselineRestoresRoute() {
        let pending = makePendingImport()
        let persistence = MockPersistenceForRoutingDraft(pendingImports: [pending])
        let appState = SpinLabAppState(
            persistence: persistence,
            libraryArchiveScan: LibraryArchiveScanService(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("spinlab-routing-draft-\(UUID().uuidString)", isDirectory: true))
        )
        let savedPaths = configureBundledRules()
        defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }

        var draft = appState.routingDraft(for: pending)
        draft.fileSampleKey = "PN40"
        appState.saveRoutingDraft(draft, for: pending.id)
        #expect(appState.pendingRoutePlan(for: pending).targets.first?.sampleId == "PN40||STO|001")

        let baseline = appState.routingDraftBaseline(for: pending)
        appState.saveRoutingDraft(baseline, for: pending.id)
        #expect(appState.pendingRoutePlan(for: pending).targets.first?.sampleId == "PN41||STO|001")
    }

    @Test("routing draft in interaction snapshot is ignored on app launch")
    func routingDraftSnapshotIsIgnoredOnLaunch() {
        let pending = makePendingImport()
        let persistence = MockPersistenceForRoutingDraft(pendingImports: [pending])
        persistence.interactionSnapshotValue.inboxWorkspaceByPendingID[pending.id.uuidString.lowercased()] = InboxPendingWorkspaceState.snapshotSafe(
            draft: PendingImportConfirmationDraft(
                batchName: "",
                sampleName: "",
                measurementName: "RT",
                workflowID: "RT",
                conditionValues: [:],
                selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
                newProjectName: ""
            ),
            editableFileContents: "",
            hasEditableFileContents: false,
            routingDraft: PendingRoutingDraft(fileSampleKey: "PN40", channelSampleKeyOverrides: ["ch2": ""])
        )

        let appState = SpinLabAppState(
            persistence: persistence,
            libraryArchiveScan: LibraryArchiveScanService(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("spinlab-routing-draft-\(UUID().uuidString)", isDirectory: true))
        )
        let savedPaths = configureBundledRules()
        defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }
        appState.refreshPendingDrawerMatches()

        let plan = appState.pendingRoutePlan(for: pending)
        #expect(plan.targets.first?.sampleId == "PN41||STO|001")
        #expect(appState.hasSavedRoutingDraft(for: pending) == false)
    }

    @Test("saved draft marker is false before save and true after save")
    func savedDraftMarkerState() {
        let pending = makePendingImport()
        let persistence = MockPersistenceForRoutingDraft(pendingImports: [pending])
        let appState = SpinLabAppState(
            persistence: persistence,
            libraryArchiveScan: LibraryArchiveScanService(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("spinlab-routing-draft-\(UUID().uuidString)", isDirectory: true))
        )

        #expect(appState.hasSavedRoutingDraft(for: pending) == false)

        var draft = appState.routingDraft(for: pending)
        draft.fileSampleKey = "PN40"
        appState.saveRoutingDraft(draft, for: pending.id)

        #expect(appState.hasSavedRoutingDraft(for: pending) == true)
    }

    @Test("routing draft baseline is initialized with sample-level precision")
    func routingDraftBaselineUsesSampleIdentity() {
        let pending = makePendingImport()
        let persistence = MockPersistenceForRoutingDraft(pendingImports: [pending])
        let appState = SpinLabAppState(
            persistence: persistence,
            libraryArchiveScan: LibraryArchiveScanService(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("spinlab-routing-draft-\(UUID().uuidString)", isDirectory: true))
        )
        let savedPaths = configureBundledRules()
        defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }

        let baseline = appState.routingDraftBaseline(for: pending)
        #expect(baseline.fileSampleKey == "PN41")
        #expect(baseline.channelSampleKeyOverrides["ch2"] == "")
    }

    @Test("channel sample override updates channel token directly")
    func channelSampleOverrideUpdatesToken() {
        let pending = SpinLabDomain.PendingImport(
            fileName: "RT_1mA_ch1_ch2_ch3_AMR.dat",
            sourceFilePath: "/tmp/RT_1mA_ch1_ch2_ch3_AMR.dat",
            originalFilePath: "/tmp/RT_1mA_ch1_ch2_ch3_AMR.dat",
            parsedHints: SpinLabDomain.ParsedFilenameHints(
                fileSampleKey: "PN41|o|STO|111",
                channelHints: [
                    SpinLabDomain.ParsedChannelHint(channel: "ch1", sampleID: "PN41|o|STO|111", tags: ["o", "STO111"]),
                    SpinLabDomain.ParsedChannelHint(channel: "ch2", sampleID: "PN44|o|STO|111", tags: ["o", "STO111"]),
                    SpinLabDomain.ParsedChannelHint(channel: "ch3", sampleID: "PN48|o|STO|111", tags: ["o", "STO111"])
                ],
                substrateTags: ["o", "STO111"]
            )
        )
        let persistence = MockPersistenceForRoutingDraft(pendingImports: [pending])
        let appState = SpinLabAppState(
            persistence: persistence,
            libraryArchiveScan: LibraryArchiveScanService(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("spinlab-routing-draft-\(UUID().uuidString)", isDirectory: true))
        )

        let baseline = appState.routingDraftBaseline(for: pending)
        #expect(baseline.fileSampleKey == "PN41|o|STO|111")
        #expect(baseline.channelSampleKeyOverrides["ch1"] == "PN41|o|STO|111")
        #expect(baseline.channelSampleKeyOverrides["ch2"] == "PN44|o|STO|111")
        #expect(baseline.channelSampleKeyOverrides["ch3"] == "PN48|o|STO|111")

        var draft = appState.routingDraft(for: pending)
        draft.channelSampleKeyOverrides["ch2"] = "PN44|HF|STO|111"
        appState.saveRoutingDraft(draft, for: pending.id)

        let plan = appState.pendingRoutePlan(for: pending)
        let ch2 = plan.channelResolutions.first { $0.channel == "ch2" }
        #expect(ch2?.sampleId == "PN44|HF|STO|111")
        #expect(plan.conflicts.isEmpty)
    }

    private func makePendingImport() -> SpinLabDomain.PendingImport {
        SpinLabDomain.PendingImport(
            fileName: "RT_1mA_ch2_AMR.dat",
            sourceFilePath: "/tmp/RT_1mA_ch2_AMR.dat",
            originalFilePath: "/tmp/RT_1mA_ch2_AMR.dat",
            parsedHints: SpinLabDomain.ParsedFilenameHints(
                fileSampleKey: "PN41",
                channelHints: [
                    SpinLabDomain.ParsedChannelHint(channel: "ch2", sampleID: nil, tags: ["STO001"])
                ],
                substrateTags: ["STO001"]
            )
        )
    }

    /// SpinLabAppState's own init unconditionally re-runs RuleLoader.configure using its
    /// (test-default, unconfigured) RulesBookSettings — so tests that need real substrate
    /// resolution (e.g. "STO001" -> STO|001) must reconfigure the bundled Rules Book *after*
    /// constructing SpinLabAppState. Returns the previously-configured book paths so callers
    /// can restore them in a `defer`.
    @discardableResult
    private func configureBundledRules() -> RulesConfigPaths? {
        let bundledDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SpinLabApp/config")
        let savedPaths = RuleLoader.currentBookPaths
        RuleLoader.configure(bookPaths: RulesConfigPaths(configDirectoryURL: bundledDir), internalPaths: AppInternalPaths())
        _ = RuleLoader.shared.reloadCached()
        return savedPaths
    }
}

private final class MockPersistenceForRoutingDraft: SpinLabPersistence {
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
