import CoreGraphics
import Foundation
import Testing
@testable import SpinLabApp

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
    ///      globalPlotDefaults, chartStyleOverrides, stackOffsetMultiplier, and
    ///      minGapFraction through it. Workflow-specific controls
    ///      (centerBaseline, linearDetrend, showAuxiliaryLine180,
    ///      phiOffsetOverrides) are present in the view file but are NOT
    ///      parameters of WorkbenchStandardPlotControls.
///
    ///   3. ThreeOmegaWorkspaceView uses WorkbenchStandardPlotControls, binding
    ///      the same shared set of controls plus globalPlotDefaults.
    ///      Workflow-specific controls (geometry, fitRanges, v3Method, RAHE
    ///      method, overlays) are present in the view file but are NOT
    ///      parameters of WorkbenchStandardPlotControls.
///
    ///   4. IVWorkspaceView uses WorkbenchStandardPlotControls, binding the same
    ///      shared controls path instead of the reduced panel. IV-specific channel
    ///      pickers remain workflow-local extra content, while globalPlotDefaults
    ///      carries the shared font defaults.

// MARK: - Source helpers

private func loadWorkbenchSource(_ filename: String) throws -> String {
    let base = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SpinLabAppTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root

    let path: String
    switch filename {
    case "RSMViewSelector.swift":
        path = "Sources/SpinLabApp/Workbench/V3/Heatmap/RSM/RSMViewSelector.swift"
    case "SharedPlotTextControls.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/SharedPlotTextControls.swift"
    case "SharedPlotTextFieldRow.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/SharedPlotTextFieldRow.swift"
    case "SharedPlotLabelOverrideField.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/SharedPlotLabelOverrideField.swift"
    case "SharedPlotFontSizePicker.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/SharedPlotFontSizePicker.swift"
    case "SharedPlotFontSizeControls.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/SharedPlotFontSizeControls.swift"
    case "PlotControlSection.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/PlotControlSection.swift"
    case "ControlRow.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/ControlRow.swift"
    case "PlotAxisBoundField.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/PlotAxisBoundField.swift"
    case "PlotAxisRangeFormatter.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/PlotAxisRangeFormatter.swift"
    case "SegmentedControlRow.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/SegmentedControlRow.swift"
    case "WorkbenchPlotControlsPanel.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchPlotControlsPanel.swift"
    case "CompactPlotStyleRow.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/CompactPlotStyleRow.swift"
    case "CompactTypographyRow.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/CompactTypographyRow.swift"
    case "WorkbenchSeriesAppearanceControls.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchSeriesAppearanceControls.swift"
    case "WorkbenchStandardPlotControls.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchStandardPlotControls.swift"
    case "WorkbenchStandardPlotControls+StoreDriven.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchStandardPlotControls+StoreDriven.swift"
    case "WorkbenchStandardPlotWorkspaceStore.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchStandardPlotWorkspaceStore.swift"
    case "WorkbenchAxisRangeControls.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchAxisRangeControls.swift"
    case "WorkbenchTitleTemplateField.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchTitleTemplateField.swift"
    case "DualAxisPlotControlsPanel.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/DualAxis/DualAxisPlotControlsPanel.swift"
    default:
        path = "Sources/SpinLabApp/Features/Workbench/\(filename)"
    }

    let url = base.appendingPathComponent(path)
    return try String(contentsOf: url, encoding: .utf8)
}

private func loadHeatmapSource(_ filename: String) throws -> String {
    let base = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SpinLabAppTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
    let url = base.appendingPathComponent("Sources/SpinLabApp/Workbench/V3/Heatmap/\(filename)")
    return try String(contentsOf: url, encoding: .utf8)
}

// MARK: - Suite 0: Shared plot text controls are reusable

@Suite("V7.8C shared plot text controls")
struct V78CSharedPlotTextControlsTests {

    @Test("SharedPlotTextFieldRow.swift is a UI utility only")
    func sharedTextFieldRowIsUtilityOnly() throws {
        let source = try loadWorkbenchSource("SharedPlotTextFieldRow.swift")
        #expect(source.contains("struct SharedPlotTextFieldRow"))
        #expect(source.contains("TextField"))
        #expect(source.contains("WorkbenchUIStyle.controlLabelFont"))
        #expect(source.contains("WorkbenchUIStyle.controlValueFont"))
        #expect(source.contains("row chrome"))
        #expect(!source.contains("Heatmap"))
        #expect(!source.contains("DualAxis"))
        #expect(!source.contains("WorkbenchStandardPlotControls"))
        #expect(!source.contains("WorkbenchPlotControlsPanel"))
        #expect(!source.contains("Clear Plot"))
    }

