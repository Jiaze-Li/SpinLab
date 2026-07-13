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
    case "CompactNumericField.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/CompactNumericField.swift"
    case "RangeControlRow.swift":
        path = "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/RangeControlRow.swift"
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

    @Test("SharedPlotTextControls.swift defines Plot title/X/Y fields")
    func sharedTextControlsDefinesFields() throws {
        let source = try loadWorkbenchSource("SharedPlotTextControls.swift")
        #expect(source.contains("label: \"Plot title\""))
        #expect(source.contains("label: \"X\""))
        #expect(source.contains("label: \"Y\""))
        #expect(!source.contains("DualAxis"))
        #expect(!source.contains("HeatmapPlotControlsPanel"))
    }

    @Test("SharedPlotTextControls.swift uses proportional 3:1:1 weights")
    func sharedTextControlsUsesProportions() throws {
        let source = try loadWorkbenchSource("SharedPlotTextControls.swift")
        #expect(source.contains("plotControlWeight(3)"))
        #expect(source.contains("plotControlWeight(1)"))
        #expect(source.contains(".frame(maxWidth: .infinity)"))
        #expect(!source.contains("WorkbenchStandardPlotControls"))
    }

    @Test("SharedPlotFontSizeControls.swift owns title/axis/tick font sizes")
    func sharedFontSizeControlsOwnsSharedSizes() throws {
        let source = try loadWorkbenchSource("SharedPlotFontSizeControls.swift")
        #expect(source.contains("titleFontSize"))
        #expect(source.contains("axisTitleFontSize"))
        #expect(source.contains("tickLabelFontSize"))
        #expect(source.contains("Font Size"))
        #expect(!source.contains("DualAxis"))
        #expect(!source.contains("HeatmapPlotControlsPanel"))
        #expect(!source.contains("Text(\"Size\")"))
    }

    @Test("WorkbenchPlotControlsPanel.swift reuses SharedPlotFontSizePicker")
    func plotControlsPanelReusesSharedFontPicker() throws {
        let source = try loadWorkbenchSource("WorkbenchPlotControlsPanel.swift")
        #expect(source.contains("CompactPlotStyleRow"))
        #expect(source.contains("CompactTypographyRow"))
        #expect(!source.contains("GroupBox(\"Plot Controls\""))
        // The file's own boundary doc comment names DualAxis/Heatmap (to say this
        // shell must not become a universal one for them — see PLOT_SYSTEM.md
        // "Plot Controls Shell Blocks"), so assert on actual component usage
        // rather than a bare substring that the comment itself would trip.
        #expect(!source.contains("DualAxisPlotControlsPanel("))
        #expect(!source.contains("HeatmapPlotControlsPanel("))
        #expect(!source.contains("Picker(\"Legend\""))
        #expect(!source.contains("Picker(\"Point\""))
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

    @Test("CompactTypographyRow.swift uses compact font pickers")
    func compactTypographyRowUsesCompactFontPickers() throws {
        let source = try loadWorkbenchSource("CompactTypographyRow.swift")
        #expect(source.contains("ViewThatFits"))
        #expect(source.contains("Font"))
        #expect(source.contains("legendFontSize"))
        #expect(source.contains("pointLabelFontSize"))
        #expect(source.contains("pickerWidth: 50"))
    }

    @Test("WorkbenchTitleTemplateField.swift reuses the shared text row")
    func titleTemplateFieldReusesSharedTextRow() throws {
        let source = try loadWorkbenchSource("WorkbenchTitleTemplateField.swift")
        #expect(source.contains("SharedPlotTextFieldRow"))
        #expect(source.contains("label: \"Title template\""))
        #expect(source.contains("placeholder: \"#tab #device #sample\""))
    }

    @Test("WorkbenchAxisRangeControls.swift compacts X/Y ranges onto one Range row")
    func axisRangeControlsCompactsIntoOneRow() throws {
        let source = try loadWorkbenchSource("WorkbenchAxisRangeControls.swift")
        #expect(source.contains("Text(\"Range\")"),
                "Range controls must carry a single leading 'Range' label, not per-axis 'X range'/'Y range' captions")
        #expect(source.contains("axisLabel: \"X\""))
        #expect(source.contains("axisLabel: \"Y\""))
        #expect(source.contains("AxisBoundField("))
        #expect(!source.contains("label: \"min\""),
                "Compact layout must not show a separate 'min' caption line above the field")
        #expect(!source.contains("label: \"max\""),
                "Compact layout must not show a separate 'max' caption line above the field")
    }

    @Test("SharedPlotLabelOverrideField.swift reuses the shared text row")
    func labelOverrideFieldReusesSharedTextRow() throws {
        let source = try loadWorkbenchSource("SharedPlotLabelOverrideField.swift")
        #expect(source.contains("SharedPlotTextFieldRow"))
        #expect(source.contains("fieldMaxWidth"))
        #expect(source.contains("commitIfDirty"))
    }

    @Test("PlotControlSection.swift is a section wrapper only")
    func plotControlSectionIsWrapperOnly() throws {
        let source = try loadWorkbenchSource("PlotControlSection.swift")
        #expect(source.contains("struct PlotControlSection"))
        #expect(source.contains("GroupBox"))
        #expect(source.contains("VStack"))
        #expect(!source.contains("DualAxis"))
        #expect(!source.contains("ThreeOmega"))
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

    @Test("CompactNumericField.swift is a reusable numeric atom")
    func compactNumericFieldIsReusableNumericAtom() throws {
        let source = try loadWorkbenchSource("CompactNumericField.swift")
        #expect(source.contains("struct CompactNumericField"))
        #expect(source.contains("TextField"))
        #expect(source.contains("sourceResetToken"))
        #expect(source.contains("xmark.circle.fill"))
        #expect(!source.contains("DualAxisPlotControlsPanel"))
        #expect(!source.contains("ThreeOmega"))
    }

    @Test("RangeControlRow.swift composes two numeric fields")
    func rangeControlRowComposesTwoNumericFields() throws {
        let source = try loadWorkbenchSource("RangeControlRow.swift")
        #expect(source.contains("struct RangeControlRow"))
        #expect(source.contains("CompactNumericField"))
        #expect(source.contains("Reset"))
        #expect(!source.contains("DualAxisPlotControlsPanel"))
        #expect(!source.contains("ThreeOmegaGeometryPanel"))
    }

    @Test("SegmentedControlRow.swift is shared picker chrome")
    func segmentedControlRowIsSharedPickerChrome() throws {
        let source = try loadWorkbenchSource("SegmentedControlRow.swift")
        #expect(source.contains("struct SegmentedControlRow"))
        #expect(source.contains("Picker"))
        #expect(source.contains("pickerStyle(.segmented)"))
        #expect(!source.contains("DualAxis"))
        #expect(!source.contains("ThreeOmega"))
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

    @Test("SharedPlotTextControls.swift does not define OptionalPlotZLabelControl")
    func optionalZLabelControlRemovedFromSharedControls() throws {
        let source = try loadWorkbenchSource("SharedPlotTextControls.swift")
        #expect(!source.contains("OptionalPlotZLabelControl"))
        #expect(source.contains("label: \"Plot title\""))
        #expect(source.contains("label: \"X\""))
        #expect(source.contains("label: \"Y\""))
    }
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

    @Test("AHEWorkspaceView.swift custom path binds showTitle")
    func aheCustomPathBindsShowTitle() throws {
        let source = try loadWorkbenchSource("AHEWorkspaceView.swift")
        #expect(source.contains("updateShowTitle"),
                "AHE Title checkbox must bind into the active tab's showTitle state")
        #expect(source.contains("aheTitleVisibility"),
                "AHE Title checkbox must schedule a dedicated visibility rerender snapshot flush")
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

    // INV-AHE-5b: AHE custom path exposes global plot defaults
    @Test("AHEWorkspaceView.swift custom path binds globalPlotDefaults")
    func aheCustomPathBindsGlobalPlotDefaults() throws {
        let source = try loadWorkbenchSource("AHEWorkspaceView.swift")
        #expect(source.contains("globalPlotDefaults: $workbench.globalPlotDefaults"),
                "AHE custom plot controls path must bind the shared globalPlotDefaults")
    }

    @Test("AHEWorkspaceView.swift uses SharedPlotTextControls")
    func aheUsesSharedTextControls() throws {
        let source = try loadWorkbenchSource("AHEWorkspaceView.swift")
        #expect(source.contains("SharedPlotTextControls"),
                "AHE must reuse the shared title/X/Y row rather than owning a separate layout")
    }

    // INV-AHE-6: AHE custom path exposes a legend rename UI path
    @Test("AHEWorkspaceView.swift exposes WorkbenchSeriesOrderPanel rename path")
    func aheCustomPathBindsSeriesRename() throws {
        let source = try loadWorkbenchSource("AHEWorkspaceView.swift")
        #expect(source.contains("WorkbenchSeriesOrderPanel"),
                "AHE custom path must expose a reachable series rename UI path")
        #expect(source.contains("allowsReordering: true"),
                "AHE plot path must expose drag-reordering controls now that the plot is reorderable")
        #expect(source.contains("updateSeriesOrder"),
                "AHE reorder path must commit the new visual series order back to store state")
        #expect(source.contains("updateSeriesLabel"),
                "AHE rename path must call through to updateSeriesLabel")
    }

    // INV-AHE-7: AHE is single-tab but is still a CartesianXY stacked-curve workflow —
    // it exposes real stack offset via WorkbenchPlotSpacingInlineControls, without a tab
    // picker (WorkbenchPlotNavigationStrip / WorkbenchStandardPlotControls are not used).
    @Test("AHEWorkspaceView.swift binds stackOffsetMultiplier via WorkbenchPlotSpacingInlineControls")
    func aheExposesStackOffset() throws {
        let source = try loadWorkbenchSource("AHEWorkspaceView.swift")
        #expect(source.contains("stackOffsetMultiplier"),
                "AHE must expose stackOffsetMultiplier — AHE joined RT/IV/XYRotation as a stacked-curve workflow")
        #expect(source.contains("WorkbenchPlotSpacingInlineControls"),
                "AHE must reuse the shared spacing controls, not a bespoke slider")
    }

    // INV-AHE-8: AHE exposes min gap fraction alongside stack offset (same reuse point)
    @Test("AHEWorkspaceView.swift binds minGapFraction via WorkbenchPlotSpacingInlineControls")
    func aheExposesMinGapFraction() throws {
        let source = try loadWorkbenchSource("AHEWorkspaceView.swift")
        #expect(source.contains("minGapFraction"),
                "AHE must expose minGapFraction — same stacking support as RT/IV/XYRotation")
    }

    // INV-AHE-9: AHE still has exactly one tab — no tab picker in the UI.
    @Test("AHEWorkspaceView.swift does not render a tab picker")
    func aheDoesNotExposeTabPicker() throws {
        let source = try loadWorkbenchSource("AHEWorkspaceView.swift")
        #expect(!source.contains("WorkbenchPlotTabPicker"),
                "AHE must not show a tab picker — it has exactly one tab (AHEWorkbenchTab.ahe)")
        #expect(!source.contains("WorkbenchPlotNavigationStrip"),
                "AHE must not pull in the tab+stack+gap combined strip — only the spacing half applies")
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

    @Test("XYRotationWorkspaceView.swift binds showTitle through standard controls")
    func xyBindsShowTitle() throws {
        let source = try loadWorkbenchSource("XYRotationWorkspaceView.swift")
        #expect(source.contains("showTitle: Binding("),
                "XY must pass the active-tab showTitle binding to WorkbenchStandardPlotControls")
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

    // INV-XY-6b: XY binds global plot defaults through the standard controls path
    @Test("XYRotationWorkspaceView.swift binds globalPlotDefaults through standard controls")
    func xyBindsGlobalPlotDefaults() throws {
        let source = try loadWorkbenchSource("XYRotationWorkspaceView.swift")
        #expect(source.contains("globalPlotDefaults: $bindableWorkbench.globalPlotDefaults"),
                "XY must pass globalPlotDefaults binding to WorkbenchStandardPlotControls")
    }

    // INV-XY-7b: XY flushes the interaction snapshot when controls change
    @Test("XYRotationWorkspaceView.swift flushes interaction snapshot after control changes")
    func xyFlushesInteractionSnapshot() throws {
        let source = try loadWorkbenchSource("XYRotationWorkspaceView.swift")
        #expect(source.contains("scheduleInteractionSnapshotFlush(source:"),
                "XY must flush the interaction snapshot after control changes so overrides persist promptly — the codebase migrated from the immediate flushInteractionSnapshotNow() call to the debounced scheduleInteractionSnapshotFlush(source:), consistent with the other workflow views")
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

    @Test("WorkbenchStandardPlotControls.swift uses SharedPlotTextControls")
    func standardControlsUsesSharedTextControls() throws {
        let source = try loadWorkbenchSource("WorkbenchStandardPlotControls.swift")
        #expect(source.contains("SharedPlotTextControls"),
                "The standard workflow controls must reuse the shared title/X/Y component")
    }

    @Test("WorkbenchStandardPlotControls.swift stays Cartesian-only")
    func standardControlsStayCartesianOnly() throws {
        let source = try loadWorkbenchSource("WorkbenchStandardPlotControls.swift")
        #expect(source.contains("WorkbenchPlotControlsPanel"))
        #expect(source.contains("SharedPlotTextControls"))
        #expect(source.contains("WorkbenchTitleTemplateField"))
        #expect(!source.contains("DualAxisPlotControlsPanel"))
        #expect(!source.contains("DualAxisDisplayState"))
        #expect(!source.contains("DualAxisRenderPipeline"))
        #expect(!source.contains("HeatmapPlotControlsPanel"))
        #expect(!source.contains("HeatmapColorScaleControls"))
        #expect(!source.contains("HeatmapZLabelControl"))
        #expect(!source.contains("HeatmapZRangeControl"))
    }

    @Test("WorkbenchStandardPlotControls.swift does not show heatmap-only Z/colorbar controls")
    func standardControlsDoesNotShowZControls() throws {
        let source = try loadWorkbenchSource("WorkbenchStandardPlotControls.swift")
        #expect(!source.contains("HeatmapZLabelControl"),
                "Ordinary Cartesian XY controls must not mount the optional Z/colorbar label control")
        #expect(!source.contains("HeatmapColorScaleControls"),
                "Ordinary Cartesian XY controls must not expose heatmap color scale controls")
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

    @Test("DualAxisPlotControlsPanel.swift stays DualAxis-only")
    func dualAxisControlsStayDualAxisOnly() throws {
        let source = try loadWorkbenchSource("DualAxisPlotControlsPanel.swift")
        #expect(source.contains("DualAxisDisplayState"))
        #expect(source.contains("DualAxisControlWeightedRowLayout"))
        #expect(source.contains("LabelOverrideField"))
        #expect(source.contains("showTitle: $displayState.showTitle"),
                "DualAxis must thread its Title binding into the shared CompactTypographyRow's trailing toggle, not own a duplicate Toggle(\"Title\")")
        #expect(source.contains("dualAxisRangeGroup"),
                "DualAxis builds its own dedicated range row (dualAxisRangeGroup), not a shared generic RangeControlRow")
        #expect(source.contains("label: \"Axis colors\""))
        #expect(!source.contains("WorkbenchStandardPlotControls"))
        #expect(!source.contains("WorkbenchPlotControlsPanel"))
        #expect(!source.contains("SharedPlotTextControls"))
        #expect(!source.contains("SharedPlotFontSizeControls"))
        #expect(!source.contains("PlotControlSection"))
        #expect(!source.contains("HeatmapPlotControlsPanel"))
        #expect(!source.contains("HeatmapColorScaleControls"))
        #expect(!source.contains("HeatmapZLabelControl"))
        #expect(!source.contains("HeatmapZRangeControl"))
    }

    @Test("DualAxisPlotControlsPanel.swift uses compact unified rows")
    func dualAxisUsesCompactUnifiedRows() throws {
        let source = try loadWorkbenchSource("DualAxisPlotControlsPanel.swift")
        #expect(source.contains("label: \"Plot title\""))
        #expect(source.contains("label: \"L-Y\""),
                "DualAxis label-override row uses the abbreviated \"L-Y\" label, not \"Left Y\"")
        #expect(source.contains("label: \"R-Y\""),
                "DualAxis label-override row uses the abbreviated \"R-Y\" label, not \"Right Y\"")
        #expect(source.contains("label: \"Left\""))
        #expect(source.contains("label: \"Right\""))
        #expect(source.contains("label: \"Axis colors\""))
        #expect(source.contains("Divider()"))
        #expect(source.contains("DualAxisControlWeightedRowLayout"))
        #expect(source.contains("menuPickerRow(label: \"Line\""))
        #expect(!source.contains("PlotControlSection(title: \"Labels\")"))
        #expect(!source.contains("PlotControlSection(title: \"Ranges\")"))
        #expect(!source.contains("PlotControlSection(title: \"Series Style\")"))
        #expect(!source.contains("PlotControlSection(title: \"Axis Colors\")"))
        #expect(!source.contains("PlotControlSection(title: \"Left Series\")"))
        #expect(!source.contains("PlotControlSection(title: \"Right Series\")"))
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

    @Test("ThreeOmegaWorkspaceView.swift binds showTitle through standard controls")
    func threeOmegaBindsShowTitle() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        #expect(source.contains("showTitle: Binding("),
                "3ω must pass the active-tab showTitle binding to WorkbenchStandardPlotControls")
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

    @Test("ThreeOmegaWorkspaceView.swift binds globalPlotDefaults through standard controls")
    func threeOmegaBindsGlobalPlotDefaults() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        #expect(source.contains("globalPlotDefaults: $workbench.globalPlotDefaults"),
                "3ω must pass globalPlotDefaults binding to WorkbenchStandardPlotControls")
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

    // INV-3W-13: 3ω-specific controls stay outside the shared standard controls path
    @Test("ThreeOmegaWorkspaceView.swift keeps workflow-specific controls outside WorkbenchStandardPlotControls")
    func threeOmegaKeepsWorkflowSpecificControlsOutsideStandardControls() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        let standardSource = try loadWorkbenchSource("WorkbenchStandardPlotControls.swift")
        #expect(source.contains("ThreeOmegaActionBarTabPicker"))
        #expect(source.contains("ThreeOmegaGeometryPanel"))
        #expect(source.contains("DualAxisPlotControlsPanel"))
        #expect(source.contains("fitRanges"))
        #expect(source.contains("v3Method"))
        #expect(!standardSource.contains("fitRanges"))
        #expect(!standardSource.contains("v3Method"))
        #expect(!standardSource.contains("overlayRuntime"))
    }

    @Test("ThreeOmegaWorkspaceView.swift compacts transport geometry and fit ranges")
    func threeOmegaCompactsTransportGeometryAndFitRanges() throws {
        let source = try loadWorkbenchSource("ThreeOmegaWorkspaceView.swift")
        #expect(source.contains("ThreeOmegaTemperatureDependencePlotControlsPanel"))
        #expect(source.contains("GroupBox"))
        #expect(source.contains("Divider()"))
        #expect(source.contains("leftExtra: { EmptyView() }"))
        #expect(source.contains("ThreeOmegaTransportGeometryFields"))
        #expect(source.contains("ThreeOmegaFitRangeEditor"))
        #expect(source.contains("Lxx"))
        #expect(source.contains("Lxy"))
        #expect(source.contains("d"))
        #expect(source.contains("V(3ω)"))
        #expect(source.contains("Fit"))
        #expect(source.contains("FitRangeBoundField"))
        #expect(source.contains("refreshTransportDerivedPlots(reason: \"geometry changed\")"),
                "geometry and v3Method share a single ThreeOmegaTransportGeometryFields onCommit callback tagged \"geometry changed\" — there is no separate \"v3Method changed\" reason")
        #expect(source.contains("refreshTransportDerivedPlots(reason: \"fit ranges changed\")"))
        #expect(!source.contains("Transport Geometry"))
        #expect(!source.contains("Fit Ranges"))
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

