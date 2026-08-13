import Foundation
import Testing
@testable import SpinLabApp

/// v5.5.7 — Reset ranges is now a shared, panel-level capability
/// (`PlotRangeResetControl`, injected via an optional `onResetRanges: (() -> Void)?`)
/// available identically across every Cartesian XY workflow (RT, IV, XY Rotation,
/// AHE, 3ω Scaling/RAHE) and Dual Axis (3ω Temperature Dependence). Supersedes the
/// old `showsResetRangesControl` bool flag and its undocumented sole opt-out
/// (3ω Temperature Dependence), which prior audits found had no recorded product
/// rationale.
///
/// Atomicity and "unrelated state untouched" are covered as real behavioral tests
/// against `TabRenderManager` (Cartesian) and `DualAxisDisplayState` (Dual Axis).
/// Call-site wiring ("every context offers it", "exactly one mutation/redraw/flush
/// per reset", "the shared control is the only reset-ranges UI") are
/// source-inspection checks, matching this repo's existing convention for
/// plot-controls wiring assertions (see V78CPlotControlsSpecializationTests.swift).
@Suite("V5.5.7 Plot range reset — atomic behavior")
struct V557PlotRangeResetAtomicBehaviorTests {

    @Test("TabRenderManager.resetAxisRangeOverride clears all four Cartesian bounds atomically")
    @MainActor
    func cartesianResetClearsAllBounds() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        manager.tabStates[.ahe] = TabRenderState(
            axisRangeOverride: AxisRangeOverride(xMin: 1, xMax: 2, yMin: 3, yMax: 4)
        )

        let changed = manager.resetAxisRangeOverride()

        #expect(changed)
        #expect(manager.tabStates[.ahe]?.axisRangeOverride == nil)
    }

    @Test("resetAxisRangeOverride is a no-op (returns false, no mutation) when there is nothing to reset")
    @MainActor
    func cartesianResetNoOpWhenAlreadyClear() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        manager.tabStates[.ahe] = TabRenderState(titleOverride: "Kept")

        let changed = manager.resetAxisRangeOverride()

        #expect(!changed, "nothing was overridden, so reset must report no change (no redraw/flush should follow)")
        #expect(manager.tabStates[.ahe]?.titleOverride == "Kept")
    }

    @Test("resetAxisRangeOverride touches only axisRangeOverride, leaving every other TabRenderState field unchanged")
    @MainActor
    func cartesianResetPreservesUnrelatedState() {
        let manager = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe)
        var state = TabRenderState(
            titleOverride: "My title",
            xLabelOverride: "X label",
            yLabelOverride: "Y label",
            seriesLabelOverrides: ["a": "Alpha"],
            hiddenSeriesKeys: ["b"],
            seriesOrder: ["a", "b"],
            axisRangeOverride: AxisRangeOverride(xMin: 0, xMax: 1, yMin: 0, yMax: 1),
            tickOverride: PlotTickOverride(x: 4, y: 5),
            showPointTags: true,
            showTitle: false
        )
        manager.tabStates[.ahe] = state

        _ = manager.resetAxisRangeOverride()

        state.axisRangeOverride = nil
        #expect(
            manager.tabStates[.ahe] == state,
            "resetAxisRangeOverride must not touch title/label overrides, series order/labels, hidden series, tick override, point tags, or title visibility"
        )
    }

    @Test("Dual Axis reset (axisRangeOverride = nil) clears all six bounds and leaves every other DualAxisDisplayState field unchanged")
    func dualAxisResetPreservesUnrelatedState() {
        var state = DualAxisDisplayState(
            titleOverride: "Title",
            xLabelOverride: "X",
            leftYLabelOverride: "L-Y",
            rightYLabelOverride: "R-Y",
            axisRangeOverride: DualAxisAxisRangeOverride(
                xMin: 0, xMax: 1, leftYMin: 2, leftYMax: 3, rightYMin: 4, rightYMax: 5
            ),
            leftSeriesStyle: DualAxisSeriesVisualStyle(lineWidth: 2, pointRadius: 3),
            rightSeriesStyle: DualAxisSeriesVisualStyle(lineWidth: 4, pointRadius: 5),
            axisColorPolicy: .monochrome,
            showTitle: false
        )
        let before = state

        // Exactly the atomic write the 3ω Temperature Dependence call site performs
        // (see ThreeOmegaWorkspaceView.swift's onResetRanges closure).
        state.axisRangeOverride = nil

        #expect(state.axisRangeOverride == nil)
        #expect(state.titleOverride == before.titleOverride)
        #expect(state.xLabelOverride == before.xLabelOverride)
        #expect(state.leftYLabelOverride == before.leftYLabelOverride)
        #expect(state.rightYLabelOverride == before.rightYLabelOverride)
        #expect(state.leftSeriesStyle == before.leftSeriesStyle)
        #expect(state.rightSeriesStyle == before.rightSeriesStyle)
        #expect(state.axisColorPolicy == before.axisColorPolicy)
        #expect(state.showTitle == before.showTitle)
    }
}

