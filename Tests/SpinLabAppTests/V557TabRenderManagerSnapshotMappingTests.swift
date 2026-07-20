import CoreGraphics
import Foundation
import Testing
@testable import SpinLabApp

/// v5.5.7 — TabRenderManager's WorkbenchTabDisplayStateSnapshot construction was written
/// independently in three places (`displayStateSnapshot(for:)`, `preparedDisplayState`, and
/// the live-state `buildPipelineInput` overload). All three now go through
/// `WorkbenchTabDisplayStateSnapshot.init(_ state: TabRenderState)`.
///
/// This suite locks down the one behavioral distinction that centralization must not erase:
/// the live-state `buildPipelineInput` overload still performs policy-based override
/// clearing (via `preparedState`, which mutates `tabStates`), while the explicit-snapshot
/// overload remains pure with respect to manager state regardless of what snapshot it's given.
@MainActor
@Suite("v5.5.7 - TabRenderManager snapshot mapping centralization")
struct V557TabRenderManagerSnapshotMappingTests {

    enum TestTab: Hashable, Sendable {
        case first
    }

    private func makePayload(sourceRef: String) -> WorkbenchPlotPayload {
        WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "Test",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [WorkbenchPlotSeries(label: "A", x: [0, 1, 2], y: [10, 20, 30], sourceRef: sourceRef)]
        )
    }

    private func makeManagerWithCommittedOverrides() -> TabRenderManager<TestTab> {
        let manager = TabRenderManager<TestTab>(defaultTab: .first)
        // Establish an initial source identity and commit display overrides against it.
        _ = manager.buildPipelineInput(payload: makePayload(sourceRef: "/tmp/a.dat"), for: .first)
        manager.updateTitleOverride("Committed Title")
        _ = manager.updateAxisBound(.xMin, value: 1.0)
        return manager
    }

    // MARK: - Canonical mapping produces identical output across the three call sites

    @Test("displayStateSnapshot and preparedDisplayState agree when no source change occurs")
    func canonicalMappingIsConsistentAcrossSites() {
        let manager = makeManagerWithCommittedOverrides()
        let sourceIdentityKey = WorkbenchChartIdentity.makeSourceIdentityKey(from: makePayload(sourceRef: "/tmp/a.dat"))

        let plain = manager.displayStateSnapshot(for: .first)
        let prepared = manager.preparedDisplayState(for: .first, sourceIdentityKey: sourceIdentityKey, policy: .preserveDisplayOverrides)

        #expect(plain.titleOverride == prepared.titleOverride)
        #expect(plain.axisRangeOverride == prepared.axisRangeOverride)
        #expect(plain.titleOverride == "Committed Title")
    }

    // MARK: - Live-state overload: still performs policy-based override clearing

    @Test("live-state buildPipelineInput clears overrides on source change under clearDisplayOverridesIfSourceChanged")
    func liveStateOverloadClearsOverridesOnSourceChange() {
        let manager = makeManagerWithCommittedOverrides()
        #expect(manager.tabStates[.first]?.titleOverride == "Committed Title")
        #expect(manager.tabStates[.first]?.axisRangeOverride != nil)

        let input = manager.buildPipelineInput(
            payload: makePayload(sourceRef: "/tmp/b.dat"),   // different sourceRef -> different source identity
            policy: .clearDisplayOverridesIfSourceChanged,
            for: .first
        )

        // The resulting render input reflects the clearing.
        #expect(input.titleOverride.isEmpty)
        #expect(input.axisRangeOverride == nil)

        // And it mutated live manager state (this is the point of the "live-state" overload):
        // preparedState/applyOverrideClearing wrote the cleared state back into tabStates.
        #expect(manager.tabStates[.first]?.titleOverride.isEmpty ?? true)
        #expect(manager.tabStates[.first]?.axisRangeOverride == nil)
    }

    @Test("live-state buildPipelineInput preserves overrides when source identity is unchanged")
    func liveStateOverloadPreservesOverridesWithoutSourceChange() {
        let manager = makeManagerWithCommittedOverrides()

        let input = manager.buildPipelineInput(
            payload: makePayload(sourceRef: "/tmp/a.dat"),   // same sourceRef -> same source identity
            policy: .clearDisplayOverridesIfSourceChanged,
            for: .first
        )

        #expect(input.titleOverride == "Committed Title")
        #expect(manager.tabStates[.first]?.titleOverride == "Committed Title")
    }

    // MARK: - Explicit-snapshot overload: remains pure with respect to manager state

    @Test("explicit-snapshot buildPipelineInput does not mutate manager state, regardless of snapshot contents")
    func explicitSnapshotOverloadDoesNotMutateManagerState() {
        let manager = makeManagerWithCommittedOverrides()
        let beforeTitle = manager.tabStates[.first]?.titleOverride
        let beforeAxisRange = manager.tabStates[.first]?.axisRangeOverride

        // A snapshot that itself carries a "cleared" state -- still must not touch manager state.
        let clearedSnapshot = WorkbenchTabDisplayStateSnapshot(
            titleOverride: "",
            xLabelOverride: "",
            yLabelOverride: "",
            seriesLabelOverrides: [:],
            legendPoint: nil,
            hiddenSeriesKeys: [],
            hiddenPointLabelsBySeries: [:],
            seriesOrder: nil,
            axisRangeOverride: nil,
            tickOverride: nil,
            showPointTags: false,
            showTitle: true
        )

        let input = manager.buildPipelineInput(
            payload: makePayload(sourceRef: "/tmp/b.dat"),   // different source than what's committed
            tabState: clearedSnapshot,
            showPlotGrid: manager.showPlotGrid,
            seriesRenderMode: manager.seriesRenderMode,
            chartStyleOverrides: manager.chartStyleOverrides,
            legendAnchor: manager.legendAnchor,
            for: .first
        )

        // Input reflects exactly the snapshot passed in.
        #expect(input.titleOverride.isEmpty)
        #expect(input.axisRangeOverride == nil)

        // Manager's live per-tab state is untouched -- no clearing, regardless of what the
        // caller-supplied snapshot contained or what source the payload carried.
        #expect(manager.tabStates[.first]?.titleOverride == beforeTitle)
        #expect(manager.tabStates[.first]?.axisRangeOverride == beforeAxisRange)

        // And a subsequent live-state call against the *original* source still sees the
        // original committed overrides -- proving the explicit-snapshot call above never
        // recorded a new source-identity key for this tab.
        let followUp = manager.buildPipelineInput(
            payload: makePayload(sourceRef: "/tmp/a.dat"),
            policy: .clearDisplayOverridesIfSourceChanged,
            for: .first
        )
        #expect(followUp.titleOverride == "Committed Title")
    }

    @Test("explicit-snapshot buildPipelineInput carries the exact snapshot's overrides into the render input")
    func explicitSnapshotOverloadIsPureProjection() {
        let manager = TabRenderManager<TestTab>(defaultTab: .first)
        let snapshot = WorkbenchTabDisplayStateSnapshot(
            titleOverride: "Custom Title",
            xLabelOverride: "Custom X",
            yLabelOverride: "Custom Y",
            seriesLabelOverrides: [:],
            legendPoint: CGPoint(x: 5, y: 6),
            hiddenSeriesKeys: [],
            hiddenPointLabelsBySeries: [:],
            seriesOrder: nil,
            axisRangeOverride: AxisRangeOverride(xMin: 1, xMax: 2, yMin: nil, yMax: nil),
            tickOverride: nil,
            showPointTags: false,
            showTitle: true
        )

        let input = manager.buildPipelineInput(
            payload: makePayload(sourceRef: "/tmp/a.dat"),
            tabState: snapshot,
            showPlotGrid: manager.showPlotGrid,
            seriesRenderMode: manager.seriesRenderMode,
            chartStyleOverrides: manager.chartStyleOverrides,
            legendAnchor: manager.legendAnchor,
            for: .first
        )

        #expect(input.titleOverride == "Custom Title")
        #expect(input.xLabelOverride == "Custom X")
        #expect(input.yLabelOverride == "Custom Y")
        #expect(input.axisRangeOverride == AxisRangeOverride(xMin: 1, xMax: 2, yMin: nil, yMax: nil))
        #expect(manager.tabStates[.first] == nil, "explicit-snapshot overload must never populate live tabStates")
    }
}
