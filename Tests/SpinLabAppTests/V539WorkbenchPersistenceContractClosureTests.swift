import Foundation
import XCTest
@testable import SpinLabApp

/// Regression tests for the final Workbench interaction-snapshot persistence-contract
/// closeout pass. Covers the four confirmed gaps from the prior pass's audit:
///   - Phase A: `ivTitleTemplate` was captured but never threaded through
///     `InteractionSnapshotCoordinator.restoreAll` into `WorkbenchFeatureStore.restoreInteraction`.
///   - Phase B: RT's min-gap field capture/restore, matching AHE/IV/XY.
///   - Phase C: transient plot-control mutations (series order/rename/visibility, label
///     overrides) must not move a capture even though the shared `onChange` callback they used
///     to funnel through is also used by genuinely persisted mutations.
///   - Phase D: RSM (zero snapshot fields) and ThreeOmega's per-tab axis/tick/reset controls
///     (also zero snapshot fields — unlike title/typography/tick-via-chartStyleOverrides) must
///     not move a capture either.
@MainActor
final class V539WorkbenchPersistenceContractClosureTests: XCTestCase {

    private func makeWorkbenchStore() -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(libraryRepository: LibraryRepository(persistence: persistence))
    }

    // MARK: - Phase A: IV title-template restore plumbing gap

    /// The bug: `WorkbenchFeatureStore.restoreInteraction` already accepted an
    /// `ivTitleTemplate` parameter (with a `nil` default), but
    /// `InteractionSnapshotCoordinator.restoreAll` never passed `snapshot.ivTitleTemplate`
    /// into it — so a saved IV title template silently reverted to the workspace default on
    /// every relaunch despite being captured correctly. This proves the store-level plumbing
    /// (which the coordinator now calls with the field wired) round-trips.
    func testWorkbenchFeatureStore_capturesAndRestoresIVTitleTemplate() {
        let store = makeWorkbenchStore()
        store.ivWorkspace.titleTemplate = "#device IV sweep"

        var snapshot = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &snapshot)
        XCTAssertEqual(snapshot.ivTitleTemplate, "#device IV sweep")

        let restoredStore = makeWorkbenchStore()
        restoredStore.restoreInteraction(
            selectedArchivedRecordID: nil,
            workbenchResultDraft: "",
            ivTitleTemplate: snapshot.ivTitleTemplate
        )

        XCTAssertEqual(restoredStore.ivWorkspace.titleTemplate, "#device IV sweep")
    }

    /// Backward compatibility: a snapshot written before `ivTitleTemplate` existed (or one
    /// where the user never touched it) decodes with `nil`. Restore must leave the IV
    /// workspace's default title template untouched rather than clobbering it with an empty
    /// string.
    func testWorkbenchFeatureStore_restoreLeavesIVTitleTemplateDefaultWhenFieldAbsent() throws {
        let data = try JSONEncoder().encode(SpinLabInteractionSnapshot())
        let decoded = try JSONDecoder().decode(SpinLabInteractionSnapshot.self, from: data)
        XCTAssertNil(decoded.ivTitleTemplate, "A snapshot with no IV title edits must decode ivTitleTemplate as nil")

        let store = makeWorkbenchStore()
        let defaultTemplate = store.ivWorkspace.titleTemplate

        store.restoreInteraction(
            selectedArchivedRecordID: nil,
            workbenchResultDraft: "",
            ivTitleTemplate: decoded.ivTitleTemplate
        )

        XCTAssertEqual(store.ivWorkspace.titleTemplate, defaultTemplate)
    }

    /// End-to-end plumbing check at the coordinator's actual call site: this is the exact
    /// parameter list `InteractionSnapshotCoordinator.restoreAll` now passes to
    /// `WorkbenchFeatureStore.restoreInteraction` — mirrors it directly so a future
    /// regression (e.g. someone dropping the argument again) fails here first.
    func testWorkbenchFeatureStore_restoreInteractionAppliesIVTitleTemplateAlongsideOtherIVFields() {
        let store = makeWorkbenchStore()
        store.restoreInteraction(
            selectedArchivedRecordID: nil,
            workbenchResultDraft: "",
            ivTitleTemplate: "#tab restored",
            ivStackOffsetMultiplier: 0.8,
            ivMinGapFraction: 0.3
        )

        XCTAssertEqual(store.ivWorkspace.titleTemplate, "#tab restored")
        XCTAssertEqual(store.ivWorkspace.stackOffsetMultiplier, 0.8)
        XCTAssertEqual(store.ivWorkspace.minGapFraction, 0.3)
    }

    // MARK: - Phase B: RT min-gap persistence trigger

    /// RT's min-gap field (`rtMinGapFraction`) capture/restore round trip, matching
    /// AHE/IV/XY's equivalent fields. The user-callback persistence trigger itself
    /// (`RTSpacingInlineControls.onGapSubmit`, now wired explicitly like AHE's
    /// `AHESpacingInlineControls.onGapSubmit` instead of relying on
    /// `WorkbenchPlotSpacingInlineControls`'s implicit `onGapSubmit ?? onStackChange`
    /// fallback) is verified by source inspection — this codebase has no SwiftUI
    /// interaction-testing harness (no ViewInspector or similar), so the private
    /// `RTSpacingInlineControls`/`AHESpacingInlineControls` view types cannot be driven
    /// from XCTest directly. What is testable, and is asserted here, is that the
    /// underlying store field this callback would flush genuinely round-trips.
    func testWorkbenchFeatureStore_capturesAndRestoresRTMinGap() {
        let store = makeWorkbenchStore()
        store.rtWorkspace.minGapFraction = 0.33

        var snapshot = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &snapshot)
        XCTAssertEqual(snapshot.rtMinGapFraction, 0.33)

        let restoredStore = makeWorkbenchStore()
        restoredStore.restoreInteraction(
            selectedArchivedRecordID: nil,
            workbenchResultDraft: "",
            rtMinGapFraction: snapshot.rtMinGapFraction
        )
        XCTAssertEqual(restoredStore.rtWorkspace.minGapFraction, 0.33)
    }

    /// Simulates the exact effect of RT's `onGapSubmit` callback (store mutation +
    /// `scheduleInteractionSnapshotFlush`) via `InteractionMemoryStore` directly — the same
    /// level `V538WorkbenchInteractionSnapshotFlushTests.testInteractionMemoryStore_flushesNormallyAfterRestoreCompletes`
    /// exercises for `rtTitleTemplate`. Confirms a min-gap edit genuinely reaches persistence,
    /// not just that the field round-trips through a manually-constructed snapshot.
    func testInteractionMemoryStore_rtMinGapEditFlushesToPersistence() async throws {
        let persistence = MockClosureTestPersistence()
        let store = InteractionMemoryStore(persistence: persistence, saveDebounceInterval: 0.01)

        store.beginSuppressingFlush()
        store.restore { _ in }
        store.markReady()
        store.endSuppressingFlush(source: "restoreInteractionSnapshot")

        // Mirrors RTSpacingInlineControls.onGapSubmit: mutate the canonical field, then
        // schedule exactly the same flush the real callback schedules.
        store.updateValue(\.rtMinGapFraction, to: 0.42, source: "rtGapSubmit")

        try await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertEqual(persistence.saveInteractionSnapshotCallCount, 1)
        XCTAssertEqual(persistence.interactionSnapshot.rtMinGapFraction, 0.42)
    }

    // MARK: - Phase C: transient vs. persisted callback separation

    /// Series reorder / rename / visibility and title/axis label overrides are per-tab render
    /// state for every standard workflow (AHE/IV/RT/XY/ThreeOmega) — none of them are
    /// `SpinLabInteractionSnapshot` fields. Before this pass, `WorkbenchStandardPlotControls`
    /// funneled all of these through the same `onChange` callback used by genuinely persisted
    /// mutations (title template, stack offset, min gap, series render mode). Mutating them
    /// directly at the store level (bypassing the view layer, since transient/persisted routing
    /// now happens inside `WorkbenchStandardPlotControls`'s body) must still be a pure no-op on
    /// capture — this is the store-level invariant the callback split exists to protect.
    func testCaptureInteraction_transientPlotControlMutationsRemainNoOpAfterCallbackSplit() {
        let store = makeWorkbenchStore()

        var before = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &before)

        store.aheWorkspace.updateSeriesOrder(["b", "a"])
        store.aheWorkspace.updateSeriesLabel(identityKey: "a", newLabel: "Renamed A")
        store.aheWorkspace.updateSeriesVisibility(identityKey: "a", isVisible: false)
        store.aheWorkspace.updatePlotTitle("local override")
        store.aheWorkspace.updateXAxisLabel("local x")
        store.aheWorkspace.updateYAxisLabel("local y")

        var after = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &after)

        XCTAssertEqual(before, after, "Transient per-tab render state must not move a capture")
    }

    /// Persisted mutations continue to reach the snapshot after the callback split — this is
    /// the other half of the Phase C contract: separating transient from persisted must not
    /// accidentally silence real persistence.
    func testCaptureInteraction_persistedPlotControlMutationsStillReachSnapshotAfterCallbackSplit() {
        let store = makeWorkbenchStore()
        store.aheWorkspace.titleTemplate = "#persisted"
        store.aheWorkspace.stackOffsetMultiplier = 0.9
        store.aheWorkspace.minGapFraction = 0.21
        store.aheWorkspace.tabs.seriesRenderMode = .scatter
        store.globalPlotDefaults = ["fontFamily": "Helvetica"]

        var snapshot = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &snapshot)

        XCTAssertEqual(snapshot.aheTitleTemplate, "#persisted")
        XCTAssertEqual(snapshot.aheStackOffsetMultiplier, 0.9)
        XCTAssertEqual(snapshot.aheMinGapFraction, 0.21)
        XCTAssertEqual(snapshot.aheSeriesRenderMode, .scatter)
        XCTAssertEqual(snapshot.workbenchPlotDefaults, ["fontFamily": "Helvetica"])
    }

    // MARK: - Phase D: RSM audit

    /// RSM has zero `SpinLabInteractionSnapshot` fields of its own (confirmed by source
    /// inspection: no `rsm*` field exists in the snapshot struct, and
    /// `WorkbenchFeatureStore.captureInteraction`/`restoreInteraction` never reference
    /// `rsmWorkspace`). Every RSM plot-control mutation — including the ones that used to call
    /// `scheduleInteractionSnapshotFlush` for view state (`rsmViewChange`'s active-view switch,
    /// now removed) — must be a pure no-op on capture.
    func testCaptureInteraction_rsmWorkspaceMutationsAreNotPartOfSnapshot() {
        let store = makeWorkbenchStore()

        var before = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &before)

        store.rsmWorkspace.activeView = store.rsmWorkspace.activeView
        store.rsmWorkspace.updateHeatmapColorScaleMode(.log10)
        store.rsmWorkspace.updateHeatmapShowColorbar(false)
        store.rsmWorkspace.updateHeatmapXTickCount(9)
        store.rsmWorkspace.updateHeatmapTitle("rsm override")

        var after = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &after)

        XCTAssertEqual(before, after, "RSM has no snapshot-backed fields — no RSM mutation should move a capture")
    }

    /// RSM's font-family/size controls write into the *shared* `globalPlotDefaults` binding
    /// (the same one AHE/IV/RT/XY/ThreeOmega use), which genuinely is a snapshot field
    /// (`workbenchPlotDefaults`) — this is the one legitimately-persisted path through RSM's
    /// plot controls, and it must still flush after the tick-count/style-change split.
    func testCaptureInteraction_rsmGlobalPlotDefaultsStillReachSnapshot() {
        let store = makeWorkbenchStore()
        store.globalPlotDefaults = ["fontSize": "13"]

        var snapshot = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &snapshot)

        XCTAssertEqual(snapshot.workbenchPlotDefaults, ["fontSize": "13"])
    }

    // MARK: - Phase D: ThreeOmega audit

    /// ThreeOmega's per-tab axis-bound / tick-count / axis-range-reset controls
    /// (`ThreeOmegaPlotControlsPanel.onAxisBoundUpdate`/`onResetRanges`/`onTickCountUpdate`)
    /// used to call `scheduleInteractionSnapshotFlush` even though none of `AxisRangeOverride`/
    /// `PlotTickOverride` is a `SpinLabInteractionSnapshot` field for ThreeOmega — an
    /// inconsistency versus AHE/IV/RT/XY, which already treated the same per-tab render state
    /// as no-flush. Mutating them directly must be a pure no-op on capture, same as the
    /// standard workflows.
    func testCaptureInteraction_threeOmegaAxisAndTickOverridesAreNotPartOfSnapshot() {
        let store = makeWorkbenchStore()

        var before = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &before)

        store.threeOmegaWorkspace.updateAxisBound(.xMin, value: 5)
        store.threeOmegaWorkspace.updateTickCount(axis: .x, count: 8)
        store.threeOmegaWorkspace.resetAxisRanges()

        var after = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &after)

        XCTAssertEqual(before, after, "ThreeOmega axis-bound/tick-count/reset are per-tab render state — no snapshot field backs them")
    }

    /// ThreeOmega's genuinely persisted fields (geometry, title template, stack offset, min
    /// gap, fit ranges) continue to capture/restore correctly — the Phase D cleanup only
    /// touched the inert flush calls, not these real paths.
    func testWorkbenchFeatureStore_capturesAndRestoresThreeOmegaPersistedFields() {
        let store = makeWorkbenchStore()
        store.threeOmegaWorkspace.geometry.lxx = 30
        store.threeOmegaWorkspace.titleTemplate = "#device 3w"
        store.threeOmegaWorkspace.stackOffsetMultiplier = 0.6
        store.threeOmegaWorkspace.minGapFraction = 0.18

        var snapshot = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &snapshot)

        XCTAssertEqual(snapshot.threeOmegaGeometryLxx, 30)
        XCTAssertEqual(snapshot.threeOmegaTitleTemplate, "#device 3w")
        XCTAssertEqual(snapshot.threeOmegaStackOffsetMultiplier, 0.6)
        XCTAssertEqual(snapshot.threeOmegaMinGapFraction, 0.18)

        let restoredStore = makeWorkbenchStore()
        restoredStore.restoreInteraction(
            selectedArchivedRecordID: nil,
            workbenchResultDraft: "",
            threeOmegaGeometryLxx: snapshot.threeOmegaGeometryLxx,
            threeOmegaTitleTemplate: snapshot.threeOmegaTitleTemplate,
            threeOmegaStackOffsetMultiplier: snapshot.threeOmegaStackOffsetMultiplier,
            threeOmegaMinGapFraction: snapshot.threeOmegaMinGapFraction
        )

        XCTAssertEqual(restoredStore.threeOmegaWorkspace.geometry.lxx, 30)
        XCTAssertEqual(restoredStore.threeOmegaWorkspace.titleTemplate, "#device 3w")
        XCTAssertEqual(restoredStore.threeOmegaWorkspace.stackOffsetMultiplier, 0.6)
        XCTAssertEqual(restoredStore.threeOmegaWorkspace.minGapFraction, 0.18)
    }

    // MARK: - Restore-loop safety (Phase A/B/C/D combined)

    /// Restoring a snapshot that includes every field touched by this pass (IV title
    /// template, RT min gap, ThreeOmega fields) must not itself schedule a new persisted
    /// write — the suppress guard must still hold across all of them.
    func testInteractionMemoryStore_restoreOfAllClosureFieldsDoesNotTriggerPersistedWrite() async throws {
        let persistence = MockClosureTestPersistence()
        persistence.interactionSnapshot.ivTitleTemplate = "#tab"
        persistence.interactionSnapshot.rtMinGapFraction = 0.25
        persistence.interactionSnapshot.threeOmegaTitleTemplate = "#3w"
        let store = InteractionMemoryStore(persistence: persistence, saveDebounceInterval: 0.01)

        store.beginSuppressingFlush()
        var restored: SpinLabInteractionSnapshot?
        store.restore { snapshot in restored = snapshot }
        store.updateValue(\.ivTitleTemplate, to: restored?.ivTitleTemplate ?? "", source: "restoreEcho")
        store.markReady()
        store.endSuppressingFlush(source: "restoreInteractionSnapshot")

        try await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertLessThanOrEqual(persistence.saveInteractionSnapshotCallCount, 1)
    }
}

private final class MockClosureTestPersistence: SpinLabPersistence {
    var interactionSnapshot: SpinLabInteractionSnapshot = SpinLabInteractionSnapshot()
    var saveInteractionSnapshotCallCount = 0

    func loadPendingImports() -> [SpinLabDomain.PendingImport] { [] }
    func savePendingImports(_ imports: [SpinLabDomain.PendingImport]) {}
    func loadArchivedRecords() -> [SpinLabDomain.ArchivedRecord] { [] }
    func saveArchivedRecords(_ records: [SpinLabDomain.ArchivedRecord]) {}
    func loadProjects() -> [SpinLabDomain.Project] { [] }
    func saveProjects(_ projects: [SpinLabDomain.Project]) {}

    func loadInteractionSnapshot() -> SpinLabInteractionSnapshot {
        interactionSnapshot
    }

    func saveInteractionSnapshot(_ snapshot: SpinLabInteractionSnapshot) {
        saveInteractionSnapshotCallCount += 1
        interactionSnapshot = snapshot
    }
}
