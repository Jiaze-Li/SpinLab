import Foundation
import Testing
@testable import SpinLabApp

/// Gate 7.8E — Plot System structural boundary guards.
///
/// These tests protect ownership and dependency direction for the Plot System
/// module group as documented in MODULE_BOUNDARIES.md and PLOT_SYSTEM.md.
/// They do not enumerate interaction combinations; they lock the architecture
/// so Plot System features cannot collapse into one mixed owner again.
///
/// Invariants tested:
///   1. Main Board shell passes plotControls as a slot and does not own
///      TabRenderState / TabRenderManager internals.
///   2. WorkbenchPlotCanvas is an interaction dispatcher, not a state owner.
///   3. WorkbenchPlottingStore does not contain currentRunTrace;
///      WorkbenchRunTraceProviding is separate;
///      WorkbenchWorkspaceProviding composes the interaction surface only;
///      Cartesian XY shared state lives in WorkbenchCartesianXYPlottingStore.
///   4. TabRenderState owns the per-tab override fields;
///      TabRenderManager owns the shared display and preservation state;
///      Cartesian XY workflow stores own the shared plot defaults.
///   5. Render pipeline stays one-way: no workflow store state in pipeline files.
///   6. WorkbenchStandardPlotControls is free of workflow-specific semantics.
///   7. Copy PNG context menu block does not call mutation callbacks.
@Suite("V7.8E Plot System Structural Boundary")
struct V78EPlotSystemStructuralBoundaryTests {

    // MARK: - Source-inspection helpers

    private static func source(at relativePath: String) throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SpinLabAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let url = base.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - 1. Main Board shell does not own TabRenderState / TabRenderManager internals

    @Test("WorkflowWorkspaceShell passes plotControls as a slot and does not directly manipulate TabRenderState")
    func shellPassesPlotControlsAsSlot() throws {
        let src = try Self.source(at: "Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift")
        // Shell must accept plotControls as a ViewBuilder slot
        #expect(src.contains("plotControls"), "Shell must declare a plotControls slot")
        // Shell must not store or construct TabRenderState or TabRenderManager instances
        #expect(!src.contains("TabRenderState"), "Shell must not reference TabRenderState directly")
        #expect(!src.contains("TabRenderManager"), "Shell must not reference TabRenderManager directly")
    }

    @Test("WorkflowWorkspaceShell does not construct workflow-specific plot controls")
    func shellDoesNotConstructWorkflowSpecificPlotControls() throws {
        let src = try Self.source(at: "Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift")
        // Shell must not reference workflow-specific plot controls types
        #expect(!src.contains("AHEPlotControlsPanel"), "Shell must not reference AHEPlotControlsPanel")
        #expect(!src.contains("WorkbenchStandardPlotControls"), "Shell must not construct WorkbenchStandardPlotControls itself")
    }

    // MARK: - 2. WorkbenchPlotCanvas is an interaction dispatcher, not a state owner

    @Test("WorkbenchPlotCanvas does not store canonical plot preservation state")
    func canvasDoesNotStorePreservationState() throws {
        let src = try Self.source(at: "Sources/SpinLabApp/Features/Workbench/WorkbenchPlotCanvas.swift")
        // Canvas must not hold TabRenderState or TabRenderManager as stored properties
        // (var/let stored property patterns — "@State" or "var x: TabRenderState" etc.)
        #expect(!src.contains("TabRenderState("), "Canvas must not construct TabRenderState instances")
        #expect(!src.contains("TabRenderManager("), "Canvas must not construct TabRenderManager instances")
        // Canvas must not hold workflow store references
        #expect(!src.contains("AHEWorkspaceStore"), "Canvas must not reference AHEWorkspaceStore")
        #expect(!src.contains("XYRotationWorkspaceStore"), "Canvas must not reference XYRotationWorkspaceStore")
        #expect(!src.contains("ThreeOmegaWorkspaceStore"), "Canvas must not reference ThreeOmegaWorkspaceStore")
    }

    @Test("WorkbenchPlotCanvas exposes interaction callbacks, not stored overrides")
    func canvasExposesCallbacks() throws {
        let src = try Self.source(at: "Sources/SpinLabApp/Features/Workbench/WorkbenchPlotCanvas.swift")
        // Canvas must expose the canonical interaction callbacks
        #expect(src.contains("onLegendDrag"), "Canvas must expose onLegendDrag callback")
        #expect(src.contains("onTogglePointLabelVisibility"), "Canvas must expose onTogglePointLabelVisibility callback")
        #expect(src.contains("onCopyPNG"), "Canvas must expose onCopyPNG callback")
    }

