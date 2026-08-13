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
        // v5.3.8: IV/RT/XY consolidated their ~25-argument WorkbenchStandardPlotControls
        // calls into the shared store-driven initializer (store:), which derives showTitle
        // from store.tabs.activeState.showTitle once — see
        // WorkbenchStandardPlotControls+StoreDriven.swift. 3ω keeps its own bespoke call
        // site and still passes showTitle: directly.
        let storeDrivenSrc = try loadSource(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchStandardPlotControls+StoreDriven.swift"
        )
        #expect(storeDrivenSrc.contains("showTitle: Binding("),
                "the shared store-driven initializer must still wire showTitle through to WorkbenchStandardPlotControls for IV/RT/XY")

        let threeOmegaSrc = try loadSource("Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift")
        #expect(threeOmegaSrc.contains("showTitle:"), "ThreeOmegaWorkspaceView.swift must still pass showTitle to WorkbenchStandardPlotControls")

        for (file, path) in [
            ("IVWorkspaceView.swift", "Sources/SpinLabApp/Features/Workbench/IVWorkspaceView.swift"),
            ("RTWorkspaceView.swift", "Sources/SpinLabApp/Features/Workbench/RTWorkspaceView.swift"),
            ("XYRotationWorkspaceView.swift", "Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift"),
        ] {
            let src = try loadSource(path)
            #expect(src.contains("store:"), "\(file) must pass its store to the shared store-driven WorkbenchStandardPlotControls initializer, which derives showTitle")
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
