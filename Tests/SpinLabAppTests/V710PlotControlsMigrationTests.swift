import CoreGraphics
import Foundation
import Testing
@testable import SpinLabApp

/// Gate 7.10 — Plot Controls controls-first migration and regression guards.
///
/// Invariants tested:
///
///   1. Stale text overrides (title, axis, series labels) auto-reset when the
///      chart identity changes on applyPipelineOutput; legendPoint and
///      seriesOrder are preserved across the reset.
///
///   2. Style-only rerenders (same identity) do NOT clear text overrides.
///
///   3. Legend rename and series reorder are independent: committing a chip
///      rename does not touch seriesOrder, and committing a reorder does not
///      touch seriesLabelOverrides.
///
///   4. TabRenderState round-trips through JSON with seriesLabelOverrides and
///      legendPoint intact (pack schema stability).
///
///   5. WorkbenchPlotLayout.compute uses the display (renamed) label when
///      measuring legend row widths, so the drag-preview box geometry is
///      correct for renamed series.
///
///   6. WorkbenchPlotCanvas source no longer contains the removed inline-edit
///      callbacks (onEditTitle, onEditXLabel, onEditYLabel, onEditLegendLabel,
///      onFontSizeChange, onStyleOverrideChange).
///
///   7. Font size and tick density controls are present in
///      WorkbenchPlotControlsPanel source, not only in WorkbenchPlotCanvas.

// MARK: - Helpers

private func makeMinimalPayload(workflowID: String = "ahe", semanticParams: [String: String] = [:]) -> WorkbenchPlotPayload {
    WorkbenchPlotPayload(
        schemaVersion: 1,
        workflowID: workflowID,
        workflowDisplayName: workflowID.uppercased(),
        title: "Test",
        axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R (Ω)"),
        series: [
            WorkbenchPlotSeries(
                label: "Sample A",
                x: [0, 1, 2],
                y: [0, 1, 0],
                sourceRef: "/tmp/sample-a.dat",
                sampleID: "sample-a",
                renderMode: .line,
                renderModeLocked: false,
                pointLabels: [],
                lineWidth: 1.5,
                metadata: [:]
            )
        ],
        semanticParams: semanticParams,
        styleParams: [:],
        legendDimension: nil,
        reverseSeriesForLegend: false,
        seriesReorderable: false
    )
}

private func makeMinimalPipelineOutput(payload: WorkbenchPlotPayload) throws -> WorkbenchRenderPipeline.Output {
    let input = WorkbenchRenderPipeline.Input(payload: payload)
    return try WorkbenchRenderPipeline.render(input)
}

// MARK: - Suite 1: Stale override reset on identity change

@Suite("V7.10 Stale override auto-reset")
struct V710StaleOverrideResetTests {

    private enum TestTab: String, Hashable, Sendable { case main }

    @MainActor
    @Test("Text overrides clear when chart identity changes")
    func textOverridesClearOnIdentityChange() throws {
        let manager = TabRenderManager<TestTab>(defaultTab: .main)

        // Set up initial overrides on .main
        manager.updateTitleOverride("My Title")
        manager.updateXLabelOverride("My X")
        manager.updateYLabelOverride("My Y")
        manager.updateSeriesLabel(sampleID: "sample-a", newLabel: "Renamed A")

        // Apply first render with payload A
        let payloadA = makeMinimalPayload(semanticParams: ["temperature": "80K"])
        let outputA = try makeMinimalPipelineOutput(payload: payloadA)
        manager.applyPipelineOutput(outputA, for: .main)

        // Confirm overrides survived the first apply (identity established, no prior key)
        #expect(manager.state(for: .main).titleOverride == "My Title")
        #expect(manager.state(for: .main).xLabelOverride == "My X")
        #expect(manager.state(for: .main).seriesLabelOverrides["sample-a"] == "Renamed A")

        // Now apply a render with a different identity (temperature changed)
        let payloadB = makeMinimalPayload(semanticParams: ["temperature": "200K"])
        let outputB = try makeMinimalPipelineOutput(payload: payloadB)
        manager.applyPipelineOutput(outputB, for: .main)

        // Text overrides must be cleared
        #expect(manager.state(for: .main).titleOverride == "")
        #expect(manager.state(for: .main).xLabelOverride == "")
        #expect(manager.state(for: .main).yLabelOverride == "")
        #expect(manager.state(for: .main).seriesLabelOverrides.isEmpty)
    }

