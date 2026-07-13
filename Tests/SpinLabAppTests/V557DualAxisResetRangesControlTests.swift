import Foundation
import Testing
@testable import SpinLabApp

/// v5.5.7 — Dual Axis controls (`DualAxisPlotControlsPanel`) gained a
/// `showsResetRangesControl` flag (default `true`, preserving prior behavior) gating
/// the standalone "Reset ranges" button. 3ω's Dual Axis (Temperature Dependence) call
/// site is the only caller opting out (`false`), hiding that aggregate button without
/// touching the underlying per-field reset (the `xmark.circle` clear buttons on each
/// range field, which remain unconditional). Source-inspection checks only.
@Suite("V5.5.7 Dual Axis Reset ranges control cleanup")
struct V557DualAxisResetRangesControlTests {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SpinLabAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private func loadSource(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("DualAxisPlotControlsPanel gates the standalone Reset ranges button behind showsResetRangesControl")
    func dualAxisPanelHasResetRangesControlFlag() throws {
        let src = try loadSource(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/DualAxis/DualAxisPlotControlsPanel.swift"
        )
        #expect(src.contains("var showsResetRangesControl: Bool = true"),
                "flag must default to the panel's original (shown) behavior")
        #expect(src.contains(#"if showsResetRangesControl, displayState.axisRangeOverride != nil {"#),
                "Reset ranges button must be gated by showsResetRangesControl without removing the underlying reset")
        #expect(src.contains(#"Button("Reset ranges")"#),
                "the gated control must remain an actual interactive button, not merely a label")
        // Per-field reset (xmark.circle clear button) must remain untouched by this flag.
        #expect(src.contains("xmark.circle.fill"),
                "individual axis-field reset buttons must remain — only the aggregate Reset ranges button is toggled")
        #expect(!src.contains("showsResetRangesHint"),
                "the old flag name must be fully renamed to showsResetRangesControl")
    }

    @Test("Only 3ω's Dual Axis (Temperature Dependence) call site opts out of the Reset ranges control")
    func onlyThreeOmegaDualAxisCallSiteHidesResetControl() throws {
        let threeOmegaSrc = try loadSource("Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift")
        #expect(threeOmegaSrc.contains("showsResetRangesControl: false"),
                "3ω's DualAxisPlotControlsPanel call site must pass showsResetRangesControl: false")

        // DualAxisPlotControlsPanel has exactly one call site in the app (3ω's Temperature
        // Dependence), so this also proves no other caller was silently affected.
        let allSwiftFiles = try FileManager.default
            .subpathsOfDirectory(atPath: repoRoot().appendingPathComponent("Sources/SpinLabApp").path)
            .filter { $0.hasSuffix(".swift") }
        var callSiteFiles: [String] = []
        for relativePath in allSwiftFiles {
            let src = try loadSource("Sources/SpinLabApp/\(relativePath)")
            if src.contains("DualAxisPlotControlsPanel(") {
                callSiteFiles.append(relativePath)
            }
        }
        #expect(callSiteFiles == ["Features/Workbench/ThreeOmegaWorkspaceView.swift"],
                "DualAxisPlotControlsPanel must have exactly one call site; found: \(callSiteFiles)")
    }
}
