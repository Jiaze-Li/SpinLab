import Foundation
import Testing
@testable import SpinLabApp

/// Phase 1B (AFM common architecture gate) — generic Heatmap workflow plugin-controls slot.
///
/// `HeatmapPlotControlsPanel` gained a second generic slot, `pluginControls`, so a workflow
/// (RSM today, AFM once registered) can mount workflow-specific controls below the common
/// Heatmap controls without Heatmap knowing workflow semantics. These are source-level guards
/// consistent with the rest of this suite's plot-controls specialization tests (this repo has
/// no SwiftUI view-inspection harness).
@Suite("Heatmap plugin-controls slot (Phase 1B)")
struct HeatmapPluginControlsSlotTests {

    private func loadSource(relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root.appending(path: relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static let heatmapControlsPath =
        "Sources/SpinLabApp/Workbench/V3/Heatmap/HeatmapPlotControlsPanel.swift"

    @Test("HeatmapPlotControlsPanel declares a generic pluginControls slot")
    func declaresPluginControlsSlot() throws {
        let source = try loadSource(relativePath: Self.heatmapControlsPath)
        #expect(source.contains("struct HeatmapPlotControlsPanel<HostControls: View, PluginControls: View>: View"))
        #expect(source.contains("@ViewBuilder var pluginControls: () -> PluginControls"))
    }

    @Test("HeatmapPlotControlsPanel renders pluginControls after common controls")
    func rendersPluginControlsAfterCommonControls() throws {
        let source = try loadSource(relativePath: Self.heatmapControlsPath)
        guard let zRangeRange = source.range(of: "HeatmapZRangeControl("),
              let pluginCallRange = source.range(of: "pluginControls()") else {
            Issue.record("Expected both HeatmapZRangeControl( and pluginControls() to appear in the panel body")
            return
        }
        #expect(pluginCallRange.lowerBound > zRangeRange.lowerBound,
                "pluginControls() must render after the common controls, not interleaved with them")
    }

    @Test("HeatmapPlotControlsPanel defaults pluginControls to EmptyView for existing callers")
    func defaultsToEmptyView() throws {
        let source = try loadSource(relativePath: Self.heatmapControlsPath)
        #expect(source.contains("extension HeatmapPlotControlsPanel where PluginControls == EmptyView"),
                "existing callers (RSM) that omit pluginControls must not be forced to change")
        #expect(source.contains("pluginControls: { EmptyView() }"))
    }

    @Test("RSMWorkspaceView does not pass pluginControls (RSM has no AFM-style plugin controls)")
    func rsmDoesNotUsePluginSlot() throws {
        let source = try loadSource(relativePath: "Sources/SpinLabApp/Features/Workbench/RSMWorkspaceView.swift")
        #expect(!source.contains("pluginControls:"),
                "RSM must keep rendering through the EmptyView default, unchanged by this gate")
    }

    @Test("WorkbenchPlotControlsPluginSection is the documented composition primitive for plugin content")
    func pluginSectionDocumentedAsCompositionPrimitive() throws {
        let source = try loadSource(
            relativePath: "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/WorkbenchPlotControlsPluginSection.swift"
        )
        #expect(source.contains("struct WorkbenchPlotControlsPluginSection<Content: View>: View"))
    }
}