    @MainActor
    @Test("legendPoint and seriesOrder survive identity change")
    func legendPointAndOrderPreservedOnIdentityChange() throws {
        let manager = TabRenderManager<TestTab>(defaultTab: .main)

        let legendPt = CGPointCodable(CGPoint(x: 0.3, y: 0.7))
        manager.tabStates[.main] = TabRenderState(
            legendPoint: legendPt,
            seriesOrder: ["key-b", "key-a"]
        )
        manager.updateTitleOverride("Title to clear")

        let payloadA = makeMinimalPayload(semanticParams: ["temperature": "80K"])
        let outputA = try makeMinimalPipelineOutput(payload: payloadA)
        manager.applyPipelineOutput(outputA, for: .main)
        // First apply establishes the identity without clearing (no prior key)
        // re-inject with a different identity to trigger the clear
        let payloadB = makeMinimalPayload(semanticParams: ["temperature": "300K"])
        let outputB = try makeMinimalPipelineOutput(payload: payloadB)
        manager.applyPipelineOutput(outputB, for: .main)

        let state = manager.state(for: .main)
        #expect(state.titleOverride == "", "title override must be cleared")
        #expect(state.legendPoint?.cgPoint == CGPoint(x: 0.3, y: 0.7), "legendPoint must survive")
        #expect(state.seriesOrder == ["key-b", "key-a"], "seriesOrder must survive")
    }

    @MainActor
    @Test("Style-only rerender preserves text overrides (same identity)")
    func styleOnlyRerenderPreservesOverrides() throws {
        let manager = TabRenderManager<TestTab>(defaultTab: .main)

        let payload = makeMinimalPayload(semanticParams: ["temperature": "80K"])

        // First render — establish identity
        let output1 = try makeMinimalPipelineOutput(payload: payload)
        manager.applyPipelineOutput(output1, for: .main)

        // Set overrides
        manager.updateTitleOverride("Keep This")
        manager.updateSeriesLabel(sampleID: "sample-a", newLabel: "Preserved Label")

        // Re-render with same payload (style change scenario)
        let output2 = try makeMinimalPipelineOutput(payload: payload)
        manager.applyPipelineOutput(output2, for: .main)

        #expect(manager.state(for: .main).titleOverride == "Keep This")
        #expect(manager.state(for: .main).seriesLabelOverrides["sample-a"] == "Preserved Label")
    }

    @MainActor
    @Test("clearStatesForTab clears text overrides but preserves legendPoint and seriesOrder")
    func clearStatesForTabScope() {
        let manager = TabRenderManager<TestTab>(defaultTab: .main)
        let pt = CGPointCodable(CGPoint(x: 0.2, y: 0.8))
        manager.tabStates[.main] = TabRenderState(
            legendPoint: pt,
            titleOverride: "To Clear",
            xLabelOverride: "Also Clear",
            seriesLabelOverrides: ["s1": "renamed"],
            seriesOrder: ["k2", "k1"]
        )

        manager.clearStatesForTab(.main)

        let s = manager.state(for: .main)
        #expect(s.titleOverride == "")
        #expect(s.xLabelOverride == "")
        #expect(s.seriesLabelOverrides.isEmpty)
        #expect(s.legendPoint?.cgPoint == CGPoint(x: 0.2, y: 0.8))
        #expect(s.seriesOrder == ["k2", "k1"])
    }
}

// MARK: - Suite 2: Legend rename + series order coexistence

@Suite("V7.10 Legend rename and series order coexistence")
struct V710LegendRenameOrderCoexistenceTests {

    @MainActor
    @Test("Committing a series rename does not touch seriesOrder")
    func renameDoesNotTouchSeriesOrder() {
        let store = ThreeOmegaWorkspaceStore()
        store.tabs.tabStates[.fieldSweep1omega] = TabRenderState(seriesOrder: ["ref-b", "ref-a"])

        store.updateSeriesLabel(sampleID: "sample-a", newLabel: "Renamed")

        #expect(store.tabs.state(for: .fieldSweep1omega).seriesOrder == ["ref-b", "ref-a"])
        #expect(store.tabs.state(for: .fieldSweep1omega).seriesLabelOverrides["sample-a"] == "Renamed")
    }

