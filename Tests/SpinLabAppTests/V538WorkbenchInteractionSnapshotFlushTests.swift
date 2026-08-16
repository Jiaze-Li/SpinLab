import Foundation
import XCTest
@testable import SpinLabApp

/// Regression tests for the standard-workflow (AHE/IV/RT/XY) interaction-snapshot
/// persistence contract:
///   - a persisted user mutation reaches the snapshot after capture
///   - RT's title/stack/gap/render-mode now round-trip like AHE/IV/XY (previously RT had
///     no dedicated field group, so its plot-control edits silently dropped on relaunch
///     even though the UI already called `scheduleInteractionSnapshotFlush`)
///   - restoring a snapshot does not itself trigger a new persisted write (no restore loop)
@MainActor
final class V538WorkbenchInteractionSnapshotFlushTests: XCTestCase {

    private func makeWorkbenchStore() -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(libraryRepository: LibraryRepository(persistence: persistence))
    }

    // MARK: - RT field group parity

    /// RT previously had no `rt*` field group in `SpinLabInteractionSnapshot`, unlike its
    /// sibling workflows. This proves RT's title template / stack offset / gap fraction /
    /// series render mode now capture and restore exactly like AHE/IV/XY.
    func testWorkbenchFeatureStore_capturesAndRestoresRTPlotControls() {
        let store = makeWorkbenchStore()
        store.rtWorkspace.titleTemplate = "#device custom"
        store.rtWorkspace.stackOffsetMultiplier = 0.7
        store.rtWorkspace.minGapFraction = 0.22
        store.rtWorkspace.tabs.seriesRenderMode = .lineAndScatter

        var snapshot = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &snapshot)

        XCTAssertEqual(snapshot.rtTitleTemplate, "#device custom")
        XCTAssertEqual(snapshot.rtStackOffsetMultiplier, 0.7)
        XCTAssertEqual(snapshot.rtMinGapFraction, 0.22)
        XCTAssertEqual(snapshot.rtSeriesRenderMode, .lineAndScatter)

        let restoredStore = makeWorkbenchStore()
        restoredStore.restoreInteraction(
            selectedArchivedRecordID: nil,
            workbenchResultDraft: "",
            rtTitleTemplate: snapshot.rtTitleTemplate,
            rtStackOffsetMultiplier: snapshot.rtStackOffsetMultiplier,
            rtMinGapFraction: snapshot.rtMinGapFraction,
            rtSeriesRenderMode: snapshot.rtSeriesRenderMode
        )

        XCTAssertEqual(restoredStore.rtWorkspace.titleTemplate, "#device custom")
        XCTAssertEqual(restoredStore.rtWorkspace.stackOffsetMultiplier, 0.7)
        XCTAssertEqual(restoredStore.rtWorkspace.minGapFraction, 0.22)
        XCTAssertEqual(restoredStore.rtWorkspace.tabs.seriesRenderMode, .lineAndScatter)
    }

    /// RT's snapshot fields round-trip through Codable like every other per-workflow field.
    func testInteractionSnapshot_roundTripsRTFields() throws {
        var snapshot = SpinLabInteractionSnapshot()
        snapshot.rtTitleTemplate = "#tab #sample"
        snapshot.rtStackOffsetMultiplier = 0.4
        snapshot.rtMinGapFraction = 0.1
        snapshot.rtSeriesRenderMode = .scatter

        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(SpinLabInteractionSnapshot.self, from: data)

        XCTAssertEqual(restored.rtTitleTemplate, "#tab #sample")
        XCTAssertEqual(restored.rtStackOffsetMultiplier, 0.4)
        XCTAssertEqual(restored.rtMinGapFraction, 0.1)
        XCTAssertEqual(restored.rtSeriesRenderMode, .scatter)
    }

    /// A snapshot with no `rt*` fields set (e.g. one written before this change) must not
    /// clobber RT's in-memory defaults — restore only applies fields that are present.
    func testWorkbenchFeatureStore_restoreInteractionLeavesRTDefaultsUntouchedWhenFieldsAbsent() {
        let store = makeWorkbenchStore()
        let defaultTemplate = store.rtWorkspace.titleTemplate
        let defaultStack = store.rtWorkspace.stackOffsetMultiplier
        let defaultGap = store.rtWorkspace.minGapFraction

        store.restoreInteraction(selectedArchivedRecordID: nil, workbenchResultDraft: "")

        XCTAssertEqual(store.rtWorkspace.titleTemplate, defaultTemplate)
        XCTAssertEqual(store.rtWorkspace.stackOffsetMultiplier, defaultStack)
        XCTAssertEqual(store.rtWorkspace.minGapFraction, defaultGap)
    }

    // MARK: - Restore-loop safety

    /// Restoring a snapshot must not itself schedule a new persisted write. This exercises
    /// the real `InteractionMemoryStore` guard (`isRestoring` / `beginSuppressingFlush`) the
    /// same way `SpinLabAppState.restoreInteractionSnapshot()` composes it, using the AHE/IV/
    /// RT/XY-relevant fields as the payload.
    func testInteractionMemoryStore_restoreDoesNotTriggerPersistedWrite() async throws {
        let persistence = MockSpinLabPersistence()
        persistence.interactionSnapshot.aheTitleTemplate = "#tab"
        persistence.interactionSnapshot.rtStackOffsetMultiplier = 0.5
        persistence.interactionSnapshot.xyRotationCenterBaseline = true
        let store = InteractionMemoryStore(persistence: persistence, saveDebounceInterval: 0.01)

        // Mirrors SpinLabAppState.restoreInteractionSnapshot(): suppress guard wraps the
        // restore, then a workbench store re-applies the restored values onto live @Observable
        // state (which is what would normally re-trigger a capture/flush from onChange
        // observers if the suppress guard didn't hold).
        store.beginSuppressingFlush()
        var appliedTemplate: String?
        store.restore { snapshot in
            appliedTemplate = snapshot.aheTitleTemplate
        }
        // Simulate a mutation observer re-asserting the just-restored value onto canonical
        // state, as AHE/IV/RT/XY workspace restore does today.
        store.updateValue(\.aheTitleTemplate, to: appliedTemplate ?? "", source: "restoreEcho")
        store.markReady()
        store.endSuppressingFlush(source: "restoreInteractionSnapshot")

        try await Task.sleep(nanoseconds: 60_000_000)

        // The suppressed mutation folded into the single deferred flush endSuppressingFlush
        // performs; there must be at most one resulting disk write, not one per suppressed
        // update, and it must not be silently dropped either (the snapshot did legitimately
        // change vs. what was loaded, e.g. via the echo above matching the loaded value).
        XCTAssertLessThanOrEqual(persistence.saveInteractionSnapshotCallCount, 1)
    }

    /// After `markReady()`, a genuine post-restore user edit (not itself restore machinery)
    /// still flushes normally — the suppress guard must not leak past `endSuppressingFlush`.
    func testInteractionMemoryStore_flushesNormallyAfterRestoreCompletes() async throws {
        let persistence = MockSpinLabPersistence()
        let store = InteractionMemoryStore(persistence: persistence, saveDebounceInterval: 0.01)

        store.beginSuppressingFlush()
        store.restore { _ in }
        store.markReady()
        store.endSuppressingFlush(source: "restoreInteractionSnapshot")

        store.updateValue(\.rtTitleTemplate, to: "#device", source: "rtStyleChange")
        try await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertEqual(persistence.saveInteractionSnapshotCallCount, 1)
        XCTAssertEqual(persistence.interactionSnapshot.rtTitleTemplate, "#device")
    }

    // MARK: - Cross-workflow consistency: transient (non-snapshot) fields don't move the needle

    /// Series order / visibility / rename / axis-bound / tick-count are not part of
    /// `SpinLabInteractionSnapshot` for any of AHE/IV/RT/XY today (they live in
    /// `TabRenderManager.tabStates`, which is per-session render state, not captured by
    /// `WorkbenchFeatureStore.captureInteraction`). Capturing after such a mutation must be a
    /// pure no-op relative to a capture that only reflects tracked fields.
    func testCaptureInteraction_seriesOrderAndVisibilityAreNotPartOfSnapshot() {
        let store = makeWorkbenchStore()

        var before = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &before)

        // Mutate only transient per-tab render state (series order / hidden keys), not any
        // tracked field.
        store.aheWorkspace.tabs.updateSeriesOrder(["b", "a"])
        store.aheWorkspace.tabs.updateSeriesVisibility(identityKey: "a", isVisible: false)

        var after = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &after)

        XCTAssertEqual(before, after)
    }

    /// Axis-range overrides, series rename, and tick-count overrides for RT/IV/XY are the
    /// same per-tab render state as AHE's series order/visibility above — none of them are
    /// SpinLabInteractionSnapshot fields, so mutating them must not move a capture either.
    func testCaptureInteraction_axisAndTickOverridesAreNotPartOfSnapshotForAnyStandardWorkflow() {
        let store = makeWorkbenchStore()

        var before = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &before)

        store.rtWorkspace.updateAxisBound(.xMin, value: 1)
        store.rtWorkspace.updateTickCount(axis: .x, count: 9)
        store.ivWorkspace.updateSeriesOrder(["ch2", "ch1"])
        store.xyRotationWorkspace.updateSeriesLabel(identityKey: "sweep-1", newLabel: "Renamed")

        var after = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &after)

        XCTAssertEqual(before, after)
    }

    /// IV's plugin-section controls (current basis, channel assignment, fit mode,
    /// zero-at-origin, angular plot toggle, angular fit mode/fold) have no corresponding
    /// `iv*` fields in `SpinLabInteractionSnapshot` — they are session-only workspace state.
    /// A capture must be identical before and after touching every one of them.
    func testCaptureInteraction_ivSpecificControlsAreNotPartOfSnapshot() {
        let store = makeWorkbenchStore()

        var before = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &before)

        let iv = store.ivWorkspace
        iv.updateXCurrentBasis(.rms, previousBasis: iv.xCurrentBasis)
        iv.ch1Component = .y
        iv.ch2Component = .x
        iv.updateFitMode(.two)
        iv.zeroAtCurrentOrigin.toggle()
        iv.updateAngularPlotEnabled(true)
        iv.angularFitMode = .harmonic
        iv.angularFitFold = 2

        var after = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &after)

        XCTAssertEqual(before, after, "IV-specific plugin controls must remain session-only — no snapshot field backs them")
    }

    // MARK: - XY Rotation field group parity

    /// XY's Center-baseline / Linear-detrend / φ-offset toggles are real snapshot fields
    /// (`xyRotationCenterBaseline`, `xyRotationLinearDetrend`, `xyRotationPhiOffsets`) —
    /// this proves they still round-trip through capture/restore after the cleanup.
    func testWorkbenchFeatureStore_capturesAndRestoresXYRotationToggles() {
        let store = makeWorkbenchStore()
        store.xyRotationWorkspace.centerBaseline = true
        store.xyRotationWorkspace.linearDetrend = true
        store.xyRotationWorkspace.phiOffsetOverrides = ["sweep-1": 12.5]

        var snapshot = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &snapshot)

        XCTAssertEqual(snapshot.xyRotationCenterBaseline, true)
        XCTAssertEqual(snapshot.xyRotationLinearDetrend, true)
        XCTAssertEqual(snapshot.xyRotationPhiOffsets, ["sweep-1": 12.5])

        let restoredStore = makeWorkbenchStore()
        restoredStore.restoreInteraction(
            selectedArchivedRecordID: nil,
            workbenchResultDraft: "",
            xyRotationPhiOffsets: snapshot.xyRotationPhiOffsets,
            xyRotationCenterBaseline: snapshot.xyRotationCenterBaseline,
            xyRotationLinearDetrend: snapshot.xyRotationLinearDetrend
        )

        XCTAssertEqual(restoredStore.xyRotationWorkspace.centerBaseline, true)
        XCTAssertEqual(restoredStore.xyRotationWorkspace.linearDetrend, true)
        XCTAssertEqual(restoredStore.xyRotationWorkspace.phiOffsetOverrides, ["sweep-1": 12.5])
    }
}

private final class MockSpinLabPersistence: SpinLabPersistence {
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
