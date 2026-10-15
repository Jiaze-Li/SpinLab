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

}