    @Test("SharedPlotFontSizePicker.swift is a UI utility only")
    func sharedFontSizePickerIsUtilityOnly() throws {
        let source = try loadWorkbenchSource("SharedPlotFontSizePicker.swift")
        #expect(source.contains("struct SharedPlotFontSizePicker"))
        #expect(source.contains("Picker"))
        #expect(source.contains("rawValue: String?"),
                "SharedPlotFontSizePicker binds a key-narrowed rawValue, not a literal globalPlotDefaults dictionary, so it stays reusable across style dictionaries")
        #expect(source.contains("pickerStyle(.menu)"))
        #expect(source.contains("labelFont"))
        #expect(!source.contains("DualAxis"))
        #expect(!source.contains("Heatmap"))
        #expect(!source.contains("WorkbenchStandardPlotControls"))
        #expect(!source.contains("HeatmapPlotControlsPanel"))
    }

    @Test("CompactPlotStyleRow.swift uses menu pickers and ViewThatFits")
    func compactPlotStyleRowUsesWrappedMenuPickers() throws {
        let source = try loadWorkbenchSource("CompactPlotStyleRow.swift")
        #expect(source.contains("ViewThatFits"))
        #expect(source.contains("Draw"))
        #expect(source.contains("Line+Scatter"))
        #expect(source.contains("pickerStyle(.menu)"))
        #expect(source.contains("WorkbenchSeriesAppearanceControls"))
        #expect(source.contains("SharedPlotTickCountControls"))
    }

    @Test("CompactPlotStyleRow.swift builds its own Range+Ticks row instead of nesting WorkbenchAxisRangeControls")
    func compactPlotStyleRowUsesDedicatedRangeTicksRow() throws {
        let source = try loadWorkbenchSource("CompactPlotStyleRow.swift")
        // The Range+Ticks row was later split into two dedicated components —
        // CompactAxisRangeRow and CompactAxisTickCountRow — rather than one
        // combined CompactRangeTicksRow. Both still avoid nesting
        // WorkbenchAxisRangeControls.
        #expect(source.contains("struct CompactAxisRangeRow"),
                "The compact Range row must be a dedicated component, not a composition of WorkbenchAxisRangeControls")
        #expect(source.contains("struct CompactAxisTickCountRow"),
                "The compact Ticks row must be a dedicated component paired with CompactAxisRangeRow")
        #expect(!source.contains("WorkbenchAxisRangeControls("),
                "CompactPlotStyleRow must not instantiate WorkbenchAxisRangeControls")
        #expect(source.contains("AxisRangeFieldRow("),
                "CompactAxisRangeRow must build X/Y range fields directly via the shared AxisRangeFieldRow atom")
        #expect(source.contains("Text(\"Range\")"))
        #expect(source.contains("axisLabel: \"X\""))
        #expect(source.contains("axisLabel: \"Y\""))
    }

    @Test("WorkbenchAxisRangeControls.swift exposes AxisRangeFieldRow for reuse")
    func workbenchAxisRangeControlsExposesSharedFieldRow() throws {
        let source = try loadWorkbenchSource("WorkbenchAxisRangeControls.swift")
        #expect(source.contains("struct AxisRangeFieldRow"),
                "AxisRangeFieldRow must be defined here and be non-private so CompactPlotStyleRow can reuse it")
        #expect(!source.contains("private struct AxisRangeFieldRow"))
    }

    @Test("WorkbenchAxisRangeControls.swift's AxisRangeFieldRow builds min/max via the shared PlotAxisBoundField leaf")
    func axisRangeFieldRowUsesSharedLeaf() throws {
        // v5.5.7: the dead WorkbenchAxisRangeControls wrapper struct was removed;
        // this file now hosts only the shared AxisRangeFieldRow atom (used by
        // CompactAxisRangeRow) and its debug-string helpers.
        let source = try loadWorkbenchSource("WorkbenchAxisRangeControls.swift")
        #expect(!source.contains("struct WorkbenchAxisRangeControls"),
                "the dead WorkbenchAxisRangeControls wrapper must stay removed")
        #expect(source.contains("PlotAxisBoundField("),
                "AxisRangeFieldRow must build its min/max fields via the shared leaf, not a local AxisBoundField")
        #expect(!source.contains("struct AxisBoundField"),
                "the old Cartesian-only AxisBoundField leaf must stay removed")
        #expect(!source.contains("label: \"min\""),
                "Compact layout must not show a separate 'min' caption line above the field")
        #expect(!source.contains("label: \"max\""),
                "Compact layout must not show a separate 'max' caption line above the field")
    }

    @Test("CompactAxisRangeRow renders a single leading 'Range' label per axis pair")
    func compactAxisRangeRowCompactsIntoOneRow() throws {
        let source = try loadWorkbenchSource("CompactPlotStyleRow.swift")
        #expect(source.contains("Text(\"Range\")"),
                "Range controls must carry a single leading 'Range' label, not per-axis 'X range'/'Y range' captions")
        #expect(source.contains("axisLabel: \"X\""))
        #expect(source.contains("axisLabel: \"Y\""))
    }

    @Test("SharedPlotLabelOverrideField.swift reuses the shared text row")
    func labelOverrideFieldReusesSharedTextRow() throws {
        let source = try loadWorkbenchSource("SharedPlotLabelOverrideField.swift")
        #expect(source.contains("SharedPlotTextFieldRow"))
        #expect(source.contains("fieldMaxWidth"))
        #expect(source.contains("commitIfDirty"))
    }

    @Test("ControlRow.swift is shared row chrome only")
    func controlRowIsSharedRowChromeOnly() throws {
        let source = try loadWorkbenchSource("ControlRow.swift")
        #expect(source.contains("struct ControlRow"))
        #expect(source.contains("Text(label)"))
        #expect(source.contains("WorkbenchUIStyle.controlLabelFont"))
        #expect(!source.contains("DualAxis"))
        #expect(!source.contains("ThreeOmega"))
    }

    @Test("PlotAxisBoundField.swift is a reusable numeric atom, workflow-agnostic")
    func plotAxisBoundFieldIsReusableNumericAtom() throws {
        // v5.5.7: CompactNumericField (DualAxis) and the private AxisBoundField
        // (Cartesian) were unified into this single shared leaf.
        let source = try loadWorkbenchSource("PlotAxisBoundField.swift")
        #expect(source.contains("struct PlotAxisBoundField"))
        #expect(source.contains("TextField"))
        #expect(source.contains("sourceResetToken"))
        #expect(source.contains("xmark.circle.fill"))
        #expect(!source.contains("DualAxisPlotControlsPanel"))
        #expect(!source.contains("ThreeOmega"))
        #expect(!source.contains("workflowID") && !source.contains("workflowName"),
                "the shared leaf must not branch on workflow identity")
    }

    @Test("Architecture guard: no production source still defines the old Cartesian-only AxisBoundField or DualAxis-only CompactNumericField")
    func onlySharedLeafRemainsInProduction() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SpinLabAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let sourcesRoot = base.appendingPathComponent("Sources/SpinLabApp")
        let allFiles = try FileManager.default
            .subpathsOfDirectory(atPath: sourcesRoot.path)
            .filter { $0.hasSuffix(".swift") }

        var filesDefiningOldLeaves: [String] = []
        for relativePath in allFiles {
            let src = try String(contentsOf: sourcesRoot.appendingPathComponent(relativePath), encoding: .utf8)
            if src.contains("struct AxisBoundField") || src.contains("struct CompactNumericField") {
                filesDefiningOldLeaves.append(relativePath)
            }
        }
        #expect(filesDefiningOldLeaves.isEmpty,
                "only PlotAxisBoundField may define a per-bound numeric leaf; found old leaf types in: \(filesDefiningOldLeaves)")

        #expect(!FileManager.default.fileExists(atPath: sourcesRoot.appendingPathComponent(
            "Workbench/Modules/PlotSystem/Controls/Common/CompactNumericField.swift").path),
            "the old DualAxis-only CompactNumericField.swift file must be deleted")
    }

    @Test("WorkbenchSeriesAppearanceControls.swift uses menu pickers")
    func seriesAppearanceControlsUseMenuPickers() throws {
        let source = try loadWorkbenchSource("WorkbenchSeriesAppearanceControls.swift")
        #expect(source.contains("Line"))
        #expect(source.contains("Scatter"))
        #expect(source.contains("pickerStyle(.menu)"))
        #expect(source.contains("Text(label)"))
        #expect(!source.contains("ControlRow"))
    }

}