    @MainActor
    @Test("Updating series order does not touch seriesLabelOverrides")
    func updateOrderDoesNotTouchSeriesLabels() {
        let store = ThreeOmegaWorkspaceStore()
        store.tabs.activeTab = .fieldSweep1omega
        store.tabs.tabStates[.fieldSweep1omega] = TabRenderState(seriesLabelOverrides: ["sample-b": "Custom B"])

        store.updateSeriesOrder(["ref-a", "ref-b"])

        #expect(store.tabs.state(for: .fieldSweep1omega).seriesLabelOverrides["sample-b"] == "Custom B")
        #expect(store.tabs.state(for: .fieldSweep1omega).seriesOrder == ["ref-a", "ref-b"])
    }
}

// MARK: - Suite 3: Pack round-trip (schema stability)

@Suite("V7.10 Pack round-trip")
struct V710PackRoundTripTests {

    @Test("TabRenderState with seriesLabelOverrides round-trips through JSON")
    func tabRenderStateWithLabelsRoundTrips() throws {
        let state = TabRenderState(
            legendPoint: CGPointCodable(CGPoint(x: 0.5, y: 0.6)),
            titleOverride: "Custom Title",
            xLabelOverride: "Custom X",
            yLabelOverride: "Custom Y",
            seriesLabelOverrides: ["sample-a": "Label A", "sample-b": "Label B"],
            seriesOrder: ["ref-b", "ref-a"]
        )

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TabRenderState.self, from: encoded)

        #expect(decoded.legendPoint?.cgPoint == CGPoint(x: 0.5, y: 0.6))
        #expect(decoded.titleOverride == "Custom Title")
        #expect(decoded.xLabelOverride == "Custom X")
        #expect(decoded.yLabelOverride == "Custom Y")
        #expect(decoded.seriesLabelOverrides == ["sample-a": "Label A", "sample-b": "Label B"])
        #expect(decoded.seriesOrder == ["ref-b", "ref-a"])
    }

    @Test("TabRenderState decodes from old pack with no seriesLabelOverrides key")
    func oldPackMissingLabelsDecodesCleanly() throws {
        let json = """
        {
          "titleOverride": "Saved Title",
          "legendPoint": {"x": 0.1, "y": 0.9}
        }
        """
        let decoded = try JSONDecoder().decode(TabRenderState.self, from: Data(json.utf8))
        #expect(decoded.titleOverride == "Saved Title")
        #expect(decoded.seriesLabelOverrides.isEmpty)
        #expect(decoded.seriesOrder == nil)
    }
}

// MARK: - Suite 4: Legend label width reflects renamed label

@Suite("V7.10 Legend layout width uses display label")
struct V710LegendLayoutWidthTests {

    @Test("measureLabelWidth with long override exceeds short original width")
    func longOverrideProducesLargerWidth() throws {
        let payload = WorkbenchPlotPayload(
            schemaVersion: 1,
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [
                WorkbenchPlotSeries(
                    label: "AB",
                    x: [0], y: [0],
                    sourceRef: nil, sampleID: "s1",
                    renderMode: .line, renderModeLocked: false,
                    pointLabels: [], lineWidth: 1.5, metadata: [:]
                )
            ],
            semanticParams: [:], styleParams: [:],
            legendDimension: nil, reverseSeriesForLegend: false, seriesReorderable: false
        )
        let opts = WorkbenchChartRenderer.Options()

        let layoutNoOverride = WorkbenchPlotLayout.compute(
            options: opts, payload: payload, legendPoint: nil
        )
        let layoutWithOverride = WorkbenchPlotLayout.compute(
            options: opts, payload: payload, legendPoint: nil,
            seriesLabelOverrides: [0: "Very Long Renamed Series Name That Exceeds The Original"]
        )

        #expect(layoutWithOverride.legendRows[0].measuredLabelWidth > layoutNoOverride.legendRows[0].measuredLabelWidth,
                "override label width must exceed original 2-char label width")
    }

    @Test("legend drag preview box uses correct width after rename via pipeline")
    func pipelinePassesOverrideWidthToLayout() throws {
        let payload = makeMinimalPayload()
        var input = WorkbenchRenderPipeline.Input(payload: payload)
        input.seriesLabelOverrides = [0: "Very Long Renamed Label For Drag Preview Test"]

        let output = try WorkbenchRenderPipeline.render(input)
        let maxW = output.layout.legendRows.map(\.measuredLabelWidth).max() ?? 0
        // 2-char original "Sample A" would measure ~50pt at 18pt font; long rename >> 50pt
        #expect(maxW > 100, "renamed series must produce a wider legend box than the short original")
    }
}

