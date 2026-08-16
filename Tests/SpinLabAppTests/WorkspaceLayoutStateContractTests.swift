import Foundation
import Testing
@testable import SpinLabApp

/// Behavioral regression guards for `WorkspaceLayoutState` — the app-wide
/// three-pane (Navigation | Primary | Detail) divider-width state contract.
/// See `docs/architecture/workbench/WORKBENCH_LAYOUT_OWNERSHIP_AUDIT.md`.
@Suite("WorkspaceLayoutState divider contract")
struct WorkspaceLayoutStateContractTests {

    private static let testDefaults = WorkspaceLayoutDefaults(
        leftMin: 180, leftIdeal: 220, leftMax: 260,
        centerMin: 400,
        rightMin: 300, rightIdeal: 400, rightMax: 700
    )

    /// Fresh, isolated UserDefaults suite per test so persistence writes never
    /// leak into the app's real defaults or between tests.
    private func makeStore() -> UserDefaults {
        UserDefaults(suiteName: "WorkspaceLayoutStateContractTests.\(UUID().uuidString)")!
    }

    // TEST 1 — restore from persisted values.
    @Test("initial persisted values seed left/right preferred widths")
    func restoresFromPersistedValues() {
        let store = makeStore()
        store.set(200.0, forKey: WorkspaceLayoutState.leftStorageKey)
        store.set(450.0, forKey: WorkspaceLayoutState.rightStorageKey)
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: store)

