import Foundation
import Testing

/// Gate 7.8C — Plot Controls specialization baseline (source-inspection).
///
/// Proves the documented control-path specialization recorded in
/// MODULE_BOUNDARIES.md (§ Control-path specialization, Gate 7.8 audit) and
/// PLOT_SYSTEM.md (§ Module Group Structure, § Boundary Notes (Gate 7.8)).
///
/// Three invariants under test:
///
///   1. AHEWorkspaceView uses a workflow-local AHEPlotControlsPanel custom
///      path — NOT WorkbenchStandardPlotControls. The custom path exposes
///      title template, grid, and render mode but withholds tab picker, stack
///      offset, and min-gap controls (not applicable for a single-tab workflow).
///
///   2. XYRotationWorkspaceView uses WorkbenchStandardPlotControls, binding
///      activeTab, titleTemplate, showPlotGrid, seriesRenderMode,
///      chartStyleOverrides, stackOffsetMultiplier, and minGapFraction through
///      it. Workflow-specific controls (centerBaseline, linearDetrend,
///      showAuxiliaryLine180, phiOffsetOverrides) are present in the view file
///      but are NOT parameters of WorkbenchStandardPlotControls.
///
///   3. ThreeOmegaWorkspaceView uses WorkbenchStandardPlotControls, binding
///      the same shared set of controls. Workflow-specific controls (geometry,
///      fitRanges, v3Method, RAHE method, overlays) are present in the view
///      file but are NOT parameters of WorkbenchStandardPlotControls.

// MARK: - Source helpers

private func loadWorkbenchSource(_ filename: String) throws -> String {
    let base = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SpinLabAppTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
    let url = base.appendingPathComponent("Sources/SpinLabApp/Features/Workbench/\(filename)")
    return try String(contentsOf: url, encoding: .utf8)
}

// MARK: - Suite 1: AHE uses custom plot controls path

@Suite("V7.8C AHE custom plot controls path")
struct V78CAHEPlotControlsPathTests {

    // INV-AHE-1: AHEWorkspaceView defines a workflow-local custom panel
    @Test("AHEWorkspaceView.swift defines AHEPlotControlsPanel")
    func aheDefinesCustomPanel() throws {
        let source = try loadWorkbenchSource("AHEWorkspaceView.swift")
        #expect(source.contains("AHEPlotControlsPanel"),
                "AHEWorkspaceView must define and use a workflow-local AHEPlotControlsPanel — the custom plot controls path for a single-tab workflow")
    }

    // INV-AHE-2: AHE does not use the two-row standard layout
    @Test("AHEWorkspaceView.swift does not use WorkbenchStandardPlotControls")
    func aheDoesNotUseStandardPlotControls() throws {
        let source = try loadWorkbenchSource("AHEWorkspaceView.swift")
        #expect(!source.contains("WorkbenchStandardPlotControls"),
                "AHE must not use WorkbenchStandardPlotControls — it is a single-tab workflow and the standard layout (tab picker, stack offset, min-gap) does not apply")
    }

    // INV-AHE-3: AHE custom path exposes title template
    @Test("AHEWorkspaceView.swift custom path binds titleTemplate")
    func aheCustomPathBindsTitleTemplate() throws {
        let source = try loadWorkbenchSource("AHEWorkspaceView.swift")
        #expect(source.contains("titleTemplate"),
                "AHE custom plot controls path must expose titleTemplate through WorkbenchTitleTemplateField")
    }

    // INV-AHE-4: AHE custom path exposes the grid toggle
    @Test("AHEWorkspaceView.swift custom path binds showPlotGrid")
    func aheCustomPathBindsGrid() throws {
        let source = try loadWorkbenchSource("AHEWorkspaceView.swift")
        #expect(source.contains("showPlotGrid"),
                "AHE custom plot controls path must expose showPlotGrid (grid toggle)")
    }

    // INV-AHE-5: AHE custom path exposes render mode (via WorkbenchPlotControlsPanel)
    @Test("AHEWorkspaceView.swift custom path binds seriesRenderMode via WorkbenchPlotControlsPanel")
    func aheCustomPathBindsRenderMode() throws {
        let source = try loadWorkbenchSource("AHEWorkspaceView.swift")
        #expect(source.contains("seriesRenderMode"),
                "AHE custom path must expose seriesRenderMode through WorkbenchPlotControlsPanel")
        #expect(source.contains("WorkbenchPlotControlsPanel"),
                "AHE custom path must use WorkbenchPlotControlsPanel as its common container")
    }

    // INV-AHE-6: AHE does not expose stack offset (no stacking in single-tab workflow)
    @Test("AHEWorkspaceView.swift does not bind stackOffsetMultiplier")
    func aheDoesNotExposeStackOffset() throws {
        let source = try loadWorkbenchSource("AHEWorkspaceView.swift")
        #expect(!source.contains("stackOffsetMultiplier"),
                "AHE must not expose stackOffsetMultiplier — AHE is single-tab and has no curve stacking")
    }

    // INV-AHE-7: AHE does not expose min gap fraction (no stacking in single-tab workflow)
    @Test("AHEWorkspaceView.swift does not bind minGapFraction")
    func aheDoesNotExposeMinGapFraction() throws {
        let source = try loadWorkbenchSource("AHEWorkspaceView.swift")
        #expect(!source.contains("minGapFraction"),
                "AHE must not expose minGapFraction — AHE is single-tab and has no curve stacking")
    }
}