// MARK: - Suite 5: Canvas source-level structural guards

@Suite("V7.10 Canvas structural guards")
struct V710CanvasStructuralGuards {

    private func canvasSource() throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = base.appendingPathComponent(
            "Sources/SpinLabApp/Features/Workbench/WorkbenchPlotCanvas.swift"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func controlsPanelSource() throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = base.appendingPathComponent(
            "Sources/SpinLabApp/Features/Workbench/WorkbenchPlotControlsPanel.swift"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("Canvas no longer declares onEditTitle callback")
    func canvasLacksOnEditTitle() throws {
        let src = try canvasSource()
        #expect(!src.contains("onEditTitle"),
                "onEditTitle must be removed from WorkbenchPlotCanvas — editing moved to Plot Controls")
    }

    @Test("Canvas no longer declares onEditXLabel or onEditYLabel")
    func canvasLacksAxisLabelCallbacks() throws {
        let src = try canvasSource()
        #expect(!src.contains("onEditXLabel"),
                "onEditXLabel must be removed from WorkbenchPlotCanvas")
        #expect(!src.contains("onEditYLabel"),
                "onEditYLabel must be removed from WorkbenchPlotCanvas")
    }

    @Test("Canvas no longer declares onEditLegendLabel callback")
    func canvasLacksOnEditLegendLabel() throws {
        let src = try canvasSource()
        #expect(!src.contains("onEditLegendLabel"),
                "onEditLegendLabel must be removed from WorkbenchPlotCanvas — legend rename moved to SeriesOrderPanel chips")
    }

    @Test("Canvas no longer declares onFontSizeChange callback")
    func canvasLacksOnFontSizeChange() throws {
        let src = try canvasSource()
        #expect(!src.contains("onFontSizeChange"),
                "onFontSizeChange must be removed from WorkbenchPlotCanvas — font size controls moved to Plot Controls panel")
    }

    @Test("Canvas no longer declares onStyleOverrideChange callback")
    func canvasLacksOnStyleOverrideChange() throws {
        let src = try canvasSource()
        #expect(!src.contains("onStyleOverrideChange"),
                "onStyleOverrideChange must be removed from WorkbenchPlotCanvas — tick density controls moved to Plot Controls panel")
    }

    @Test("Canvas still declares onLegendDrag (kept in canvas)")
    func canvasRetainsOnLegendDrag() throws {
        let src = try canvasSource()
        #expect(src.contains("onLegendDrag"),
                "onLegendDrag must remain in WorkbenchPlotCanvas")
    }

    @Test("Canvas still declares onTogglePointLabelVisibility (kept in canvas)")
    func canvasRetainsPointDotToggle() throws {
        let src = try canvasSource()
        #expect(src.contains("onTogglePointLabelVisibility"),
                "onTogglePointLabelVisibility must remain in WorkbenchPlotCanvas")
    }

    @Test("Canvas still declares onCopyPNG (kept in canvas)")
    func canvasRetainsCopyPNG() throws {
        let src = try canvasSource()
        #expect(src.contains("onCopyPNG"),
                "onCopyPNG must remain in WorkbenchPlotCanvas")
    }

    @Test("PlotControlsPanel declares font size picker controls")
    func controlsPanelHasFontSizeControls() throws {
        let src = try controlsPanelSource()
        #expect(src.contains("titleFontSize"), "controls panel must contain font size key for title")
        #expect(src.contains("axisTitleFontSize"), "controls panel must contain font size key for axis")
        #expect(src.contains("legendFontSize"), "controls panel must contain font size key for legend")
    }

    @Test("PlotControlsPanel declares tick density controls")
    func controlsPanelHasTickDensityControls() throws {
        let src = try controlsPanelSource()
        #expect(src.contains("tickTargetX"), "controls panel must contain X tick density key")
        #expect(src.contains("tickTargetY"), "controls panel must contain Y tick density key")
    }
}

