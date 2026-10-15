import Foundation
import SwiftUI
import Testing
@testable import SpinLabApp

/// Behaviour of the workflow adapters behind the shared Controls Surface (spec 06 CS-28):
/// what each Common/Plot control writes into the real store and whether it schedules an
/// interaction-snapshot flush. These replace the old source-text checks of the per-workflow
/// views, which asserted how the legacy assemblers were wired rather than what they do.
@MainActor
@Suite("Controls adapters — state and persistence policy (real stores)")
struct ControlsWorkflowAdapterTests {
    private func descriptor(_ kind: WorkbenchWorkflowKind, _ appState: SpinLabAppState) -> WorkbenchControlsDescriptor {
        kind.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:]))
    }

    /// A schedule request sets the pending flag synchronously and clears it on the next turn.
    private func settle(_ appState: SpinLabAppState) async {
        for _ in 0..<5 where appState.isInteractionSnapshotFlushPending { await Task.yield() }
        appState.isInteractionSnapshotFlushPending = false
    }

    private func exercise<Store: WorkbenchStandardPlotWorkspaceStore>(
        _ store: Store, kind: WorkbenchWorkflowKind, appState: SpinLabAppState
    ) async {
        let name = "\(kind)"
        let d = descriptor(kind, appState)
        guard case .cartesianXY(let plot) = d.plot else { Issue.record("\(name) must be cartesianXY"); return }
        await settle(appState)

        // Persisted style change: written to the store AND flushed.
        d.common.onShowTitleChange(false)
        #expect(store.tabs.activeState.showTitle == false, "\(name) showTitle")
        #expect(appState.isInteractionSnapshotFlushPending, "\(name) showTitle is a persisted change")
        await settle(appState)
        plot.onChange()
        #expect(appState.isInteractionSnapshotFlushPending, "\(name) onChange flushes")
        await settle(appState)

        // Bindings reach the store.
        plot.stackOffset.wrappedValue = 0.7
        plot.minGapFraction.wrappedValue = 0.25
        plot.titleTemplate.wrappedValue = "#tab #sample"
        plot.seriesRenderMode.wrappedValue = .scatter
        #expect(store.stackOffsetMultiplier == 0.7, "\(name) stack")
        #expect(store.minGapFraction == 0.25, "\(name) gap")
        #expect(store.titleTemplate == "#tab #sample", "\(name) title template")
        #expect(store.seriesRenderMode == .scatter, "\(name) render mode")
        let grid = plot.showGrid.wrappedValue
        plot.showGrid.wrappedValue = !grid
        #expect(store.showPlotGrid == !grid, "\(name) grid")
        plot.chartStyleOverrides.wrappedValue = ["tickTargetX": "7"]
        #expect(store.chartStyleOverrides["tickTargetX"] == "7", "\(name) chart style overrides")
        await settle(appState)

        // Transient per-tab render state: written to the store, NEVER flushed.
        d.common.onTitleOverride("My title")
        #expect(store.tabs.activeState.titleOverride == "My title", "\(name) title override")
        plot.onXLabelOverride("X!")
        plot.onYLabelOverride("Y!")
        #expect(store.tabs.activeState.xLabelOverride == "X!", "\(name) x label")
        #expect(store.tabs.activeState.yLabelOverride == "Y!", "\(name) y label")
        plot.onAxisBoundUpdate(.xMin, 1)
        plot.onAxisBoundUpdate(.yMax, 9)
        #expect(store.tabs.activeState.axisRangeOverride?.xMin == 1, "\(name) x min")
        #expect(store.tabs.activeState.axisRangeOverride?.yMax == 9, "\(name) y max")
        plot.onTickCountUpdate(.x, 8)
        #expect(store.tabs.activeState.tickOverride?.x == 8, "\(name) tick count")
        #expect(!appState.isInteractionSnapshotFlushPending, "\(name): transient edits must not flush the snapshot")

        // Reset clears every range override atomically, with no flush.
        plot.onResetRanges()
        #expect(store.tabs.activeState.axisRangeOverride == nil, "\(name) reset ranges")
        #expect(!appState.isInteractionSnapshotFlushPending, "\(name): reset must not flush the snapshot")
    }

    @Test("AHE, IV, RT, XY Rotation and 3ω (Cartesian tabs) share one adapter contract")
    func standardStoresShareOneContract() async {
        let appState = SpinLabAppState()
        let wb = appState.workbench
        await exercise(wb.aheWorkspace, kind: .ahe, appState: appState)
        await exercise(wb.ivWorkspace, kind: .iv, appState: appState)
        await exercise(wb.rtWorkspace, kind: .rt, appState: appState)
        await exercise(wb.xyRotationWorkspace, kind: .xyRotation, appState: appState)
        await exercise(wb.threeOmegaWorkspace, kind: .threeOmega, appState: appState)
    }

    @Test("3ω Temperature Dependence: range reset is atomic and transient; persisted edits flush")
    func threeOmegaDualAxisPolicy() async {
        let appState = SpinLabAppState()
        let store = appState.workbench.threeOmegaWorkspace
        store.tabs.activeTab = .temperatureDependence
        let d = descriptor(.threeOmega, appState)
        guard case .dualAxis(let plot) = d.plot else { Issue.record("TD must be dualAxis"); return }
        await settle(appState)

        store.temperatureDependenceDisplayState.axisRangeOverride = DualAxisAxisRangeOverrideFixture.some
        plot.onResetRanges()
        #expect(store.temperatureDependenceDisplayState.axisRangeOverride == nil)
        #expect(!appState.isInteractionSnapshotFlushPending, "range reset is transient")
        plot.onTransientChange()
        #expect(!appState.isInteractionSnapshotFlushPending)
        plot.onDisplayStateChange()
        #expect(appState.isInteractionSnapshotFlushPending, "title template / typography / ticks are persisted")
        await settle(appState)
    }

    @Test("Stack offset and gap exist only in the Cartesian XY Plot section")
    func stackGapOnlyCartesian() {
        let appState = SpinLabAppState()
        let store = appState.workbench.threeOmegaWorkspace
        for tab in ThreeOmegaWorkbenchTab.allCases {
            store.tabs.activeTab = tab
            let host = ControlsSurfaceHost(width: 520) {
                WorkbenchControlsSurface(descriptor: self.descriptor(.threeOmega, appState))
            }
            let hasSpacing = host.probe.frames.keys.contains { $0.hasPrefix("controls.plot.spacing") }
            #expect(hasSpacing == (tab != .temperatureDependence), "\(tab)")
        }
    }

    @Test("No Clear Plot or analysis action is placed inside the Controls Surface")
    func clearPlotStaysInResultShell() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("Sources/SpinLabApp/Workbench/Modules/PlotSystem/ControlsSurface")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("clearPlot"), "\(file.lastPathComponent)")
            #expect(!source.contains("Clear Plot"), "\(file.lastPathComponent)")
        }
    }

    @Test("Controls code keeps the minimum font rule: no .caption2 and no bare .caption")
    func minimumFontRule() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SpinLabApp")
        var offenders: [String] = []
        let scopes = ["Workbench/Modules/PlotSystem/ControlsSurface", "Workbench/Modules/PlotSystem/Controls"]
        let adapterFiles = ["AHESpecificPlotControls", "IVSpecificPlotControls", "XYRotationSpecificControls",
                            "ThreeOmegaSpecificControls", "RSMSpecificControls", "AFMPlotControls",
                            "WorkbenchStandardControlsAdapter", "WorkbenchHeatmapControlsAdapter"]
        var urls: [URL] = []
        for scope in scopes {
            let e = FileManager.default.enumerator(at: root.appendingPathComponent(scope), includingPropertiesForKeys: nil)
            while let url = e?.nextObject() as? URL { if url.pathExtension == "swift" { urls.append(url) } }
        }
        for name in adapterFiles { urls.append(root.appendingPathComponent("Features/Workbench/\(name).swift")) }
        for url in urls {
            let source = try String(contentsOf: url, encoding: .utf8)
            let code = source.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            if code.contains(".caption2") { offenders.append("\(url.lastPathComponent): .caption2") }
            if code.contains(".font(.caption)") { offenders.append("\(url.lastPathComponent): .font(.caption)") }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }
}

private enum DualAxisAxisRangeOverrideFixture {
    static var some: DualAxisAxisRangeOverride? { DualAxisAxisRangeOverride(xMin: 1, xMax: 2) }
}