// MARK: - Suite 2: XY Rotation uses WorkbenchStandardPlotControls

@Suite("V7.8C XY Rotation standard plot controls path")
struct V78CXYPlotControlsPathTests {

    // INV-XY-1: XYRotationWorkspaceView uses the standard two-row layout
    @Test("XYRotationWorkspaceView.swift uses WorkbenchStandardPlotControls")
    func xyUsesStandardPlotControls() throws {
        let source = try loadWorkbenchSource("XYRotationWorkspaceView.swift")
        #expect(source.contains("WorkbenchStandardPlotControls"),
                "XY must use WorkbenchStandardPlotControls — it is a multi-tab stacking workflow")
    }

    // INV-XY-2: XY binds activeTab through the standard controls path
    @Test("XYRotationWorkspaceView.swift binds tabs.activeTab through standard controls")
    func xyBindsActiveTab() throws {
        let source = try loadWorkbenchSource("XYRotationWorkspaceView.swift")
        #expect(source.contains("activeTab: $bindableStore.tabs.activeTab"),
                "XY must pass activeTab binding to WorkbenchStandardPlotControls (tab picker row)")
    }

    // INV-XY-3: XY binds titleTemplate through the standard controls path
    @Test("XYRotationWorkspaceView.swift binds titleTemplate through standard controls")
    func xyBindsTitleTemplate() throws {
        let source = try loadWorkbenchSource("XYRotationWorkspaceView.swift")
        #expect(source.contains("titleTemplate: $bindableStore.titleTemplate"),
                "XY must pass titleTemplate binding to WorkbenchStandardPlotControls")
    }

    // INV-XY-4: XY binds showPlotGrid through the standard controls path
    @Test("XYRotationWorkspaceView.swift binds showPlotGrid through standard controls")
    func xyBindsShowPlotGrid() throws {
        let source = try loadWorkbenchSource("XYRotationWorkspaceView.swift")
        #expect(source.contains("showPlotGrid"),
                "XY must pass showPlotGrid binding to WorkbenchStandardPlotControls (grid toggle)")
    }

    // INV-XY-5: XY binds seriesRenderMode through the standard controls path
    @Test("XYRotationWorkspaceView.swift binds seriesRenderMode through standard controls")
    func xyBindsSeriesRenderMode() throws {
        let source = try loadWorkbenchSource("XYRotationWorkspaceView.swift")
        #expect(source.contains("seriesRenderMode: $bindableStore.tabs.seriesRenderMode"),
                "XY must pass seriesRenderMode binding to WorkbenchStandardPlotControls")
    }

    // INV-XY-6: XY binds chartStyleOverrides through the standard controls path
    @Test("XYRotationWorkspaceView.swift binds chartStyleOverrides through standard controls")
    func xyBindsChartStyleOverrides() throws {
        let source = try loadWorkbenchSource("XYRotationWorkspaceView.swift")
        #expect(source.contains("chartStyleOverrides: $bindableStore.tabs.chartStyleOverrides"),
                "XY must pass chartStyleOverrides binding to WorkbenchStandardPlotControls")
    }

    // INV-XY-7: XY exposes stackOffsetMultiplier through the standard controls path
    @Test("XYRotationWorkspaceView.swift binds stackOffsetMultiplier through standard controls")
    func xyBindsStackOffset() throws {
        let source = try loadWorkbenchSource("XYRotationWorkspaceView.swift")
        #expect(source.contains("stackOffsetMultiplier"),
                "XY must pass stackOffsetMultiplier binding to WorkbenchStandardPlotControls (stack offset slider)")
    }

    // INV-XY-8: XY exposes minGapFraction through the standard controls path
    @Test("XYRotationWorkspaceView.swift binds minGapFraction through standard controls")
    func xyBindsMinGapFraction() throws {
        let source = try loadWorkbenchSource("XYRotationWorkspaceView.swift")
        #expect(source.contains("minGapFraction: $bindableStore.minGapFraction"),
                "XY must pass minGapFraction binding to WorkbenchStandardPlotControls (min-gap field)")
    }

    // INV-XY-9..11: XY workflow-specific controls are present in the view file
    @Test("XYRotationWorkspaceView.swift contains centerBaseline (workflow-specific)")
    func xyContainsCenterBaseline() throws {
        let source = try loadWorkbenchSource("XYRotationWorkspaceView.swift")
        #expect(source.contains("centerBaseline"),
                "centerBaseline is an XY-specific toggle that must be present in the view file")
    }

    @Test("XYRotationWorkspaceView.swift contains linearDetrend (workflow-specific)")
    func xyContainsLinearDetrend() throws {
        let source = try loadWorkbenchSource("XYRotationWorkspaceView.swift")
        #expect(source.contains("linearDetrend"),
                "linearDetrend is an XY-specific toggle that must be present in the view file")
    }

    @Test("XYRotationWorkspaceView.swift contains showAuxiliaryLine180 (workflow-specific)")
    func xyContainsShowAuxiliaryLine180() throws {
        let source = try loadWorkbenchSource("XYRotationWorkspaceView.swift")
        #expect(source.contains("showAuxiliaryLine180"),
                "showAuxiliaryLine180 is an XY-specific toggle that must be present in the view file")
    }

    // INV-XY-12: phi offset controls are in the view file (Assembly-owned panel)
    @Test("XYRotationWorkspaceView.swift contains phiOffsetOverrides (workflow-specific)")
    func xyContainsPhiOffsetOverrides() throws {
        let source = try loadWorkbenchSource("XYRotationWorkspaceView.swift")
        #expect(source.contains("phiOffsetOverrides"),
                "phiOffsetOverrides is Assembly-owned XY state; its controls must appear in the view file outside the standard controls path")
    }

    // INV-XY-13..14: WorkbenchStandardPlotControls does not own XY-specific controls
    @Test("WorkbenchStandardPlotControls.swift does not contain centerBaseline")
    func standardControlsDoesNotOwnCenterBaseline() throws {
        let source = try loadWorkbenchSource("WorkbenchStandardPlotControls.swift")
        #expect(!source.contains("centerBaseline"),
                "centerBaseline must not appear inside WorkbenchStandardPlotControls — it is Assembly-owned, not Plot Controls-owned")
    }

    @Test("WorkbenchStandardPlotControls.swift does not contain linearDetrend")
    func standardControlsDoesNotOwnLinearDetrend() throws {
        let source = try loadWorkbenchSource("WorkbenchStandardPlotControls.swift")
        #expect(!source.contains("linearDetrend"),
                "linearDetrend must not appear inside WorkbenchStandardPlotControls — it is Assembly-owned, not Plot Controls-owned")
    }
}