// MARK: - Suite 1: AHE uses the shared standard plot controls adapter

// AHE is single-tab (AHEWorkbenchTab has exactly one case, .ahe), so it hides the
// adapter's built-in tab row via `hideTabRow: true` and relocates stack/gap next to the
// title field via `titleRowTrailingContent` — the same pattern IV and 3ω use for their
// own workspace-level tab strips. This closed a gap left when AHE was first split out at
// Gate 7.8, before `hideTabRow`/`titleRowTrailingContent` existed on the adapter.
@Suite("V7.8C AHE uses WorkbenchStandardPlotControls")
struct V78CAHEPlotControlsPathTests {

    // INV-AHE-3: AHE exposes title template through the adapter.
    // v5.3.8: titleTemplate/showGrid/showTitle/seriesRenderMode/chartStyleOverrides are no
    // longer bound field-by-field in each workflow view — AHEWorkspaceView passes
    // `store: ahe` and the shared store-driven initializer derives all of them from the
    // `WorkbenchStandardPlotWorkspaceStore` conformance once. See INV-STORE-DRIVEN below.
    @Test("AHEWorkspaceView.swift binds titleTemplate")
    func aheCustomPathBindsTitleTemplate() throws {
        let source = try loadWorkbenchSource("AHEWorkspaceView.swift")
        #expect(source.contains("store: ahe"),
                "AHE must pass its store to the shared store-driven WorkbenchStandardPlotControls initializer, which derives titleTemplate")
    }

    // INV-AHE-5b: AHE exposes global plot defaults
    @Test("AHEWorkspaceView.swift binds globalPlotDefaults")
    func aheCustomPathBindsGlobalPlotDefaults() throws {
        let source = try loadWorkbenchSource("AHEWorkspaceView.swift")
        #expect(source.contains("globalPlotDefaults: $workbench.globalPlotDefaults"),
                "AHE must bind the shared globalPlotDefaults")
    }

    // INV-AHE-9: AHE still has exactly one tab — no tab picker in the UI.
    @Test("AHEWorkspaceView.swift does not render a tab picker")
    func aheDoesNotExposeTabPicker() throws {
        let source = try loadWorkbenchSource("AHEWorkspaceView.swift")
        #expect(!source.contains("WorkbenchPlotTabPicker"),
                "AHE must not show a tab picker — it has exactly one tab (AHEWorkbenchTab.ahe)")
        #expect(!source.contains("WorkbenchPlotNavigationStrip"),
                "AHE must not directly reference the tab+stack+gap combined strip — hideTabRow suppresses it inside the adapter")
    }

}