// MARK: - Suite 6: Label display semantics + series order mechanisms

@Suite("V7.10 Label display and order mechanisms")
struct V710LabelDisplayAndOrderTests {

    private enum TestTab: String, Hashable, Sendable { case main }

    // MARK: Label display — model-layer invariants

    @MainActor
    @Test("Layout exposes rendered default title/x/y when overrides are empty")
    func renderedDefaultsAvailableWhenOverridesEmpty() throws {
        let manager = TabRenderManager<TestTab>(defaultTab: .main)
        let payload = makeMinimalPayload()
        let output = try makeMinimalPipelineOutput(payload: payload)
        manager.applyPipelineOutput(output, for: .main)

        let state = manager.state(for: .main)
        let layout = manager.tabOutputs[.main]?.layout

        #expect(state.titleOverride.isEmpty, "titleOverride must be empty when no edit has occurred")
        #expect(state.xLabelOverride.isEmpty)
        #expect(state.yLabelOverride.isEmpty)
        #expect(layout?.chartTitle == "Test", "layout.chartTitle is the rendered default title")
        #expect(layout?.xAxisLabel == "H (T)", "layout.xAxisLabel is the rendered default x label")
        #expect(layout?.yAxisLabel == "R (Ω)", "layout.yAxisLabel is the rendered default y label")
    }

    @MainActor
    @Test("Override values are reflected in state after edit")
    func overrideValuesReflectedAfterEdit() throws {
        let manager = TabRenderManager<TestTab>(defaultTab: .main)
        let payload = makeMinimalPayload()
        let output = try makeMinimalPipelineOutput(payload: payload)
        manager.applyPipelineOutput(output, for: .main)

        manager.updateTitleOverride("Custom Title")
        manager.updateXLabelOverride("My X")
        manager.updateYLabelOverride("My Y")

        let state = manager.state(for: .main)
        #expect(state.titleOverride == "Custom Title")
        #expect(state.xLabelOverride == "My X")
        #expect(state.yLabelOverride == "My Y")
    }

    @MainActor
    @Test("Reset clears override; layout rendered default is unchanged")
    func resetClearsOverrideAndLayoutRetainsDefault() throws {
        let manager = TabRenderManager<TestTab>(defaultTab: .main)
        let payload = makeMinimalPayload()
        let output = try makeMinimalPipelineOutput(payload: payload)
        manager.applyPipelineOutput(output, for: .main)

        manager.updateTitleOverride("Temporary Title")
        #expect(manager.state(for: .main).titleOverride == "Temporary Title")

        manager.updateTitleOverride("")

        let state = manager.state(for: .main)
        let layout = manager.tabOutputs[.main]?.layout
        #expect(state.titleOverride.isEmpty, "override cleared after reset commit")
        #expect(layout?.chartTitle == "Test", "rendered default unchanged after override reset")
    }

    // MARK: Series order mechanisms