// MARK: - Source-inspection: call-site wiring

@Suite("V5.5.7 Plot range reset — capability wiring")
struct V557PlotRangeResetWiringTests {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SpinLabAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private func loadSource(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// Returns the bodies of every `{ ... }` closure immediately following each
    /// occurrence of `marker` in `source`, using brace counting rather than a fixed
    /// indent so it's robust to files (like ThreeOmegaWorkspaceView.swift) that wire
    /// the marker more than once at different nesting depths.
    private func closureBodies(in source: String, afterMarker marker: String) -> [String] {
        var bodies: [String] = []
        var searchStart = source.startIndex
        while let markerRange = source.range(of: marker, range: searchStart..<source.endIndex) {
            var depth = 1
            var index = markerRange.upperBound
            let bodyStart = index
            while index < source.endIndex {
                let ch = source[index]
                if ch == "{" { depth += 1 }
                if ch == "}" {
                    depth -= 1
                    if depth == 0 { break }
                }
                index = source.index(after: index)
            }
            bodies.append(String(source[bodyStart..<index]))
            searchStart = index < source.endIndex ? source.index(after: index) : source.endIndex
        }
        return bodies
    }

    private func occurrences(of substring: String, in text: String) -> Int {
        text.components(separatedBy: substring).count - 1
    }

    private struct CartesianCase {
        let file: String
        let resetCall: String
    }

    // RT/IV/XY Rotation/AHE axis-range overrides live only in per-tab render state
    // (TabRenderManager), which is not part of SpinLabInteractionSnapshot. Reset must
    // still perform its one atomic mutation, but — per the interaction-snapshot
    // persistence contract — must NOT schedule a snapshot flush for state the snapshot
    // doesn't track. 3ω's axis-range overrides (Cartesian AxisRangeOverride and Dual
    // Axis's DualAxisDisplayState.axisRangeOverride) are the same kind of per-tab render
    // state and are held to the identical contract — see the 3ω-specific test below.
    private let cartesianCases: [CartesianCase] = [
        CartesianCase(file: "Features/Workbench/RTWorkspaceView.swift", resetCall: "store.resetAxisRanges()"),
        CartesianCase(file: "Features/Workbench/IVWorkspaceView.swift", resetCall: "store.resetAxisRanges()"),
        CartesianCase(file: "Features/Workbench/XYRotationWorkspaceView.swift", resetCall: "store.resetAxisRanges()"),
        CartesianCase(file: "Features/Workbench/AHEWorkspaceView.swift", resetCall: "ahe.resetAxisRanges()"),
    ]

    @Test("RT/IV/XY Rotation/AHE each wire onResetRanges to exactly one atomic reset call, with no interaction-snapshot flush (axis-range overrides are not a persisted field)")
    func cartesianCallSitesWireResetExactlyOnce() throws {
        for testCase in cartesianCases {
            let source = try loadSource("Sources/SpinLabApp/\(testCase.file)")
            let bodies = closureBodies(in: source, afterMarker: "onResetRanges: {")
            #expect(bodies.count == 1, "\(testCase.file) must wire onResetRanges exactly once")
            guard let body = bodies.first else { continue }
            #expect(occurrences(of: testCase.resetCall, in: body) == 1,
                    "\(testCase.file) must call \(testCase.resetCall) exactly once per reset")
            #expect(!body.contains("scheduleInteractionSnapshotFlush"),
                    "\(testCase.file) must not schedule an interaction snapshot flush on reset — axis-range overrides are transient, per-tab render state, not a SpinLabInteractionSnapshot field")
        }
    }

    @Test("3ω wires onResetRanges exactly once for the Cartesian (Scaling/RAHE) path and once for Dual Axis (Temperature Dependence), each atomic and with no interaction-snapshot flush (axis-range overrides are not a persisted field for 3ω either)")
    func threeOmegaBothPathsWireResetExactlyOnce() throws {
        let source = try loadSource("Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift")
        let bodies = closureBodies(in: source, afterMarker: "onResetRanges: {")
        #expect(bodies.count == 2, "3ω must wire onResetRanges exactly twice — Cartesian (Scaling/RAHE) and Dual Axis (Temperature Dependence)")

        guard let cartesianBody = bodies.first(where: { $0.contains("store.resetAxisRanges()") }) else {
            Issue.record("Could not find 3ω's Cartesian onResetRanges closure")
            return
        }
        #expect(occurrences(of: "store.resetAxisRanges()", in: cartesianBody) == 1)
        #expect(!cartesianBody.contains("scheduleInteractionSnapshotFlush"),
                "3ω's Cartesian reset must not schedule an interaction snapshot flush — axis-range overrides are transient, per-tab render state, not a SpinLabInteractionSnapshot field, matching AHE/IV/RT/XY")

        guard let dualAxisBody = bodies.first(where: { $0.contains("temperatureDependenceDisplayState.axisRangeOverride = nil") }) else {
            Issue.record("Could not find 3ω's Dual Axis onResetRanges closure")
            return
        }
        #expect(occurrences(of: "bindableStore.temperatureDependenceDisplayState.axisRangeOverride = nil", in: dualAxisBody) == 1,
                "Dual Axis reset must reuse the existing atomic single-write clear, not per-bound commits")
        #expect(!dualAxisBody.contains("scheduleInteractionSnapshotFlush"),
                "3ω's Dual Axis reset must not schedule an interaction snapshot flush — DualAxisDisplayState.axisRangeOverride is transient, per-tab render state, not a SpinLabInteractionSnapshot field")
    }

    @Test("The old showsResetRangesControl flag and its opt-out are fully gone")
    func showsResetRangesControlFlagRemoved() throws {
        let panelSrc = try loadSource("Sources/SpinLabApp/Workbench/Modules/PlotSystem/DualAxis/DualAxisPlotControlsPanel.swift")
        #expect(!panelSrc.contains("showsResetRangesControl"),
                "DualAxisPlotControlsPanel must no longer expose a bool flag — visibility is the injected onResetRanges capability")
        #expect(panelSrc.contains("var onResetRanges: (() -> Void)? = nil"),
                "DualAxisPlotControlsPanel must expose the same typed capability as the Cartesian XY panel")

        let threeOmegaSrc = try loadSource("Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift")
        #expect(!threeOmegaSrc.contains("showsResetRangesControl"),
                "3ω's Dual Axis call site must no longer opt out — no documented product rationale existed for withholding it")
    }

    @Test("PlotRangeResetControl is the only reset-ranges UI implementation in the app")
    func sharedControlIsSoleImplementation() throws {
        let allSwiftFiles = try FileManager.default
            .subpathsOfDirectory(atPath: repoRoot().appendingPathComponent("Sources/SpinLabApp").path)
            .filter { $0.hasSuffix(".swift") }
        var filesWithResetButtonText: [String] = []
        for relativePath in allSwiftFiles {
            let src = try loadSource("Sources/SpinLabApp/\(relativePath)")
            if src.contains(#"Button("Reset ranges""#) {
                filesWithResetButtonText.append(relativePath)
            }
        }
        #expect(filesWithResetButtonText == ["Workbench/Modules/PlotSystem/Controls/Common/PlotRangeResetControl.swift"],
                "exactly one file may build the \"Reset ranges\" button; found: \(filesWithResetButtonText)")
    }

    @Test("The reset control is composed at the panel level, not inside the per-bound numeric leaf")
    func resetControlNotInsideNumericLeaf() throws {
        let axisRangeFieldRowSrc = try loadSource(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchAxisRangeControls.swift"
        )
        #expect(!axisRangeFieldRowSrc.contains("PlotRangeResetControl"),
                "the shared row atom (AxisRangeFieldRow) must not know about reset")

        // v5.5.7: AxisBoundField (Cartesian) and CompactNumericField (Dual Axis)
        // were unified into this one shared leaf.
        let sharedLeafSrc = try loadSource(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/PlotAxisBoundField.swift"
        )
        #expect(!sharedLeafSrc.contains("PlotRangeResetControl"),
                "the per-bound leaf (PlotAxisBoundField) must not know about reset")
    }

    @Test("WorkbenchPlotControlsPanel composes PlotRangeResetControl only when onResetRanges is supplied")
    func cartesianPanelComposesSharedControlConditionally() throws {
        let src = try loadSource(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchPlotControlsPanel.swift"
        )
        #expect(src.contains("if let onResetRanges {"),
                "the shared control must be omitted (not just disabled) when no reset capability is injected")
        #expect(src.contains("PlotRangeResetControl("),
                "WorkbenchPlotControlsPanel must compose the shared control, not a local duplicate")
    }
}