// MARK: - Suite 2: XY Rotation uses WorkbenchStandardPlotControls

@Suite("V7.8C XY Rotation standard plot controls path")
struct V78CXYPlotControlsPathTests {

    // INV-XY-7b: XY flushes the interaction snapshot when controls change
    @Test("XYRotationWorkspaceView.swift flushes interaction snapshot after control changes")
    func xyFlushesInteractionSnapshot() throws {
        let source = try loadWorkbenchSource("XYRotationWorkspaceView.swift")
        #expect(source.contains("scheduleInteractionSnapshotFlush(source:"),
                "XY must flush the interaction snapshot after control changes so overrides persist promptly — the codebase migrated from the immediate flushInteractionSnapshotNow() call to the debounced scheduleInteractionSnapshotFlush(source:), consistent with the other workflow views")
    }

}

// MARK: - Suite 3: Three Omega uses WorkbenchStandardPlotControls

@Suite("V7.8C Three Omega standard plot controls path")
struct V78C3OmegaPlotControlsPathTests {

    // INV-3W-2: 3ω binds activeTab through the standard controls path
    @Test("ThreeOmegaWorkspaceView.swift binds tabs.activeTab through standard controls")
    func threeOmegaBindsActiveTab() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        #expect(source.contains("activeTab: $store.tabs.activeTab"),
                "3ω must pass activeTab binding to WorkbenchStandardPlotControls (tab picker row)")
    }

    @Test("ThreeOmegaWorkspaceView.swift binds globalPlotDefaults through standard controls")
    func threeOmegaBindsGlobalPlotDefaults() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        #expect(source.contains("globalPlotDefaults: $workbench.globalPlotDefaults"),
                "3ω must pass globalPlotDefaults binding to WorkbenchStandardPlotControls")
    }

}