    // MARK: - 3. Plot protocol surface is clean

    @Test("WorkbenchPlottingStore does not contain currentRunTrace")
    func plottingStoreHasNoRunTrace() throws {
        let src = try Self.source(at: "Sources/SpinLabApp/Features/Workbench/WorkbenchPlottingStore.swift")
        // Verify the protocol body does not declare currentRunTrace
        // Find the protocol block for WorkbenchPlottingStore and check it has no currentRunTrace
        let lines = src.components(separatedBy: "\n")
        var inPlottingStore = false
        var braceDepth = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("protocol WorkbenchPlottingStore") {
                inPlottingStore = true
            }
            if inPlottingStore {
                braceDepth += line.filter { $0 == "{" }.count
                braceDepth -= line.filter { $0 == "}" }.count
                if trimmed.contains("currentRunTrace") {
                    Issue.record("WorkbenchPlottingStore must not contain currentRunTrace (Gate 7.8D resolved this)")
                }
                if braceDepth <= 0 && inPlottingStore && trimmed.contains("}") {
                    break
                }
            }
        }
        #expect(inPlottingStore, "protocol WorkbenchPlottingStore was not found — scan never ran")
    }

    @Test("WorkbenchRunTraceProviding is a distinct protocol separate from WorkbenchPlottingStore")
    func runTraceProvidingIsSeparate() throws {
        let src = try Self.source(at: "Sources/SpinLabApp/Features/Workbench/WorkbenchPlottingStore.swift")
        #expect(src.contains("protocol WorkbenchRunTraceProviding"), "WorkbenchRunTraceProviding must be declared")
        #expect(src.contains("protocol WorkbenchPlottingStore"), "WorkbenchPlottingStore must be declared")
        // They must be separate protocol declarations (not one conforming to the other here)
        let rtRange = src.range(of: "protocol WorkbenchRunTraceProviding")!
        let psRange = src.range(of: "protocol WorkbenchPlottingStore")!
        #expect(rtRange != psRange, "They must be distinct declarations")
    }

    @Test("WorkbenchWorkspaceProviding composes WorkbenchPlottingStore and WorkbenchRunTraceProviding")
    func workspaceProvidingComposesBoth() throws {
        let src = try Self.source(at: "Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift")
        // The protocol declaration line must include both
        guard let declLine = src.components(separatedBy: "\n").first(where: { $0.contains("protocol WorkbenchWorkspaceProviding") }) else {
            Issue.record("WorkbenchWorkspaceProviding declaration not found")
            return
        }
        #expect(declLine.contains("WorkbenchPlottingStore"), "WorkbenchWorkspaceProviding must inherit WorkbenchPlottingStore")
        #expect(declLine.contains("WorkbenchRunTraceProviding"), "WorkbenchWorkspaceProviding must inherit WorkbenchRunTraceProviding")
    }

    @Test("WorkbenchCartesianXYPlottingStore owns the Cartesian XY-only shared state")
    func cartesianXYPlottingStoreOwnsSharedState() throws {
        let src = try Self.source(at: "Sources/SpinLabApp/Features/Workbench/WorkbenchPlottingStore.swift")
        guard let declLine = src.components(separatedBy: "\n").first(where: { $0.contains("protocol WorkbenchCartesianXYPlottingStore") }) else {
            Issue.record("WorkbenchCartesianXYPlottingStore declaration not found")
            return
        }
        #expect(declLine.contains("WorkbenchPlottingStore"), "Cartesian XY protocol must compose WorkbenchPlottingStore")
        #expect(declLine.contains("WorkbenchGlobalPlotDefaultsProviding"), "Cartesian XY protocol must compose WorkbenchGlobalPlotDefaultsProviding")
        #expect(src.contains("var showPlotGrid"), "Cartesian XY protocol must own showPlotGrid")
        #expect(src.contains("var seriesRenderMode"), "Cartesian XY protocol must own seriesRenderMode")
        #expect(src.contains("var chartStyleOverrides"), "Cartesian XY protocol must own chartStyleOverrides")
        #expect(src.contains("var globalPlotDefaults"), "WorkbenchGlobalPlotDefaultsProviding must own globalPlotDefaults")
    }

    // MARK: - 4. TabRenderState and TabRenderManager own canonical preservation state

    @Test("TabRenderState contains the per-tab override fields")
    func tabRenderStateOwnsPerTabFields() throws {
        let src = try Self.source(at: "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Preservation/TabRenderManager.swift")
        // Must have all documented per-tab fields
        #expect(src.contains("var legendPoint"), "TabRenderState must own legendPoint")
        #expect(src.contains("var titleOverride"), "TabRenderState must own titleOverride")
        #expect(src.contains("var xLabelOverride"), "TabRenderState must own xLabelOverride")
        #expect(src.contains("var yLabelOverride"), "TabRenderState must own yLabelOverride")
        #expect(src.contains("var seriesLabelOverrides"), "TabRenderState must own seriesLabelOverrides")
        #expect(src.contains("var hiddenPointLabelIndicesBySeries"), "TabRenderState must own hiddenPointLabelIndicesBySeries")
        #expect(src.contains("var seriesOrder"), "TabRenderState must own seriesOrder")
    }

    @Test("TabRenderManager contains the shared display and preservation state fields")
    func tabRenderManagerOwnsSharedState() throws {
        let src = try Self.source(at: "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Preservation/TabRenderManager.swift")
        #expect(src.contains("var activeTab"), "TabRenderManager must own activeTab")
        #expect(src.contains("var showPlotGrid"), "TabRenderManager must own showPlotGrid")
        #expect(src.contains("var seriesRenderMode"), "TabRenderManager must own seriesRenderMode")
        #expect(src.contains("var chartStyleOverrides"), "TabRenderManager must own chartStyleOverrides")
        #expect(src.contains("var legendAnchor"), "TabRenderManager must own legendAnchor")
        #expect(src.contains("var tabStates"), "TabRenderManager must own tabStates")
        #expect(src.contains("var tabOutputs"), "TabRenderManager must own tabOutputs")
    }

    @Test("WorkbenchPlottingStore remains interaction-only")
    func plottingStoreIsInteractionOnly() throws {
        let src = try Self.source(at: "Sources/SpinLabApp/Features/Workbench/WorkbenchPlottingStore.swift")
        let lines = src.components(separatedBy: "\n")
        var inPlottingStore = false
        var braceDepth = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("protocol WorkbenchPlottingStore") {
                inPlottingStore = true
            }
            if inPlottingStore {
                braceDepth += line.filter { $0 == "{" }.count
                braceDepth -= line.filter { $0 == "}" }.count
                #expect(!trimmed.contains("globalPlotDefaults"), "WorkbenchPlottingStore must not expose globalPlotDefaults")
                #expect(!trimmed.contains("showPlotGrid"), "WorkbenchPlottingStore must not expose showPlotGrid")
                #expect(!trimmed.contains("seriesRenderMode"), "WorkbenchPlottingStore must not expose seriesRenderMode")
                #expect(!trimmed.contains("chartStyleOverrides"), "WorkbenchPlottingStore must not expose chartStyleOverrides")
                if braceDepth <= 0 && trimmed.contains("}") {
                    break
                }
            }
        }
    }

    @Test("WorkbenchPlotCanvas does not redeclare canonical TabRenderState fields as stored properties")
    func canvasDoesNotRedeclarePreservationFields() throws {
        let src = try Self.source(at: "Sources/SpinLabApp/Features/Workbench/WorkbenchPlotCanvas.swift")
        // These are canonical TabRenderState fields — canvas must not declare them
        let forbidden = ["titleOverride", "legendPoint", "seriesOrder", "xLabelOverride", "yLabelOverride"]
        for field in forbidden {
            // Accept presence inside a comment; reject as a @State / var declaration
            let statePattern = "@State.*\(field)|var \(field)"
            let found = src.range(of: statePattern, options: .regularExpression) != nil
            #expect(!found, "Canvas must not declare \(field) as a stored property")
        }
    }

    // MARK: - 5. Render pipeline stays one-way

    @Test("WorkbenchRenderPipeline does not reference workflow store state")
    func renderPipelineIsOneWay() throws {
        let src = try Self.source(at: "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Pipeline/WorkbenchRenderPipeline.swift")
        #expect(!src.contains("cachedSearchResults"), "Render pipeline must not reference cachedSearchResults")
        #expect(!src.contains("selectedSearchResultIDs"), "Render pipeline must not reference selectedSearchResultIDs")
        #expect(!src.contains("ingestionResult"), "Render pipeline must not reference ingestionResult")
        #expect(!src.contains("currentRunTrace"), "Render pipeline must not reference currentRunTrace")
        #expect(!src.contains("AHEWorkspaceStore"), "Render pipeline must not import AHEWorkspaceStore")
        #expect(!src.contains("XYRotationWorkspaceStore"), "Render pipeline must not import XYRotationWorkspaceStore")
        #expect(!src.contains("ThreeOmegaWorkspaceStore"), "Render pipeline must not import ThreeOmegaWorkspaceStore")
    }

    @Test("WorkbenchChartRenderer does not reference workflow store state")
    func chartRendererIsOneWay() throws {
        let src = try Self.source(at: "Sources/SpinLabApp/Workbench/V3/WorkbenchChartRenderer.swift")
        #expect(!src.contains("cachedSearchResults"), "Renderer must not reference cachedSearchResults")
        #expect(!src.contains("ingestionResult"), "Renderer must not reference ingestionResult")
        #expect(!src.contains("currentRunTrace"), "Renderer must not reference currentRunTrace")
        #expect(!src.contains("AHEWorkspaceStore"), "Renderer must not import AHEWorkspaceStore")
        #expect(!src.contains("XYRotationWorkspaceStore"), "Renderer must not import XYRotationWorkspaceStore")
        #expect(!src.contains("ThreeOmegaWorkspaceStore"), "Renderer must not import ThreeOmegaWorkspaceStore")
    }

    // MARK: - 6. WorkbenchStandardPlotControls is free of workflow-specific semantics

    @Test("WorkbenchStandardPlotControls does not contain workflow-specific field names")
    func standardPlotControlsIsWorkflowAgnostic() throws {
        let src = try Self.source(at: "Sources/SpinLabApp/Features/Workbench/WorkbenchStandardPlotControls.swift")
        // These are Assembly-owned fields that must not appear in common controls
        let workflowSpecific = [
            "centerBaseline",
            "linearDetrend",
            "phiOffsetOverrides",
            "fitRanges",
            "v3Method",
            "rahe",
            "geometry",
            "AHEWorkspaceStore",
            "XYRotationWorkspaceStore",
            "ThreeOmegaWorkspaceStore"
        ]
        for name in workflowSpecific {
            #expect(!src.contains(name), "WorkbenchStandardPlotControls must not reference \(name)")
        }
    }

    // MARK: - 7. Copy PNG context menu block does not call mutation callbacks

    @Test("WorkbenchPlotCanvas Copy PNG block does not call title/legend/style mutation callbacks")
    func copyPNGBlockDoesNotCallMutationCallbacks() throws {
        let src = try Self.source(at: "Sources/SpinLabApp/Features/Workbench/WorkbenchPlotCanvas.swift")
        // Locate the Copy PNG context menu block (starting at .contextMenu or Menu("Copy PNG"))
        // and verify that no mutation callbacks are called inside it.
        // Starting from onCopyPNG stored-property declaration would scan too much of the file;
        // anchoring to the view-body context menu block is precise.
        let lines = src.components(separatedBy: "\n")
        var inCopyPNGBlock = false
        var copyBraceDepth = 0
        let mutationCallbacks = [
            "onEditTitle", "onEditXLabel", "onEditYLabel", "onEditLegendLabel",
            "onFontSizeChange", "onStyleOverrideChange", "onLegendDrag",
            "onTogglePointLabelVisibility"
        ]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Enter the block at the .contextMenu opening or the Menu("Copy PNG") line.
            if !inCopyPNGBlock && (trimmed.hasPrefix(".contextMenu") || trimmed.hasPrefix("Menu(\"Copy PNG\")")) {
                inCopyPNGBlock = true
                copyBraceDepth = 0
            }
            if inCopyPNGBlock {
                copyBraceDepth += line.filter { $0 == "{" }.count
                copyBraceDepth -= line.filter { $0 == "}" }.count
                // Detect call sites (not stored-property declarations).
                for callback in mutationCallbacks {
                    if trimmed.contains("\(callback)(") || trimmed.contains("\(callback)?(") {
                        Issue.record("Copy PNG context menu block must not call \(callback) — found: \(trimmed)")
                    }
                }
                // Exit when brace depth returns to zero (block closed).
                if copyBraceDepth <= 0 {
                    inCopyPNGBlock = false
                }
            }
        }
        // Test passes if no Issue was recorded above
    }
}