        #expect(state.leftPreferredWidth == 200)
        #expect(state.rightPreferredWidth == 450)
    }

    // TEST 2 — commits write both live and persisted state, independently per side.
    @Test("commitLeftWidth/commitRightWidth update live and persisted state independently")
    func commitsWriteLiveAndPersistedStateIndependently() {
        let store = makeStore()
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: store)

        state.commitLeftWidth(240)
        #expect(state.leftPreferredWidth == 240)
        #expect(state.persistedLeftWidth == 240)
        #expect(state.rightPreferredWidth == Self.testDefaults.rightIdeal)
        #expect(state.persistedRightWidth == nil)

        state.commitRightWidth(500)
        #expect(state.rightPreferredWidth == 500)
        #expect(state.persistedRightWidth == 500)
        #expect(state.leftPreferredWidth == 240) // untouched by the right commit
    }

    // TEST 3 — center is never persisted; only derivable via layout(for:).
    @Test("center width has no storage key and is derived, not stored")
    func centerWidthIsNeverPersisted() {
        let store = makeStore()
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: store)
        state.commitLeftWidth(230)
        state.commitRightWidth(420)

        let layout = state.layout(for: 1400)
        #expect(layout.center > 0)
        // No storage key exists for center at all — this is a structural
        // guarantee (no `centerStorageKey`/`commitCenterWidth` API surface),
        // reaffirmed here via the store: nothing under any "center" key.
        #expect(store.dictionaryRepresentation().keys.contains(where: { $0.lowercased().contains("center") }) == false)
    }

    // TEST 4 — layout(for:) is pure: repeated/varied queries never mutate preferences.
    @Test("layout(for:) queries never mutate left/right preferences")
    func layoutQueriesNeverMutatePreferences() {
        let store = makeStore()
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: store)
        state.commitLeftWidth(230)
        state.commitRightWidth(420)

        _ = state.layout(for: 300)   // far too narrow
        _ = state.layout(for: 5000)  // very wide

        #expect(state.leftPreferredWidth == 230)
        #expect(state.rightPreferredWidth == 420)
        #expect(state.persistedLeftWidth == 230)
        #expect(state.persistedRightWidth == 420)
    }

    // TEST 5 — window shrink constrains the effective layout without mutating
    // preferences; widening restores the original preferred widths.
    @Test("shrink constrains effective layout, regrow restores preferred widths, preferences untouched")
    func shrinkThenGrowPreservesPreferences() {
        let store = makeStore()
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: store)
        state.commitLeftWidth(260)
        state.commitRightWidth(700)

        let wide = state.layout(for: 2000)
        #expect(abs(wide.left - 260) < 0.01)
        #expect(abs(wide.right - 700) < 0.01)

        let narrow = state.layout(for: 900)
        #expect(narrow.left < 260)
        #expect(narrow.right < 700)
        #expect(narrow.center >= Self.testDefaults.centerMin - 0.01)
        #expect(state.leftPreferredWidth == 260)
        #expect(state.rightPreferredWidth == 700)

        let restored = state.layout(for: 2000)
        #expect(abs(restored.left - 260) < 0.01)
        #expect(abs(restored.right - 700) < 0.01)
    }

    // TEST 6 — never produces negative or non-finite widths, even far below minima.
    @Test("extremely narrow available width never produces negative or non-finite panes")
    func extremelyNarrowWidthNeverGoesNegative() {
        let store = makeStore()
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: store)

        for width: CGFloat in [0, 1, 50, 200] {
            let layout = state.layout(for: width)
            #expect(layout.left >= 0)
            #expect(layout.center >= 0)
            #expect(layout.right >= 0)
            #expect(layout.left.isFinite)
            #expect(layout.center.isFinite)
            #expect(layout.right.isFinite)
        }
    }

    // TEST 7 — commits clamp to each side's own min/max.
    @Test("commitLeftWidth/commitRightWidth clamp to their own min/max")
    func commitsClampToOwnBounds() {
        let store = makeStore()
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: store)

        state.commitLeftWidth(10)
        #expect(state.leftPreferredWidth == Self.testDefaults.leftMin)
        state.commitLeftWidth(10_000)
        #expect(state.leftPreferredWidth == Self.testDefaults.leftMax)

        state.commitRightWidth(10)
        #expect(state.rightPreferredWidth == Self.testDefaults.rightMin)
        state.commitRightWidth(10_000)
        #expect(state.rightPreferredWidth == Self.testDefaults.rightMax)
    }

    // TEST 8 — re-reading state from the same store never drifts from what was committed.
    @Test("re-reading state from the same store is stable")
    func rereadIsStable() {
        let store = makeStore()
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: store)
        state.commitLeftWidth(245)
        state.commitRightWidth(410)

        let reread = WorkspaceLayoutState(defaults: Self.testDefaults, store: store)
        #expect(reread.leftPreferredWidth == 245)
        #expect(reread.rightPreferredWidth == 410)
    }

    // TEST 9 — lifecycle alone (construct/discard) never persists anything.
    @Test("instantiating/discarding state without a commit does not persist")
    func lifecycleAloneDoesNotPersist() {
        let store = makeStore()
        _ = WorkspaceLayoutState(defaults: Self.testDefaults, store: store)
        #expect(store.object(forKey: WorkspaceLayoutState.leftStorageKey) == nil)
        #expect(store.object(forKey: WorkspaceLayoutState.rightStorageKey) == nil)
    }

    // TEST 10 — leftIntent/rightIntent preview a width without ever mutating
    // or persisting the underlying preference. This is what a live divider
    // drag calls on every frame while dragging.
    @Test("layout(leftIntent:rightIntent:) previews widths without mutating or persisting preferences")
    func dragIntentsAreReadOnlyPreviews() {
        let store = makeStore()
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: store)
        state.commitLeftWidth(220)
        state.commitRightWidth(400)

        let previewed = state.layout(for: 1600, leftIntent: 245, rightIntent: 380)

        #expect(state.leftPreferredWidth == 220)
        #expect(state.rightPreferredWidth == 400)
        #expect(state.persistedLeftWidth == 220)
        #expect(state.persistedRightWidth == 400)
        // Sanity: the preview actually reflects the intents, not the stored preferences.
        #expect(abs(previewed.left - 245) < 0.01)
        #expect(abs(previewed.right - 380) < 0.01)
    }

    // TEST 11 — left drag preview only changes the left rendered width; the
    // right side keeps tracking its own stored preference.
    @Test("left drag intent changes only the left rendered width")
    func leftDragIntentChangesOnlyLeftWidth() {
        let store = makeStore()
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: store)
        state.commitLeftWidth(220)
        state.commitRightWidth(400)

        let baseline = state.layout(for: 1600)
        let previewed = state.layout(for: 1600, leftIntent: 250)

        #expect(abs(previewed.left - 250) < 0.01)
        #expect(abs(previewed.right - baseline.right) < 0.01)
    }

    // TEST 12 — right drag preview only changes the right rendered width; the
    // left side keeps tracking its own stored preference.
    @Test("right drag intent changes only the right rendered width")
    func rightDragIntentChangesOnlyRightWidth() {
        let store = makeStore()
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: store)
        state.commitLeftWidth(220)
        state.commitRightWidth(400)

        let baseline = state.layout(for: 1600)
        let previewed = state.layout(for: 1600, rightIntent: 450)

        #expect(abs(previewed.right - 450) < 0.01)
        #expect(abs(previewed.left - baseline.left) < 0.01)
    }

    // TEST 13 — an intent-driven "drag-end" commit clamps and persists the
    // dragged side only, mirroring how AppWorkspaceShell resolves the final
    // legal width from the pure layout function before calling commit.
    @Test("intent-driven drag-end commit updates only the dragged side")
    func intentDrivenCommitUpdatesOnlyDraggedSide() {
        let store = makeStore()
        let state = WorkspaceLayoutState(defaults: Self.testDefaults, store: store)
        state.commitLeftWidth(220)
        state.commitRightWidth(400)

        let effective = state.layout(for: 1600, leftIntent: 258)
        state.commitLeftWidth(effective.left)

        #expect(state.leftPreferredWidth == 258)
        #expect(state.persistedLeftWidth == 258)
        #expect(state.rightPreferredWidth == 400)
        #expect(state.persistedRightWidth == 400)
    }
}