// MARK: - Suite 3b: DualAxis keeps its own grouped controls while reusing text rows

@Suite("V7.8C DualAxis control ownership")
struct V78CDualAxisPlotControlsPathTests {

}

// MARK: - Suite 4: IV uses WorkbenchStandardPlotControls

@Suite("V7.8C IV standard plot controls path")
struct V78CIVPlotControlsPathTests {

    @Test("IVWorkspaceView.swift binds activeTab through standard controls")
    func ivBindsActiveTab() throws {
        let source = try loadWorkbenchSource("IVWorkspaceView.swift")
        #expect(source.contains("activeTab: $store.tabs.activeTab"),
                "IV must pass activeTab binding to WorkbenchStandardPlotControls")
    }

    @Test("IVWorkspaceView.swift binds globalPlotDefaults through standard controls")
    func ivBindsGlobalPlotDefaults() throws {
        let source = try loadWorkbenchSource("IVWorkspaceView.swift")
        #expect(source.contains("globalPlotDefaults: $workbench.globalPlotDefaults"),
                "IV must pass globalPlotDefaults binding to WorkbenchStandardPlotControls")
    }

    @Test("IVWorkspaceStore.swift renders through TabRenderManager buildPipelineInput")
    func ivStoreUsesBuildPipelineInput() throws {
        let source = try loadWorkbenchSource("IVWorkspaceStore.swift")
        #expect(source.contains("tabs.buildPipelineInput("),
                "IV rerender must route payloads through TabRenderManager.buildPipelineInput with captured display state")
        #expect(source.contains("payload: displayPayload"),
                "IV rerender must build the pipeline from the stacked display payload")
        #expect(source.contains("tabState: tabState"),
                "IV rerender must capture the current tab display state before rendering")
        #expect(source.contains("legendAnchor: tabs.legendAnchor"),
                "IV rerender must pass shell-level legend anchoring into the render input")
        #expect(source.contains("manifestPayload: manifestPayload"),
                "IV rerender must preserve the manifest payload separately from the display payload")
        #expect(source.contains("displayPayload: displayPayload"),
                "IV rerender must store the stacked display payload for export")
    }

    @Test("IVWorkspaceStore.swift exposes standard plot binding state")
    func ivStoreExposesStandardPlotBindingState() throws {
        let source = try loadWorkbenchSource("IVWorkspaceStore.swift")
        #expect(source.contains("stackOffsetMultiplier"),
                "IV store must expose stackOffsetMultiplier for WorkbenchStandardPlotControls")
        #expect(source.contains("minGapFraction"),
                "IV store must expose minGapFraction for WorkbenchStandardPlotControls")
        #expect(source.contains("xCurrentBasis"),
                "IV store must expose xCurrentBasis for the IV basis selector")
        #expect(source.contains("updateTitleOverride"),
                "IV store must expose title override mutation through TabRenderManager")
        #expect(source.contains("updateXLabelOverride"),
                "IV store must expose X label override mutation through TabRenderManager")
        #expect(source.contains("updateYLabelOverride"),
                "IV store must expose Y label override mutation through TabRenderManager")
    }
}

// MARK: - Suite 4b: RT uses WorkbenchStandardPlotControls

@Suite("V7.8C RT standard plot controls path")
struct V78CRTPlotControlsPathTests {

}

// MARK: - Suite 4c: v5.3.8 store-driven consolidation boundary
//
// AHE/IV/RT/XY used to each define a private PlotControlsPanel wrapper forwarding ~25
// named arguments 1:1 from `store`/`store.tabs` into `WorkbenchStandardPlotControls`. That
// derivation now lives once in `WorkbenchStandardPlotControls+StoreDriven.swift`, driven by
// `WorkbenchStandardPlotWorkspaceStore` conformance (`WorkbenchStandardPlotWorkspaceStore.swift`).
// These tests protect that single ownership: the four workflow stores conform, the shared
// initializer derives the standard fields once, and per-view files no longer duplicate that
// derivation.
@Suite("V5.3.8 store-driven standard plot controls boundary")
struct V538StoreDrivenPlotControlsBoundaryTests {