// MARK: - Suite 3: Three Omega uses WorkbenchStandardPlotControls

@Suite("V7.8C Three Omega standard plot controls path")
struct V78C3OmegaPlotControlsPathTests {

    // INV-3W-1: ThreeOmegaWorkspaceView uses the standard two-row layout
    @Test("ThreeOmegaWorkspaceView.swift uses WorkbenchStandardPlotControls")
    func threeOmegaUsesStandardPlotControls() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        #expect(source.contains("WorkbenchStandardPlotControls"),
                "3ω must use WorkbenchStandardPlotControls — it is a multi-tab stacking workflow")
    }

    // INV-3W-2: 3ω binds activeTab through the standard controls path
    @Test("ThreeOmegaWorkspaceView.swift binds tabs.activeTab through standard controls")
    func threeOmegaBindsActiveTab() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        #expect(source.contains("activeTab: $store.tabs.activeTab"),
                "3ω must pass activeTab binding to WorkbenchStandardPlotControls (tab picker row)")
    }

    // INV-3W-3: 3ω binds titleTemplate through the standard controls path
    @Test("ThreeOmegaWorkspaceView.swift binds titleTemplate through standard controls")
    func threeOmegaBindsTitleTemplate() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        #expect(source.contains("titleTemplate: $store.titleTemplate"),
                "3ω must pass titleTemplate binding to WorkbenchStandardPlotControls")
    }

    // INV-3W-4: 3ω binds showPlotGrid through the standard controls path
    @Test("ThreeOmegaWorkspaceView.swift binds showPlotGrid through standard controls")
    func threeOmegaBindsShowPlotGrid() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        #expect(source.contains("showPlotGrid"),
                "3ω must pass showPlotGrid binding to WorkbenchStandardPlotControls (grid toggle)")
    }

    // INV-3W-5: 3ω binds seriesRenderMode through the standard controls path
    @Test("ThreeOmegaWorkspaceView.swift binds seriesRenderMode through standard controls")
    func threeOmegaBindsSeriesRenderMode() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        #expect(source.contains("seriesRenderMode: $store.tabs.seriesRenderMode"),
                "3ω must pass seriesRenderMode binding to WorkbenchStandardPlotControls")
    }

    // INV-3W-6: 3ω binds chartStyleOverrides through the standard controls path
    @Test("ThreeOmegaWorkspaceView.swift binds chartStyleOverrides through standard controls")
    func threeOmegaBindsChartStyleOverrides() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        #expect(source.contains("chartStyleOverrides: $store.tabs.chartStyleOverrides"),
                "3ω must pass chartStyleOverrides binding to WorkbenchStandardPlotControls")
    }

    // INV-3W-7: 3ω exposes stackOffsetMultiplier through the standard controls path
    @Test("ThreeOmegaWorkspaceView.swift binds stackOffsetMultiplier through standard controls")
    func threeOmegaBindsStackOffset() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        #expect(source.contains("stackOffsetMultiplier"),
                "3ω must pass stackOffsetMultiplier binding to WorkbenchStandardPlotControls (stack offset slider)")
    }

    // INV-3W-8: 3ω exposes minGapFraction through the standard controls path
    @Test("ThreeOmegaWorkspaceView.swift binds minGapFraction through standard controls")
    func threeOmegaBindsMinGapFraction() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        #expect(source.contains("minGapFraction: $store.minGapFraction"),
                "3ω must pass minGapFraction binding to WorkbenchStandardPlotControls (min-gap field)")
    }

    // INV-3W-9..11: 3ω workflow-specific physics controls are present in the view file
    @Test("ThreeOmegaWorkspaceView.swift contains geometry (workflow-specific)")
    func threeOmegaContainsGeometry() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        #expect(source.contains("store.geometry"),
                "geometry is 3ω Assembly-owned state; its controls must appear in the view file outside the standard controls path")
    }

    @Test("ThreeOmegaWorkspaceView.swift contains fitRanges (workflow-specific)")
    func threeOmegaContainsFitRanges() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        #expect(source.contains("fitRanges"),
                "fitRanges is 3ω Assembly-owned state; its controls must appear in the view file outside the standard controls path")
    }

    @Test("ThreeOmegaWorkspaceView.swift contains v3Method (workflow-specific)")
    func threeOmegaContainsV3Method() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        #expect(source.contains("v3Method"),
                "v3Method is 3ω Assembly-owned state; its control must appear in the view file outside the standard controls path")
    }

    // INV-3W-12: RAHE method picker is present (workflow-specific, Assembly-owned)
    @Test("ThreeOmegaWorkspaceView.swift contains RAHE method (workflow-specific)")
    func threeOmegaContainsRAHEMethod() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        #expect(source.contains("updateRAHEMethod"),
                "RAHE method picker is 3ω Assembly-owned; it must appear in the view file outside standard controls ownership")
    }

    // INV-3W-13: overlay controls are present (workflow-specific, Assembly-owned)
    @Test("ThreeOmegaWorkspaceView.swift contains overlay controls (workflow-specific)")
    func threeOmegaContainsOverlayControls() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        #expect(source.contains("overlayRuntime"),
                "overlay controls are 3ω Assembly-owned; they must appear in the view file outside standard controls ownership")
    }

    // INV-3W-14..16: WorkbenchStandardPlotControls does not own 3ω-specific controls
    @Test("WorkbenchStandardPlotControls.swift does not contain v3Method")
    func standardControlsDoesNotOwnV3Method() throws {
        let source = try loadWorkbenchSource("WorkbenchStandardPlotControls.swift")
        #expect(!source.contains("v3Method"),
                "v3Method must not appear inside WorkbenchStandardPlotControls — it is 3ω Assembly-owned, not Plot Controls-owned")
    }

    @Test("WorkbenchStandardPlotControls.swift does not contain geometry")
    func standardControlsDoesNotOwnGeometry() throws {
        let source = try loadWorkbenchSource("WorkbenchStandardPlotControls.swift")
        #expect(!source.contains("geometry"),
                "geometry must not appear inside WorkbenchStandardPlotControls — it is 3ω Assembly-owned, not Plot Controls-owned")
    }

    @Test("WorkbenchStandardPlotControls.swift does not contain fitRanges")
    func standardControlsDoesNotOwnFitRanges() throws {
        let source = try loadWorkbenchSource("WorkbenchStandardPlotControls.swift")
        #expect(!source.contains("fitRanges"),
                "fitRanges must not appear inside WorkbenchStandardPlotControls — it is 3ω Assembly-owned, not Plot Controls-owned")
    }
}