    @Test("Drag reorder and arrow reorder produce same key sequence for a basic move")
    func dragAndArrowProduceSameOrder() {
        let rowA = SeriesOrderRow(identityKey: "key-a", sampleID: "a", sourceRef: "/a", label: "A", originalIndex: 0)
        let rowB = SeriesOrderRow(identityKey: "key-b", sampleID: "b", sourceRef: "/b", label: "B", originalIndex: 1)
        let presented = [rowB, rowA]  // presentedRows reverses internal order

        // Arrow: move index 0 (B) to index 1
        var arrowResult = presented
        let moved = arrowResult.remove(at: 0)
        arrowResult.insert(moved, at: 1)

        // Drag: drop B onto A past the midpoint (dropLocationX >= 0.5 → insert after A)
        let dragResult = WorkbenchSeriesOrderPanel.reorderedRows(
            presented,
            draggedKey: "key-b",
            targetKey: "key-a",
            dropLocationX: 0.7
        )

        #expect(arrowResult.map(\.identityKey) == dragResult.map(\.identityKey),
                "drag and arrow reorder must produce identical key order")
    }

    @Test("WorkbenchSeriesOrderPanel source declares both drag and arrow order mechanisms")
    func seriesOrderPanelHasBothDragAndArrow() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = base.appendingPathComponent(
            "Sources/SpinLabApp/Features/Workbench/WorkbenchSeriesOrderPanel.swift"
        )
        let src = try String(contentsOf: url, encoding: .utf8)
        #expect(src.contains(".draggable("), "chip must use .draggable for drag reorder")
        #expect(src.contains(".dropDestination("), "chip must use .dropDestination to accept drops")
        #expect(src.contains("arrow.up"), "chip must retain arrow.up button as fallback reorder")
        #expect(src.contains("arrow.down"), "chip must retain arrow.down button as fallback reorder")
    }

    @Test("Rename button uses square.and.pencil, not bare pencil icon")
    func renameIconUsesSquareAndPencil() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = base.appendingPathComponent(
            "Sources/SpinLabApp/Features/Workbench/WorkbenchSeriesOrderPanel.swift"
        )
        let src = try String(contentsOf: url, encoding: .utf8)
        #expect(src.contains("\"square.and.pencil\""),
                "rename button must use square.and.pencil for clarity")
        #expect(!src.contains("\"pencil\""),
                "bare pencil icon must be replaced by square.and.pencil")
    }

    @Test("WorkbenchSeriesOrderPanel declares drop indicator state")
    func seriesOrderPanelHasDropIndicatorState() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = base.appendingPathComponent(
            "Sources/SpinLabApp/Features/Workbench/WorkbenchSeriesOrderPanel.swift"
        )
        let src = try String(contentsOf: url, encoding: .utf8)
        #expect(src.contains("dragTargetKey"),
                "panel must declare dragTargetKey state for the drop indicator")
        #expect(src.contains("dropIsRight"),
                "panel must declare dropIsRight state to track indicator side")
        #expect(src.contains("Color.accentColor"),
                "panel must render the drop indicator using accentColor (blue)")
    }
}

// MARK: - Suite 7: UI density and typography guards

/// Guards against regression of font sizes below 12pt in Plot Controls UI files.
/// Checks source text directly so violations are caught at commit time without running the app.
@Suite("V7.10 UI density and typography guards")
struct V710UIDensityGuards {

    private func sourceURL(for filename: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SpinLabApp/Features/Workbench/\(filename)")
    }

    // MARK: caption2 absent