    @Test("WorkbenchStandardPlotWorkspaceStore.swift is the sole conformance point for AHE/IV/RT/XY")
    func fourStoresConformToSharedProtocol() throws {
        let source = try loadWorkbenchSource("WorkbenchStandardPlotWorkspaceStore.swift")
        #expect(source.contains("protocol WorkbenchStandardPlotWorkspaceStore"))
        for storeName in ["AHEWorkspaceStore", "IVWorkspaceStore", "RTWorkspaceStore", "XYRotationWorkspaceStore"] {
            #expect(source.contains("extension \(storeName): WorkbenchStandardPlotWorkspaceStore {}"),
                    "\(storeName) must conform to WorkbenchStandardPlotWorkspaceStore so it can use the shared store-driven initializer")
        }
        // RSM/3ω are intentionally excluded — RSM uses HeatmapPlotControlsPanel, 3ω keeps
        // its own bespoke wiring (DualAxisPlotControlsPanel + workflow-specific extras).
        #expect(!source.contains("RSMWorkspaceStore"))
        #expect(!source.contains("ThreeOmegaWorkspaceStore"))
    }

    @Test("AHE/IV/RT/XY workflow views no longer forward the standard field set by hand")
    func perWorkflowViewsDoNotDuplicateStandardFieldForwarding() throws {
        for filename in ["AHEWorkspaceView.swift", "IVWorkspaceView.swift", "RTWorkspaceView.swift", "XYRotationWorkspaceView.swift"] {
            let source = try loadWorkbenchSource(filename)
            #expect(!source.contains("seriesOrderPayload:"),
                    "\(filename) must not re-forward seriesOrderPayload — it is derived by the shared store-driven initializer")
            #expect(!source.contains("activeLayout:"),
                    "\(filename) must not re-forward activeLayout — it is derived by the shared store-driven initializer")
            #expect(!source.contains("sourceResetToken:"),
                    "\(filename) must not re-forward sourceResetToken — it is derived by the shared store-driven initializer")
        }
    }

}

// MARK: - Suite 5: RSM uses a dedicated heatmap plot controls surface

@Suite("V7.8C RSM heatmap plot controls path")
struct V78CRSMPlotControlsPathTests {