// MARK: - Suite 3b: DualAxis keeps its own grouped controls while reusing text rows

@Suite("V7.8C DualAxis control ownership")
struct V78CDualAxisPlotControlsPathTests {

    @Test("DualAxisPlotControlsPanel.swift uses the compact weighted row layout")
    func dualAxisUsesCompactWeightedRowLayout() throws {
        let source = try loadWorkbenchSource("DualAxisPlotControlsPanel.swift")
        #expect(source.contains("DualAxisControlWeightedRowLayout"))
        #expect(source.contains("LabelOverrideField"))
        #expect(source.contains("dualAxisRangeGroup"),
                "DualAxis builds its own dedicated range row (dualAxisRangeGroup), not a shared generic RangeControlRow")
        #expect(source.contains("menuPickerRow(label: \"Line\""))
        #expect(source.contains("label: \"Axis colors\""))
        #expect(!source.contains("SharedPlotTextFieldRow"))
        #expect(!source.contains("PlotControlSection"))
        #expect(!source.contains("SegmentedControlRow"))
        #expect(!source.contains("SharedPlotTextControls"))
        #expect(!source.contains("SharedPlotFontSizeControls"))
        #expect(!source.contains("HeatmapZLabelControl"))
        #expect(!source.contains("Clear Plot"))
    }
}

