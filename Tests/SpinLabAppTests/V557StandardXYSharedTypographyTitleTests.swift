import Foundation
import SwiftUI
import Testing
@testable import SpinLabApp

/// Current Controls Surface replacement for the retired v5.5.7 source-inspection guards.
/// Title belongs to shared Common; all Plot Modes reuse shared Axes and typography.
@MainActor
@Suite("Shared Controls Surface — Title and range reset", .rulesGlobalState)
struct V557StandardXYSharedTypographyTitleTests {
    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadSource(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("Show Title is owned by shared Common and not duplicated by any Plot Mode")
    func sharedCommonOwnsTitle() throws {
        let surface = try loadSource("Sources/SpinLabApp/Workbench/Modules/PlotSystem/ControlsSurface/WorkbenchControlsSurface.swift")
        let common = try loadSource("Sources/SpinLabApp/Workbench/Modules/PlotSystem/ControlsSurface/WorkbenchCommonControls.swift")
        #expect(surface.contains("WorkbenchCommonControls(model: descriptor.common)"))
        #expect(common.contains("title: \"Show Title\""))
        #expect(common.contains("model.onShowTitleChange($0)"))
        #expect(common.contains("SharedPlotTransparentBackgroundToggle("))
        for file in ["CartesianXYPlotControls.swift", "DualAxisPlotControls.swift", "HeatmapPlotControls.swift"] {
            let src = try loadSource("Sources/SpinLabApp/Workbench/Modules/PlotSystem/ControlsSurface/" + file)
            #expect(!src.contains("title: \"Show Title\""), "\(file) must not duplicate Common's toggle")
            #expect(!src.contains("WorkbenchCommonControls("), "\(file) must not mount a second Common")
        }
    }

    @Test("Shared Common Title callbacks update the actual Cartesian and dual-axis stores")
    func titleCallbackReachesActualStores() {
        let appState = SpinLabAppState()
        let ahe = appState.workbench.aheWorkspace
        let cartesian = ahe.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:]))
        cartesian.common.onShowTitleChange(false)
        #expect(ahe.tabs.activeState.showTitle == false)
        #expect(ahe.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:])).common.showTitle == false)

        let omega = appState.workbench.threeOmegaWorkspace
        omega.tabs.activeTab = .temperatureDependence
        let dualAxis = omega.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:]))
        #expect(dualAxis.plot.mode == .dualAxis)
        dualAxis.common.onShowTitleChange(false)
        #expect(omega.temperatureDependenceDisplayState.showTitle == false)
        #expect(omega.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:])).common.showTitle == false)
    }

    @Test("Range reset is owned by shared Axes and wired from both Cartesian and dual-axis adapters")
    func resetRangesSharedWiring() throws {
        let root = "Sources/SpinLabApp/"
        let axes = try loadSource(root + "Workbench/Modules/PlotSystem/ControlsSurface/PlotAxesControls.swift")
        #expect(axes.contains("PlotRangeResetControl(hasActiveOverride: model.hasRangeOverride, onReset: model.onResetRanges, alwaysPresent: true)"))
        for name in ["CartesianXYPlotControls.swift", "DualAxisPlotControls.swift"] {
            let src = try loadSource(root + "Workbench/Modules/PlotSystem/ControlsSurface/" + name)
            #expect(src.contains("PlotAxesControls(model: axesModel"), "\(name) must use shared Axes")
            #expect(src.contains("onResetRanges: model.onResetRanges"), "\(name) must forward its reset callback")
            #expect(!src.contains("PlotRangeResetControl("), "\(name) must not create a second reset control")
        }
        let adapter = try loadSource(root + "Features/Workbench/WorkbenchStandardControlsAdapter.swift")
        #expect(adapter.contains("onResetRanges: { self.resetAxisRanges() }"))
        let omega = try loadSource(root + "Features/Workbench/ThreeOmegaSpecificControls.swift")
        #expect(omega.contains("onResetRanges: {"))
        let oldLayout = repoRoot().appendingPathComponent(root + "Workbench/Modules/PlotSystem/Controls/Common/WeightedRowLayout.swift")
        #expect(!FileManager.default.fileExists(atPath: oldLayout.path),
                "retired WeightedRowLayout must not be restored as a competing layout implementation")
    }
}