    @Test("RSMWorkspaceView.swift does not use WorkbenchStandardPlotControls")
    func rsmDoesNotUseStandardPlotControls() throws {
        let source = try loadWorkbenchSource("RSMWorkspaceView.swift")
        #expect(!source.contains("WorkbenchStandardPlotControls"),
                "RSM must not use the XY-specific WorkbenchStandardPlotControls container")
    }

    @Test("WorkbenchPlotActionStrip.swift stays in the shared result shell")
    func actionStripStaysInSharedResultShell() throws {
        let source = try loadWorkbenchSource("WorkbenchPlotActionStrip.swift")
        #expect(source.contains("Clear Plot"))
        #expect(source.contains("isClearPlotDisabled"))
        #expect(!source.contains("WorkbenchStandardPlotControls"))
        #expect(!source.contains("DualAxisPlotControlsPanel"))
        #expect(!source.contains("HeatmapPlotControlsPanel"))
    }

    @Test("RSMWorkspaceView.swift no longer hardcodes Title/X/Y field widths")
    func rsmDoesNotHardcodeTextFieldWidths() throws {
        let source = try loadWorkbenchSource("RSMWorkspaceView.swift")
        #expect(!source.contains("fieldMaxWidth: 200"),
                "RSM heatmap controls must not hardcode a wider Title field")
        #expect(!source.contains("fieldMaxWidth: 80"),
                "RSM heatmap controls must not hardcode narrower X/Y fields")
    }

    // INV-RSM-PL-3: Color Scale label uses primary foreground (not secondary)
    @Test("RSMWorkspaceView.swift Color Scale label uses primary text color")
    func rsmColorScaleLabelIsPrimary() throws {
        let source = try loadWorkbenchSource("RSMViewSelector.swift")
        #expect(source.contains("WorkbenchUIStyle.primaryTextColor"),
                "RSM selector must use primary text styling for the active label")
        #expect(source.contains("Text(\"View\")"),
                "RSM selector must keep the view label inside the workflow-specific component")
    }

    @Test("RSMViewSelector.swift remains RSM-specific")
    func rsmViewSelectorRemainsSpecific() throws {
        let source = try loadWorkbenchSource("RSMViewSelector.swift")
        #expect(source.contains("RSMView.allCases"))
        #expect(source.contains("isViewCompatible"))
        #expect(source.contains("Recommended:"))
        #expect(source.contains("WorkbenchUIStyle.primaryTextColor"))
        #expect(source.contains("exclamationmark.triangle"))
        #expect(!source.contains("SharedPlotTextControls"))
        #expect(!source.contains("SharedPlotFontSizeControls"))
        #expect(!source.contains("HeatmapColorScaleControls"))
        #expect(!source.contains("HeatmapPlotControlsPanel"))
    }

    @Test("HeatmapZRangeControl hides Custom from the percentile picker")
    func heatmapZRangeControlHidesCustomPreset() throws {
        let source = try loadHeatmapSource("HeatmapZRangeControl.swift")
        #expect(source.contains("ViewThatFits(in: .horizontal)"))
        #expect(source.contains("ForEach(HeatmapPercentilePreset.visiblePresets"))
        #expect(source.contains("get: { zDomainState.percentilePreset == .custom ? .p1_99 : zDomainState.percentilePreset }"))
        #expect(!source.contains("HeatmapPercentilePreset.allCases"))
        #expect(source.contains("validationIssue"))
        #expect(source.contains("Min"))
        #expect(source.contains("Max"))
        #expect(source.contains("Preset"))
    }

    // INV-RSM-PL-4: Default Z label for "Detector" column normalizes to publication standard
    @Test("publicationZLabel maps Detector to Intensity (counts)")
    func rsmPublicationZLabelNormalizesDetector() {
        #expect(RSMWorkspaceStore.publicationZLabel(for: "Detector") == "Intensity (counts)",
                "Generic 'Detector' column must normalize to 'Intensity (counts)' for publication use")
        #expect(RSMWorkspaceStore.publicationZLabel(for: "detector") == "Intensity (counts)",
                "Case-insensitive match: 'detector' must also normalize")
        #expect(RSMWorkspaceStore.publicationZLabel(for: "") == "Intensity (counts)",
                "Empty column name must also produce publication default")
    }

    // INV-RSM-PL-5: Custom column names are preserved
    @Test("publicationZLabel preserves custom non-standard column names")
    func rsmPublicationZLabelPreservesCustomNames() {
        #expect(RSMWorkspaceStore.publicationZLabel(for: "Intensity") == "Intensity",
                "Non-generic column name 'Intensity' must pass through unchanged")
        #expect(RSMWorkspaceStore.publicationZLabel(for: "κ (W/m·K)") == "κ (W/m·K)",
                "Custom column name must be preserved as-is")
    }

    // INV-RSM-PL-5b: renderedZLabel returns label exactly as provided (no auto-prefix)
    @Test("HeatmapRenderer.renderedZLabel returns label unchanged in all modes")
    func rsmLogModeZLabelNoPrefix() {
        #expect(HeatmapRenderer.renderedZLabel("Intensity (counts)", mode: .linear) == "Intensity (counts)",
                "Linear mode must return label unchanged")
        #expect(HeatmapRenderer.renderedZLabel("Intensity (counts)", mode: .log10) == "Intensity (counts)",
                "Log10 mode must not auto-prefix the Z/colorbar label")
        #expect(HeatmapRenderer.renderedZLabel("My Custom", mode: .log10) == "My Custom",
                "Log10 mode must not add any prefix to custom labels")
        let userLog = HeatmapRenderer.renderedZLabel("log10 Intensity (counts)", mode: .log10)
        #expect(userLog == "log10 Intensity (counts)",
                "User-supplied prefix must be preserved exactly as entered")
    }

    // INV-RSM-PL-7: Large font sizes produce sufficient left padding to avoid y-axis overlap
    @Test("HeatmapPlotLayout large fonts produce non-overlapping y-axis geometry")
    func rsmLargeFontsYAxisNoOverlap() {
        var style = WorkbenchChartStyle()
        style.titleFontSize = 28
        style.axisTitleFontSize = 24
        style.tickLabelFontSize = 22

        // Fractional RSM-style y-values produce wide tick labels (e.g. "-0.125", "0.625")
        // that stress-test the text-measurement-based layout expansion at large font sizes.
        // Integer-only values like [0, 1] produce labels too narrow to trigger expansion.
        let grid = HeatmapGrid(
            xValues: [0.0, 0.5, 1.0],
            yValues: [-0.125, 0.250, 0.625, 1.000],
            zMatrix: [
                [0.0, 0.5, 1.0],
                [0.5, 1.0, 1.5],
                [1.0, 1.5, 2.0],
                [1.5, 2.0, 2.5]
            ]
        )
        let payload = HeatmapPlotPayload(
            workflowID: "rsm", title: "Large font test",
            xLabel: "H (r.l.u.)", yLabel: "L (r.l.u.)", zLabel: "Intensity (counts)",
            grid: grid
        )
        let layout = HeatmapPlotLayout.compute(payload: payload, chartStyle: style)

        let paddingLeft = layout.gridRect.minX

        // Wide tick labels at 22pt must force paddingLeft beyond the 80pt base minimum.
        #expect(paddingLeft > 80,
                "At tick=22pt with fractional labels like \"-0.125\", paddingLeft must expand beyond the 80pt base")

        // Y-axis title right edge must not reach into the tick label lane.
        // Tick labels occupy [paddingLeft - tickToPlotGap(8) - labelWidth .. paddingLeft - 8].
        let titleRightEdge = layout.yLabelCenter.x + style.axisTitleFontSize / 2
        let tickLabelTrailingX = paddingLeft - 8  // tickToPlotGap
        #expect(titleRightEdge < tickLabelTrailingX,
                "Y-axis title right edge must not extend into the tick label lane")
    }

    // INV-RSM-PL-8: Fixed-H data recommends KL view
    @Test("CanonicalRSMDataset recommends KL view for fixed-H data")
    func rsmFixedHRecommendsKL() throws {
        let rsmTextFixedH = """
H     K     L     Detector
0.0   0.0   1.0   10.0
0.0   0.5   1.0   20.0
0.0   0.0   2.0   30.0
0.0   0.5   2.0   40.0
"""
        let dataset = try RSMDataParser.parse(text: rsmTextFixedH, title: "KL scan")
        #expect(dataset.recommendedView == .kl,
                "When H is fixed, recommended view must be KL")
        #expect(dataset.isViewCompatible(.kl),
                "KL view must be compatible when H is fixed")
        #expect(!dataset.isViewCompatible(.hl),
                "HL view must be incompatible when H is fixed — H doesn't vary")
        #expect(!dataset.isViewCompatible(.hk),
                "HK view must be incompatible when H is fixed")
    }

    // INV-RSM-PL-8b: Fixed-K data recommends HL view
    @Test("CanonicalRSMDataset recommends HL view for fixed-K data")
    func rsmFixedKRecommendsHL() throws {
        let rsmTextFixedK = """
H     K     L     Detector
-1.0  0.0   1.0   100.0
 0.0  0.0   1.0   200.0
 1.0  0.0   1.0   150.0
-1.0  0.0   1.5   110.0
 0.0  0.0   1.5   250.0
 1.0  0.0   1.5   180.0
"""
        let dataset = try RSMDataParser.parse(text: rsmTextFixedK, title: "HL scan")
        #expect(dataset.recommendedView == .hl,
                "When K is fixed, recommended view must be HL")
        #expect(dataset.isViewCompatible(.hl))
        #expect(!dataset.isViewCompatible(.kl))
        #expect(!dataset.isViewCompatible(.hk))
    }

    // INV-RSM-PL-9: View picker shows warning icon for incompatible view
    @Test("RSMViewSelector.swift shows warning icon when view is incompatible with data")
    func rsmShowsViewCompatibilityWarning() throws {
        let source = try loadWorkbenchSource("RSMViewSelector.swift")
        #expect(source.contains("isViewCompatible"),
                "View picker must check isViewCompatible to show compatibility warning")
        #expect(source.contains("exclamationmark.triangle") || source.contains("exclamationmark"),
                "View picker must show a warning symbol when the selected view is incompatible")
    }

    @Test("RSMWorkspaceView.swift does not expose XY-only controls")
    func rsmDoesNotExposeXYOnlyControls() throws {
        let source = try loadWorkbenchSource("RSMWorkspaceView.swift")
        #expect(!source.contains("seriesRenderMode"),
                "RSM must not expose line/scatter render mode")
        #expect(!source.contains("seriesOrder"),
                "RSM must not expose series order controls")
        #expect(!source.contains("legendLabel"),
                "RSM must not expose legend label override controls")
        #expect(!source.contains("pointLabel"),
                "RSM must not expose point label controls")
        #expect(!source.contains("stackOffset"),
                "RSM must not expose stack offset controls")
    }
}