// MARK: - Suite 4: IV uses WorkbenchStandardPlotControls

@Suite("V7.8C IV standard plot controls path")
struct V78CIVPlotControlsPathTests {

    @Test("IVWorkspaceView.swift uses WorkbenchStandardPlotControls")
    func ivUsesStandardPlotControls() throws {
        let source = try loadWorkbenchSource("IVWorkspaceView.swift")
        #expect(source.contains("WorkbenchStandardPlotControls"),
                "IV must use WorkbenchStandardPlotControls instead of a reduced custom panel")
    }

    @Test("IVWorkspaceView.swift binds activeTab through standard controls")
    func ivBindsActiveTab() throws {
        let source = try loadWorkbenchSource("IVWorkspaceView.swift")
        #expect(source.contains("activeTab: $store.tabs.activeTab"),
                "IV must pass activeTab binding to WorkbenchStandardPlotControls")
    }

    @Test("IVWorkspaceView.swift binds titleTemplate through standard controls")
    func ivBindsTitleTemplate() throws {
        let source = try loadWorkbenchSource("IVWorkspaceView.swift")
        #expect(source.contains("titleTemplate: $store.titleTemplate"),
                "IV must pass titleTemplate binding to WorkbenchStandardPlotControls")
    }

    @Test("IVWorkspaceView.swift binds showPlotGrid through standard controls")
    func ivBindsShowPlotGrid() throws {
        let source = try loadWorkbenchSource("IVWorkspaceView.swift")
        #expect(source.contains("showGrid"),
                "IV must pass showGrid binding to WorkbenchStandardPlotControls")
    }

    @Test("IVWorkspaceView.swift binds showTitle through standard controls")
    func ivBindsShowTitle() throws {
        let source = try loadWorkbenchSource("IVWorkspaceView.swift")
        #expect(source.contains("showTitle: Binding("),
                "IV must pass the active-tab showTitle binding to WorkbenchStandardPlotControls")
    }

    @Test("IVWorkspaceView.swift binds style controls through standard controls")
    func ivBindsStyleControls() throws {
        let source = try loadWorkbenchSource("IVWorkspaceView.swift")
        #expect(source.contains("seriesRenderMode: $store.tabs.seriesRenderMode"),
                "IV must pass seriesRenderMode binding to WorkbenchStandardPlotControls")
        #expect(source.contains("chartStyleOverrides: $store.tabs.chartStyleOverrides"),
                "IV must pass chartStyleOverrides binding to WorkbenchStandardPlotControls")
    }

    @Test("IVWorkspaceView.swift binds globalPlotDefaults through standard controls")
    func ivBindsGlobalPlotDefaults() throws {
        let source = try loadWorkbenchSource("IVWorkspaceView.swift")
        #expect(source.contains("globalPlotDefaults: $workbench.globalPlotDefaults"),
                "IV must pass globalPlotDefaults binding to WorkbenchStandardPlotControls")
    }

    @Test("IVWorkspaceView.swift binds label override callbacks through standard controls")
    func ivBindsLabelOverrides() throws {
        let source = try loadWorkbenchSource("IVWorkspaceView.swift")
        #expect(source.contains("onTitleOverride"),
                "IV must pass title override callback to WorkbenchStandardPlotControls")
        #expect(source.contains("onXLabelOverride"),
                "IV must pass X label override callback to WorkbenchStandardPlotControls")
        #expect(source.contains("onYLabelOverride"),
                "IV must pass Y label override callback to WorkbenchStandardPlotControls")
        #expect(source.contains("activeSeriesLabelOverrides"),
                "IV must pass the active series label overrides to WorkbenchStandardPlotControls")
        #expect(source.contains("onRenameSeriesLabel"),
                "IV must pass the series rename callback to WorkbenchStandardPlotControls")
    }

    @Test("IVWorkspaceView.swift keeps channel pickers as workflow-specific extra content")
    func ivKeepsChannelPickersWorkflowLocal() throws {
        // IVChannelPicker / IVCurrentBasisPicker were extracted into
        // IVSpecificPlotControls.swift (wrapped in WorkbenchPlotControlsPluginSection,
        // see commit 62722f0), so IVWorkspaceView.swift now references that wrapper
        // instead of declaring the pickers inline.
        let viewSource = try loadWorkbenchSource("IVWorkspaceView.swift")
        #expect(viewSource.contains("IVSpecificPlotControls"),
                "IV-specific plot controls must remain workflow-local extra content, via IVSpecificPlotControls")

        let controlsSource = try loadWorkbenchSource("IVSpecificPlotControls.swift")
        #expect(controlsSource.contains("IVChannelPicker"),
                "IV-specific channel picker controls must remain workflow-local")
        #expect(controlsSource.contains("IVCurrentBasisPicker"),
                "IV-specific current-basis control must remain workflow-local")
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

    @Test("RTWorkspaceView.swift uses WorkbenchStandardPlotControls")
    func rtUsesStandardPlotControls() throws {
        let source = try loadWorkbenchSource("RTWorkspaceView.swift")
        #expect(source.contains("WorkbenchStandardPlotControls"),
                "RT must use WorkbenchStandardPlotControls instead of a reduced custom panel")
    }

    @Test("RTWorkspaceView.swift binds showTitle through standard controls")
    func rtBindsShowTitle() throws {
        let source = try loadWorkbenchSource("RTWorkspaceView.swift")
        #expect(source.contains("showTitle: Binding("),
                "RT must pass the active-tab showTitle binding to WorkbenchStandardPlotControls")
    }
}