    @Test("WorkbenchPlotControlsPanel contains no .caption2 font references")
    func plotControlsPanelNoCaption2() throws {
        let src = try String(contentsOf: sourceURL(for: "WorkbenchPlotControlsPanel.swift"), encoding: .utf8)
        #expect(!src.contains(".caption2"),
                "WorkbenchPlotControlsPanel must not use .caption2 — minimum font is .caption (≥12pt)")
    }

    @Test("WorkbenchSeriesOrderPanel contains no .caption2 font references")
    func seriesOrderPanelNoCaption2() throws {
        let src = try String(contentsOf: sourceURL(for: "WorkbenchSeriesOrderPanel.swift"), encoding: .utf8)
        #expect(!src.contains(".caption2"),
                "WorkbenchSeriesOrderPanel must not use .caption2 — minimum font is .caption (≥12pt)")
    }

    @Test("WorkbenchStandardPlotControls contains no .caption2 font references")
    func standardPlotControlsNoCaption2() throws {
        let src = try String(contentsOf: sourceURL(for: "WorkbenchStandardPlotControls.swift"), encoding: .utf8)
        #expect(!src.contains(".caption2"),
                "WorkbenchStandardPlotControls must not use .caption2 — minimum font is .caption (≥12pt)")
    }

    // MARK: Sub-12pt system sizes absent

    @Test("WorkbenchSeriesOrderPanel contains no system icon font smaller than 12pt")
    func seriesOrderPanelNoSmallSystemFont() throws {
        let src = try String(contentsOf: sourceURL(for: "WorkbenchSeriesOrderPanel.swift"), encoding: .utf8)
        #expect(!src.contains("system(size: 9"),
                "icon size 9pt is below minimum — use system(size: 12) or larger")
        #expect(!src.contains("system(size: 10"),
                "icon size 10pt is below minimum — use system(size: 12) or larger")
        #expect(!src.contains("system(size: 11"),
                "icon size 11pt is below minimum — use system(size: 12) or larger")
    }

    @Test("WorkbenchStandardPlotControls LabelOverrideField clear icon is not smaller than 12pt")
    func labelOverrideFieldClearIconMinSize() throws {
        let src = try String(contentsOf: sourceURL(for: "WorkbenchStandardPlotControls.swift"), encoding: .utf8)
        #expect(!src.contains("system(size: 9"),
                "xmark.circle.fill icon must be at least 12pt")
        #expect(!src.contains("system(size: 10"),
                "xmark.circle.fill icon must be at least 12pt")
        #expect(!src.contains("system(size: 11"),
                "xmark.circle.fill icon must be at least 12pt")
    }

    // MARK: Structural: GroupBox title removed

    @Test("WorkbenchSeriesOrderPanel does not use GroupBox with 'Series Order' title")
    func seriesOrderPanelNoGroupBoxTitle() throws {
        let src = try String(contentsOf: sourceURL(for: "WorkbenchSeriesOrderPanel.swift"), encoding: .utf8)
        #expect(!src.contains("GroupBox(\"Series Order\")"),
                "Series Order GroupBox title must be removed — chips shown directly")
    }

    // MARK: No .caption font modifier

    @Test("WorkbenchPlotControlsPanel uses no .caption font modifier")
    func plotControlsPanelNoCaption() throws {
        let src = try String(contentsOf: sourceURL(for: "WorkbenchPlotControlsPanel.swift"), encoding: .utf8)
        #expect(!src.contains(".font(.caption)"),
                "WorkbenchPlotControlsPanel must not use .font(.caption) — use .font(.system(size: 12)) or larger")
    }

    @Test("WorkbenchStandardPlotControls uses no .caption font modifier")
    func standardPlotControlsNoCaption() throws {
        let src = try String(contentsOf: sourceURL(for: "WorkbenchStandardPlotControls.swift"), encoding: .utf8)
        #expect(!src.contains(".font(.caption)"),
                "WorkbenchStandardPlotControls must not use .font(.caption) — use .font(.system(size: 12)) or larger")
    }

    @Test("WorkbenchSeriesOrderPanel uses no .caption font modifier")
    func seriesOrderPanelNoCaption() throws {
        let src = try String(contentsOf: sourceURL(for: "WorkbenchSeriesOrderPanel.swift"), encoding: .utf8)
        #expect(!src.contains(".font(.caption)"),
                "WorkbenchSeriesOrderPanel must not use .font(.caption) — use .font(.system(size: 12)) or larger")
    }

    // MARK: LabelOverrideField TextField must use primary color unconditionally

    @Test("LabelOverrideField TextField does not use conditional secondary foreground color")
    func labelOverrideFieldTextFieldNoPrimarySecondaryConditional() throws {
        let src = try String(contentsOf: sourceURL(for: "WorkbenchStandardPlotControls.swift"), encoding: .utf8)
        #expect(!src.contains("hasOverride ? Color.primary : Color.secondary"),
                "LabelOverrideField TextField must use Color.primary unconditionally — secondary color must not be applied to the input field")
    }

    // MARK: Structural: ticks inline with Draw row

    @Test("WorkbenchPlotControlsPanel tick density steppers are in the same row as the render mode picker")
    func plotControlsPanelTicksInlineWithDraw() throws {
        let src = try String(contentsOf: sourceURL(for: "WorkbenchPlotControlsPanel.swift"), encoding: .utf8)
        // The tickDensityRow property should no longer exist as a standalone view
        #expect(!src.contains("var tickDensityRow"),
                "tickDensityRow must be merged into the Draw row, not kept as a separate view")
        // tickTargetX and the segmented picker must appear in close proximity (same HStack)
        // Verify both keys are still present (not deleted)
        #expect(src.contains("tickTargetX"), "tick X density key must remain in source")
        #expect(src.contains("tickTargetY"), "tick Y density key must remain in source")
        #expect(src.contains(".segmented"), "render mode segmented picker must remain")
    }
}
