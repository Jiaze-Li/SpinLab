import Foundation
import SwiftUI
import Testing
@testable import SpinLabApp

/// v5.5.7 — Standard XY's Title checkbox moves from the Draw row into the trailing
/// end of the shared Font row (`CompactTypographyRow`), consuming the same
/// `showTitle` capability Dual Axis already threads into that row. Source-inspection
/// checks only — layout/behavior is otherwise unchanged (Grid stays on the Draw row,
/// `showTitle` remains caller-owned state, `.equatable()`/onChange semantics preserved).
@Suite("V5.5.7 Standard XY shared Typography + Title integration")
struct V557StandardXYSharedTypographyTitleTests {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SpinLabAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private func loadSource(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("WorkbenchStandardPlotControls no longer declares its own Title toggle; Grid stays on the Draw row")
    func standardControlsHasNoLocalTitleToggle() throws {
        let src = try loadSource(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchStandardPlotControls.swift"
        )
        #expect(!src.contains(#"Toggle("Title""#),
                "Title toggle must be removed from WorkbenchStandardPlotControls — it now lives in CompactTypographyRow")
        #expect(src.contains(#"Toggle("Grid""#),
                "Grid toggle must remain on the Draw row, untouched by the Title relocation")
    }

    @Test("WorkbenchPlotControlsPanel threads Standard XY's showTitle into CompactTypographyRow")
    func panelThreadsShowTitleIntoTypographyRow() throws {
        let src = try loadSource(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchPlotControlsPanel.swift"
        )
        #expect(src.contains("var showTitle: Binding<Bool>?"))
        #expect(src.contains("showTitle: showTitle"),
                "showTitle must be forwarded to CompactTypographyRow's initializer unchanged")
        #expect(src.contains(".equatable()"),
                "CompactTypographyRow call must retain its .equatable() wrapper")
    }

    @Test("Every WorkbenchStandardPlotControls caller still passes showTitle through unchanged")
    func standardControlsCallersStillWireShowTitle() throws {
        for (file, path) in [
            ("IVWorkspaceView.swift", "Sources/SpinLabApp/Features/Workbench/IVWorkspaceView.swift"),
            ("RTWorkspaceView.swift", "Sources/SpinLabApp/Features/Workbench/RTWorkspaceView.swift"),
            ("ThreeOmegaWorkspaceView.swift", "Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift"),
            ("XYRotationWorkspaceView.swift", "Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift"),
        ] {
            let src = try loadSource(path)
            #expect(src.contains("showTitle:"), "\(file) must still pass showTitle to WorkbenchStandardPlotControls")
        }
    }

    @Test("Standard XY and Dual Axis both drive their Title toggle through the same shared CompactTypographyRow capability")
    func standardXYAndDualAxisShareTypographyRowTitleCapability() throws {
        let panelSrc = try loadSource(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchPlotControlsPanel.swift"
        )
        let dualAxisSrc = try loadSource(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/DualAxis/DualAxisPlotControlsPanel.swift"
        )
        #expect(panelSrc.contains("CompactTypographyRow(") && panelSrc.contains("showTitle: showTitle"),
                "Standard XY (via WorkbenchPlotControlsPanel) must call CompactTypographyRow with its showTitle binding")
        #expect(dualAxisSrc.contains("CompactTypographyRow(") && dualAxisSrc.contains("showTitle: $displayState.showTitle"),
                "Dual Axis must call CompactTypographyRow with its showTitle binding")
        #expect(!dualAxisSrc.contains(#"Toggle("Title""#),
                "Dual Axis must not retain a standalone Title toggle — regression guard for the prior consolidation")
    }
}