// MARK: - Suite 5: RSM uses a dedicated heatmap plot controls surface

@Suite("V7.8C RSM heatmap plot controls path")
struct V78CRSMPlotControlsPathTests {

    @Test("HeatmapPlotControlsPanel.swift defines the heatmap controls surface")
    func heatmapModuleDefinesControlsPanel() throws {
        let source = try loadHeatmapSource("HeatmapPlotControlsPanel.swift")
        #expect(source.contains("struct HeatmapPlotControlsPanel"),
                "Heatmap module must define the heatmap plot controls panel")
        #expect(source.contains("hostControls"),
                "Heatmap plot controls must expose a generic host controls slot")
        #expect(source.contains("SharedPlotTextControls"),
                "Heatmap module must use the shared title/X/Y component")
        #expect(source.contains("Toggle(\"Title\""),
                "Heatmap module must expose the Title checkbox in common controls")
        #expect(source.contains("HeatmapZLabelControl"),
                "Heatmap module must mount the optional Z/colorbar label control")
        #expect(source.contains("SharedPlotFontSizeControls"),
                "Heatmap module must use the shared title/axis/tick font controls")
        #expect(source.contains("HeatmapZRangeControl"),
                "Heatmap module must mount the Z range controls")
        #expect(source.contains("HeatmapColorScaleControls"),
                "Heatmap module must mount the extracted color scale controls")
        #expect(source.contains("HeatmapInterpolationControls"),
                "Heatmap module must mount the interpolation controls")
        #expect(!source.contains("private struct HeatmapColorScaleControls"),
                "Heatmap module must not define the color scale controls inline")
        #expect(!source.contains("RSMViewSelector"),
                "Heatmap plot controls must not reference RSM-specific view selection")
        #expect(!source.contains("SharedPlotTextFieldRow"),
                "Heatmap panel should keep using the higher-level shared text controls, not the raw text-row primitive")
        #expect(source.contains(".frame(maxWidth: .infinity)"),
                "Heatmap plot controls must apply .frame(maxWidth: .infinity) so the box fills the row")
    }

    @Test("HeatmapPlotControlsPanel.swift stays Heatmap-only")
    func heatmapControlsStayHeatmapOnly() throws {
        let source = try loadHeatmapSource("HeatmapPlotControlsPanel.swift")
        #expect(source.contains("SharedPlotTextControls"))
        #expect(source.contains("SharedPlotFontSizeControls"))
        #expect(source.contains("SharedPlotTickCountControls"))
        #expect(source.contains("HeatmapColorScaleControls"))
        #expect(source.contains("HeatmapInterpolationControls"))
        #expect(source.contains("HeatmapZLabelControl"))
        #expect(source.contains("HeatmapZRangeControl"))
        #expect(!source.contains("WorkbenchStandardPlotControls"))
        #expect(!source.contains("WorkbenchPlotControlsPanel"))
        #expect(!source.contains("DualAxisPlotControlsPanel"))
        #expect(!source.contains("DualAxisDisplayState"))
        #expect(!source.contains("DualAxisRenderPipeline"))
    }

    @Test("RSMWorkspaceView.swift mounts HeatmapPlotControlsPanel")
    func rsmDefinesHeatmapPanel() throws {
        let source = try loadWorkbenchSource("RSMWorkspaceView.swift")
        #expect(source.contains("HeatmapPlotControlsPanel"),
                "RSM must mount the heatmap plot controls panel from the heatmap module")
        #expect(source.contains("RSMViewSelector"),
                "RSM must mount the RSM-specific view selector")
        #expect(source.contains("hostControls: RSMViewSelector"),
                "RSM must pass the RSM view selector into the heatmap panel host slot")
        #expect(source.contains("showTitle: bindableStore.heatmapDisplayState.showTitle"),
                "RSM must bind Heatmap title visibility from the per-tab heatmap display state")
        #expect(source.contains("onShowTitleChange:"),
                "RSM must rerender when Heatmap title visibility changes")
    }

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

    @Test("XY workspaces do not show HeatmapZRangeControl")
    func xyWorkspacesDoNotShowHeatmapZRangeControl() throws {
        let source = try loadWorkbenchSource("WorkbenchPlotControlsPanel.swift")
        #expect(!source.contains("HeatmapZRangeControl"),
                "XY plot controls must not expose the heatmap Z range control")
    }

    @Test("RSMWorkspaceView.swift composes shared and optional plot controls")
    func rsmExposesHeatmapControls() throws {
        let source = try loadWorkbenchSource("RSMWorkspaceView.swift")
        #expect(source.contains("HeatmapPlotControlsPanel"),
                "RSM must mount the heatmap plot controls panel from the heatmap module")
        #expect(!source.contains("ForEach(RSMView.allCases"),
                "RSM must not inline the HL/KL/HK picker")
        #expect(!source.contains("Picker(\"\", selection: $bindableStore.activeView)"),
                "RSM must not inline the active-view picker")
    }

    // INV-RSM-PL-1: GroupBox fills available width
    @Test("RSMWorkspaceView.swift Plot Controls GroupBox fills available width")
    func rsmGroupBoxFillsWidth() throws {
        let source = try loadHeatmapSource("HeatmapPlotControlsPanel.swift")
        #expect(source.contains(".frame(maxWidth: .infinity)"),
                "Heatmap plot controls must apply .frame(maxWidth: .infinity) so the box fills the row")
    }

    // INV-RSM-PL-2: Shared text layout owns 3:1:1 proportions
    @Test("SharedPlotTextControls.swift uses weighted 3:1:1 Title/X/Y proportions")
    func rsmProportionalTitleLayout() throws {
        let source = try loadWorkbenchSource("SharedPlotTextControls.swift")
        #expect(source.contains("plotControlWeight(3)"),
                "Title must receive the larger weight in the shared text row")
        #expect(source.contains("plotControlWeight(1)"),
                "X/Y must each receive the same unit weight in the shared text row")
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

    @Test("HeatmapZLabelControl.swift is a heatmap module component")
    func heatmapZLabelControlIsModuleOwned() throws {
        let source = try loadHeatmapSource("HeatmapZLabelControl.swift")
        #expect(source.contains("struct HeatmapZLabelControl"))
        #expect(source.contains("Toggle(\"Z\""))
        #expect(source.contains("label: \"\""))
        #expect(source.contains("sourceResetToken"))
        #expect(!source.contains("RSM"))
    }

    @Test("HeatmapZLabelControl and HeatmapZRangeControl remain separate components")
    func heatmapZLabelAndRangeControlsRemainSeparate() throws {
        let zLabelSource = try loadHeatmapSource("HeatmapZLabelControl.swift")
        let zRangeSource = try loadHeatmapSource("HeatmapZRangeControl.swift")
        #expect(!zLabelSource.contains("HeatmapZRangeControl"))
        #expect(!zRangeSource.contains("HeatmapZLabelControl"))
        #expect(zRangeSource.contains("HeatmapZDomainState"))
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

    @Test("HeatmapColorScaleControls.swift is a heatmap module component")
    func heatmapColorScaleControlsIsModuleOwned() throws {
        let source = try loadHeatmapSource("HeatmapColorScaleControls.swift")
        #expect(source.contains("struct HeatmapColorScaleControls"))
        #expect(source.contains("Colorbar"),
                "Visible label must be 'Colorbar' after spacing polish")
        #expect(!source.contains("\"Color Scale\""),
                "'Color Scale' must no longer appear as the visible first-row label")
        #expect(source.contains("PlotScaleTransform.linear"))
        #expect(source.contains("PlotScaleTransform.log10"))
        #expect(!source.contains("RSM"))
    }

    @Test("HeatmapInterpolationControls.swift is a heatmap module component")
    func heatmapInterpolationControlsIsModuleOwned() throws {
        let source = try loadHeatmapSource("HeatmapInterpolationControls.swift")
        #expect(source.contains("struct HeatmapInterpolationControls"))
        #expect(source.contains("\"Interpolation\""))
        #expect(source.contains("Text(\"Nearest\")"))
        #expect(source.contains("Log-Space Gaussian"))
        #expect(source.contains("HeatmapInterpolationMode.nearest"))
        #expect(source.contains("HeatmapInterpolationMode.logSpaceGaussian1p5x"))
        // Plain bilinear, plain gaussian-light, and the retired raw-intensity-space
        // Gaussian Upsample 2x must no longer be surfaced as picker options.
        #expect(!source.contains("Bilinear 2x"))
        #expect(!source.contains("Gaussian Light"))
        #expect(!source.contains("Gaussian Upsample"))
        #expect(!source.contains("HeatmapInterpolationMode.gaussianUpsample2x"))
        #expect(!source.contains("4x"))
        #expect(!source.contains("RSM"))
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

    // INV-RSM-PL-5c: hostControls and Colorbar share row 1 (kept short); Ticks and
    // Interpolation share row 2, so the long "Gaussian Upsample 2x" segment no longer
    // stretches the first row's height.
    @Test("HeatmapPlotControlsPanel splits hostControls/Colorbar (row 1) from Ticks/Interpolation (row 2)")
    func heatmapControlsPanelSplitsIntoResponsiveRows() throws {
        let source = try loadHeatmapSource("HeatmapPlotControlsPanel.swift")
        #expect(source.contains("HeatmapInterpolationControls("),
                "HeatmapInterpolationControls must still be mounted")

        // Row 1: hostControls and HeatmapColorScaleControls must be siblings inside the
        // first HStack.
        let hstackRange = source.range(of: "HStack(spacing:")
        #expect(hstackRange != nil,
                "HeatmapPlotControlsPanel must use HStack for its control rows")
        guard let firstHStackStart = hstackRange?.lowerBound else { return }
        let afterFirstHStack = String(source[firstHStackStart...])
        // Everything up to the first row's closing brace (approximated by the next
        // occurrence of a second "HStack(spacing:") marks the end of row 1's content.
        let row1End = afterFirstHStack.range(
            of: "HStack(spacing:",
            range: afterFirstHStack.index(afterFirstHStack.startIndex, offsetBy: "HStack(spacing:".count)..<afterFirstHStack.endIndex
        )
        let row1Content = row1End.map { String(afterFirstHStack[..<$0.lowerBound]) } ?? afterFirstHStack

        #expect(row1Content.contains("hostControls"),
                "hostControls must be in row 1")
        #expect(row1Content.contains("HeatmapColorScaleControls("),
                "HeatmapColorScaleControls must be in row 1")

        // Interpolation and Ticks must NOT be crammed into row 1 — that's exactly the
        // overflow this split fixes.
        #expect(!row1Content.contains("HeatmapInterpolationControls("),
                "HeatmapInterpolationControls must be moved out of row 1 to prevent overflow")
        #expect(!row1Content.contains("SharedPlotTickCountControls"),
                "Tick controls must be moved out of row 1 to prevent overflow")

        // No Spacer(minLength:) forcing the row to claim extra width — each row should
        // size to its own content instead.
        #expect(!source.contains("Spacer(minLength:"),
                "HeatmapPlotControlsPanel must not force width via Spacer(minLength:)")

        // Row 2 must contain both the tick controls and interpolation controls, with
        // Ticks appearing first.
        #expect(source.contains("SharedPlotTickCountControls"),
                "Tick controls must still be mounted, just on a separate row")
        guard
            let ticksRange = source.range(of: "SharedPlotTickCountControls"),
            let interpolationRange = source.range(of: "HeatmapInterpolationControls(")
        else {
            Issue.record("Expected both SharedPlotTickCountControls and HeatmapInterpolationControls to be present")
            return
        }
        #expect(ticksRange.lowerBound < interpolationRange.lowerBound,
                "Ticks must appear before Interpolation within row 2")
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
