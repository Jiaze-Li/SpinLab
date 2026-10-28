import AppKit
import SwiftUI
import Testing
@testable import SpinLabApp

/// Real SwiftUI layout of the AFM Specific section (CS-18b): three logical lines, Channel · Surface
/// Level / Line Flatten · Zero / Scale Bar · Bar text (· Length), over the real AFM store.
@MainActor
@Suite("Controls Surface — AFM Specific logical lines")
struct AFMSpecificLayoutTests {
    private typealias F = ControlsSurfaceFixtures
    private let widths: [CGFloat] = [300, 364, 420, 520, 667, 720]
    private let tolerance: CGFloat = 1.0

    private static let settings: [AFMScaleBarSetting] = [
        AFMScaleBarSetting(mode: .off),
        AFMScaleBarSetting(mode: .auto),
        AFMScaleBarSetting(mode: .manual, manualLengthMicrometers: 2, color: .black),
    ]

    private func host(_ setting: AFMScaleBarSetting, width: CGFloat) -> ControlsSurfaceHost<WorkbenchControlsSurface> {
        let appState = SpinLabAppState()
        appState.workbench.afmWorkspace.scaleBar = setting
        let descriptor = WorkbenchWorkflowKind.afm.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:]))
        return ControlsSurfaceHost(width: width) { WorkbenchControlsSurface(descriptor: descriptor) }
    }

    private func id(_ group: String, _ row: String) -> String { "controls.specific.\(group).\(row)" }
    private var channel: String { id("dataChannel", "channel") }
    private var level: String { id("processing", "surfaceLevel") }
    private var flatten: String { id("processing", "lineFlatten") }
    private var zero: String { id("processing", "zero") }
    private var bar: String { id("plotDecoration", "scaleBar") }
    private var barText: String { id("plotDecoration", "barText") }
    private var barLength: String { id("plotDecoration", "barLength") }

    private func sameLine(_ a: CGRect, _ b: CGRect) -> Bool { abs(a.minY - b.minY) <= tolerance }

    @Test("667pt: Channel·Surface Level / Line Flatten·Zero / Scale Bar·Bar text(·Length) are three lines, in order")
    func threeLogicalLinesAt667() {
        for setting in Self.settings {
            let h = host(setting, width: 667)
            let f = h.probe.frames
            let name = "\(setting.mode)"
            guard let c = f[channel], let l = f[level], let lf = f[flatten], let z = f[zero], let b = f[bar] else {
                Issue.record("\(name): AFM controls missing"); continue
            }
            #expect(sameLine(c, l) && c.maxX <= l.minX + tolerance, "\(name): Channel then Surface Level share a line")
            #expect(sameLine(lf, z) && lf.maxX <= z.minX + tolerance, "\(name): Line Flatten then Zero share a line")
            #expect(c.maxY <= lf.minY + tolerance && lf.maxY <= b.minY + tolerance, "\(name): lines are stacked in data → processing → decoration order")
            switch setting.mode {
            case .off:
                #expect(f[barText] == nil && f[barLength] == nil, "Off shows only Scale Bar")
            case .auto:
                #expect(f[barText].map { sameLine(b, $0) && b.maxX <= $0.minX + tolerance } == true, "Auto: Bar text beside Scale Bar")
                #expect(f[barLength] == nil)
            case .manual:
                if let t = f[barText], let len = f[barLength] {
                    #expect(sameLine(b, t) && sameLine(t, len) && b.maxX <= t.minX + tolerance && t.maxX <= len.minX + tolerance, "Manual: Scale Bar, Bar text, Length on one line")
                } else { Issue.record("Manual: Bar text / Length missing") }
            }
            #expect(f.keys.allSatisfy { !$0.lowercased().contains("edgecrop") }, "Edge Crop placeholder is not shown")
        }
    }

    @Test("Sound geometry at 300/364/420/520/667/720 for Scale Bar Off, Auto and Manual")
    func geometryAtEveryWidth() {
        for setting in Self.settings {
            let h = host(setting, width: 300)
            for width in widths {
                h.resize(to: width)
                let problems = ControlsGeometry.problems(h.probe, width: width)
                let frames = h.probe.frames
                func box(_ id: String) -> String { frames[id].map { "\(Int($0.minX.rounded())),\(Int($0.minY.rounded()))+\(Int($0.width.rounded()))x\(Int($0.height.rounded()))" } ?? "-" }
                print("[AFM-SPECIFIC-FRAMES] \(setting.mode)@\(Int(width)) channel=\(box(channel)) level=\(box(level)) flatten=\(box(flatten)) zero=\(box(zero)) bar=\(box(bar)) text=\(box(barText)) length=\(box(barLength))")
                #expect(problems.isEmpty, "\(setting.mode)@\(Int(width)): \(problems)")
                let f = h.probe.frames
                // Reading order is data → processing → decoration at every width.
                let order = [channel, level, flatten, zero, bar].compactMap { f[$0] }
                #expect(order.count == 5)
                for (a, b) in zip(order, order.dropFirst()) {
                    #expect(b.minY >= a.maxY - tolerance || b.minX >= a.maxX - tolerance, "\(setting.mode)@\(Int(width)): order broken \(a) -> \(b)")
                }
                // Companions never sit on a line above their main control, and Length never above Bar text.
                if let t = f[barText] { #expect(t.minY >= f[bar]!.minY - tolerance, "\(setting.mode)@\(Int(width)): Bar text above Scale Bar") }
                if let t = f[barText], let len = f[barLength] {
                    #expect(len.minY >= t.minY - tolerance, "\(setting.mode)@\(Int(width)): Length above Bar text")
                }
            }
        }
    }

    @Test("Zero is not alone on its line once Line Flatten and Zero fit together; Scale Bar changes move no line above it")
    func zeroNotOrphanedAndUpperLinesStay() {
        for width in widths {
            let hosts = Self.settings.map { host($0, width: width) }
            for h in hosts {
                let f = h.probe.frames
                if width >= 420 { #expect(sameLine(f[flatten]!, f[zero]!), "Zero must share Line Flatten's line @\(Int(width))") }
                if width >= 667 { #expect(sameLine(f[channel]!, f[level]!), "Surface Level shares Channel's line @\(Int(width))") }
            }
            // Switching Scale Bar mode must not move anything above the decoration line.
            for id in [channel, level, flatten, zero, "controls.specific.selection", "controls.specific.flattening"] {
                let rects = hosts.compactMap { $0.probe.frames[id] }
                #expect(rects.count == hosts.count)
                for r in rects.dropFirst() { #expect(r == rects[0] || (abs(r.minX - rects[0].minX) <= tolerance && abs(r.minY - rects[0].minY) <= tolerance && abs(r.width - rects[0].width) <= tolerance), "\(id) moved with Scale Bar mode @\(Int(width))") }
            }
        }
    }

    @Test("Menus take their intrinsic width: identical for every Scale Bar selection, never the shared wide width")
    func menuWidthsAreContentFit() {
        var widthsByMode: [[String: CGFloat]] = []
        for setting in Self.settings {
            let h = host(setting, width: 720)
            let f = h.probe.frames
            widthsByMode.append([level, flatten, zero, bar].reduce(into: [:]) { $0[$1] = f[$1 + "#content"]?.width })
            for key in [level, flatten, zero, bar] {
                let w = f[key + "#content"]?.width ?? 0
                #expect(w >= WorkbenchInputWidth.menuMinimum, "\(key) below the menu minimum")
                #expect(w < WorkbenchInputWidth.wide, "\(key) stretched to the shared wide width (\(w))")
            }
        }
        for w in widthsByMode.dropFirst() { #expect(w == widthsByMode[0], "menu width must not follow the selection") }
        print("[AFM-SPECIFIC-WIDTHS] \(widthsByMode[0])")
    }

    @Test("Long option and channel names stay whole: row wraps instead of squeezing the menu")
    func longMenusWrapWhole() {
        let channels = ["Height Trace (forward, flattened) 2", "Amplitude Error Retrace Long Name", "Z"]
        var selection = channels[0]
        let content = WorkbenchSpecificContent {
            WorkbenchSpecificGroup("dataChannel", title: "Data Channel") {
                WorkbenchSpecificRow("channel", label: "Channel", line: "selection", atomic: true) {
                    WorkbenchSpecificInput.menu("picker", selection: Binding(get: { selection }, set: { selection = $0 }),
                                                options: channels.map { (title: $0, value: $0) }, contentFit: true)
                }
            }
            WorkbenchSpecificGroup("processing", title: "Processing") {
                WorkbenchSpecificRow("surfaceLevel", label: "Surface Level", line: "selection", atomic: true) {
                    WorkbenchSpecificInput.menu("picker", selection: .constant("Robust Plane"),
                                                options: ["Off", "Plane", "Robust Plane"].map { (title: $0, value: $0) }, contentFit: true)
                }
            }
        }
        let h = ControlsSurfaceHost(width: 300) {
            WorkbenchControlsSurface(descriptor: F.descriptor(.heatmap(F.heatmap()), specific: content))
        }
        for width in widths {
            h.resize(to: width)
            #expect(ControlsGeometry.problems(h.probe, width: width).isEmpty, "long menus @\(Int(width)): \(ControlsGeometry.problems(h.probe, width: width))")
            let f = h.probe.frames
            if let c = f[channel + "#content"], let l = f[level + "#content"] {
                #expect(c.width > l.width, "Channel menu follows its longest name")
            }
        }
    }

    @Test("Other workflows keep their group containers: no line layout outside AFM")
    func otherWorkflowsKeepGroups() {
        let appState = SpinLabAppState()
        for kind in WorkbenchWorkflowKind.allCases where kind != .afm {
            #expect(!kind.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:])).specific.usesLines, "\(kind)")
        }
        #expect(WorkbenchWorkflowKind.afm.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:])).specific.groups.map(\.id)
                == ["dataChannel", "processing", "plotDecoration"])
    }

    @Test("Processing edits reach the store unchanged")
    func processingBindingsUnchanged() {
        let appState = SpinLabAppState()
        let store = appState.workbench.afmWorkspace
        store.updateSurfaceLevel(.robustPlane); store.updateLineFlattenOrder(.order2); store.updateZeroReference(.minimum)
        let configuration = store.processingConfiguration
        #expect(configuration.surfaceLevel == .robustPlane)
        #expect(configuration.lineFlattenOrder == .order2)
        #expect(configuration.zeroReference == .minimum)
        let d = WorkbenchWorkflowKind.afm.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:]))
        #expect(d.specific.groups.map(\.title) == ["Data Channel", "Processing", "Plot Decoration"], "semantic group ownership is unchanged")
        #expect(d.specific.groups.flatMap(\.rows).map(\.id).prefix(5) == ["channel", "surfaceLevel", "lineFlatten", "zero", "scaleBar"])
    }
}
