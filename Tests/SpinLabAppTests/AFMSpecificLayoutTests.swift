import AppKit
import SwiftUI
import Testing
@testable import SpinLabApp

/// Real SwiftUI layout of the AFM Specific section (CS-18b): region one `Channel · Leveling ·
/// (Line Flatten · Zero)`, region two `Scale Bar · Bar text (· Length)`, over a real AFM store.
@MainActor
@Suite("Controls Surface — AFM Specific logical regions", .rulesGlobalState)
struct AFMSpecificLayoutTests {
    private typealias F = ControlsSurfaceFixtures
    private let widths: [CGFloat] = [300, 364, 420, 520, 667, 720]
    private let tolerance: CGFloat = 1.0

    private static let settings: [AFMScaleBarSetting] = [
        AFMScaleBarSetting(mode: .off),
        AFMScaleBarSetting(mode: .auto),
        AFMScaleBarSetting(mode: .manual, manualLengthMicrometers: 2, color: .black),
    ]

    /// A real store restored from a Pack so the Channel menu carries a real channel name.
    private func store(channel label: String, bar: AFMScaleBarSetting) async throws -> AFMWorkspaceStore {
        let store = AFMWorkspaceStore(workflowID: "afm")
        try await load(store, channel: label, bar: bar)
        return store
    }

    private func load(_ store: AFMWorkspaceStore, channel label: String, bar: AFMScaleBarSetting) async throws {
        let n = 8
        let xs = (0..<n).map { Double($0) * 0.2 }
        let values = xs.map { y in xs.map { x in sin(x) + cos(y) + 0.1 * x } }
        let channel = CanonicalAFMChannel(
            id: "c", sourceIndex: 0, sourceLabel: label, semanticTypeRaw: "Height", displayLabel: label,
            values: values, canonicalUnit: "nm", sourceUnit: "m",
            provenance: AFMChannelProvenance(planefit: nil, planefitOrder: nil, flattenOrder: nil, planefitOffset: nil, planefitXSlope: nil, planefitYSlope: nil))
        let dataset = CanonicalAFMDataset(
            sourceRef: "/x.ibw", title: "T", xCoordinates: xs, yCoordinates: xs, channels: [channel],
            sourceMetadata: AFMSourceProvenance(sourceFilePath: "/x.ibw", waveName: "T", sourceWidth: n, sourceHeight: n, rawNote: ""))
        let result = AFMPackResult(canonicalDataset: dataset)
        let config = AFMPackConfig(packState: AFMPackState(processingConfiguration: AFMProcessingConfiguration(activeChannelID: "c"), scaleBar: bar),
                                   displayState: HeatmapTabRenderState())
        let pack = AnalysisPack(label: "t", workflowID: "afm", filePaths: ["/x.ibw"], sampleKeys: ["k"], sourceFingerprint: "f",
                                config: try JSONEncoder().encode(config), result: try JSONEncoder().encode(result))
        store.restoreFromPack(config: config, result: result, pack: pack, restoreSearchState: { _, _ in }, seedSelection: { _, _ in })
        for _ in 0..<300 where store.isAnalyzing || store.renderedImageData == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        try #require(store.renderedImageData != nil && !store.isAnalyzing, "the restored store must finish rendering")
    }

    private func host(_ store: AFMWorkspaceStore, width: CGFloat) -> ControlsSurfaceHost<WorkbenchControlsSurface> {
        let appState = SpinLabAppState()
        let descriptor = store.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:]))
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
    private let regionOne = "controls.specific.selection"
    private let regionTwo = "controls.specific.decoration"

    private func sameLine(_ a: CGRect, _ b: CGRect) -> Bool { abs(a.minY - b.minY) <= tolerance }
    private func box(_ f: [String: CGRect], _ id: String) -> String {
        f[id].map { "\(Int($0.minX.rounded())),\(Int($0.minY.rounded()))+\(Int($0.width.rounded()))x\(Int($0.height.rounded()))" } ?? "-"
    }

    @Test("Typical channel: the four groups share one line as soon as their native widths fit; Scale Bar always starts the next region")
    func fourGroupsShareALineWhenTheyFit() async throws {
        for setting in Self.settings {
            let s = try await store(channel: "DeflectionRetrace", bar: setting)
            // The width the four need is measured, not assumed: the narrowest width (1pt steps) at which Zero
            // shares Channel's line. Below it the pair Line Flatten · Zero wraps whole (checked at -8pt).
            let h = host(s, width: 720)
            var needed: CGFloat?
            for width in stride(from: CGFloat(720), through: 600, by: -1) {
                h.resize(to: width)
                guard let c = h.probe.frames[channel], let z = h.probe.frames[zero], sameLine(c, z) else { break }
                needed = width
            }
            let fit = try #require(needed)
            let name = "\(setting.mode)"
            print("[AFM-SPECIFIC-NEEDED] \(name) fourGroupsNeed=\(fit)pt")
            print("[AFM-SPECIFIC-NEEDED] fits at 667pt: \(fit <= 667)")
            for width in [fit, 720] {
                h.resize(to: width)
                let f = h.probe.frames
                let c = try #require(f[channel]), l = try #require(f[level]), lf = try #require(f[flatten]), z = try #require(f[zero]), b = try #require(f[bar])
                #expect([c, l, lf, z].allSatisfy { sameLine($0, c) }, "\(name)@\(Int(width)): four groups on one line")
                #expect(c.maxX <= l.minX + tolerance && l.maxX <= lf.minX + tolerance && lf.maxX <= z.minX + tolerance, "\(name): order Channel, Leveling, Line Flatten, Zero")
                #expect(b.minY >= c.maxY - tolerance && b.minX <= tolerance, "\(name)@\(Int(width)): Scale Bar starts a new region")
            }
            h.resize(to: fit - 8)
            let f = h.probe.frames
            #expect(sameLine(f[flatten]!, f[zero]!) && !sameLine(f[channel]!, f[flatten]!), "\(name): below the threshold the unit wraps whole")
        }
    }

    @Test("667pt: Channel · Leveling on the first line, Line Flatten · Zero wrapped together below, Scale Bar next")
    func layoutAt667() async throws {
        for setting in Self.settings {
            let h = host(try await store(channel: "DeflectionRetrace", bar: setting), width: 667)
            let f = h.probe.frames
            let name = "\(setting.mode)"
            print("[AFM-SPECIFIC-667] \(name) channel=\(box(f, channel)) leveling=\(box(f, level)) flatten=\(box(f, flatten)) zero=\(box(f, zero)) bar=\(box(f, bar)) text=\(box(f, barText)) length=\(box(f, barLength))")
            guard let c = f[channel], let l = f[level], let lf = f[flatten], let z = f[zero], let b = f[bar] else {
                Issue.record("\(name): AFM controls missing"); continue
            }
            #expect(sameLine(c, l) && c.maxX <= l.minX + tolerance)
            #expect(sameLine(lf, z) && lf.maxX <= z.minX + tolerance && lf.minX <= tolerance, "\(name): Line Flatten · Zero are one unit")
            #expect(max(z.maxX, l.maxX) <= 667 + tolerance)
            #expect(lf.minY >= c.maxY - tolerance && b.minY >= lf.maxY - tolerance && b.minX <= tolerance)
            switch setting.mode {
            case .off: #expect(f[barText] == nil && f[barLength] == nil)
            case .auto:
                #expect(f[barText].map { sameLine(b, $0) && b.maxX <= $0.minX + tolerance } == true)
                #expect(f[barLength] == nil)
            case .manual:
                if let t = f[barText], let len = f[barLength] {
                    #expect(sameLine(b, t) && sameLine(t, len) && t.maxX <= len.minX + tolerance, "Manual: Scale Bar, Bar text, Length on one line")
                } else { Issue.record("Manual: Bar text / Length missing") }
            }
            #expect(f.keys.allSatisfy { !$0.lowercased().contains("edgecrop") })
        }
    }

    @Test("Sound geometry and reading order at 300/364/420/520/667/720 for Scale Bar Off, Auto and Manual")
    func geometryAtEveryWidth() async throws {
        for setting in Self.settings {
            let h = host(try await store(channel: "DeflectionRetrace", bar: setting), width: 300)
            for width in widths {
                h.resize(to: width)
                let problems = ControlsGeometry.problems(h.probe, width: width)
                #expect(problems.isEmpty, "\(setting.mode)@\(Int(width)): \(problems)")
                let f = h.probe.frames
                print("[AFM-SPECIFIC-FRAMES] \(setting.mode)@\(Int(width)) channel=\(box(f, channel)) leveling=\(box(f, level)) flatten=\(box(f, flatten)) zero=\(box(f, zero)) bar=\(box(f, bar)) text=\(box(f, barText)) length=\(box(f, barLength))")
                let order = [channel, level, flatten, zero, bar].compactMap { f[$0] }
                #expect(order.count == 5)
                for (a, b) in zip(order, order.dropFirst()) {
                    #expect(b.minY >= a.maxY - tolerance || b.minX >= a.maxX - tolerance, "\(setting.mode)@\(Int(width)): order broken \(a) -> \(b)")
                }
                // Line Flatten and Zero wrap as one unit: Zero is never alone below Line Flatten
                // while the two could sit together on a line of their own.
                if width >= 364 { #expect(sameLine(f[flatten]!, f[zero]!), "Line Flatten · Zero must stay together @\(Int(width))") }
                if let t = f[barText] { #expect(t.minY >= f[bar]!.minY - tolerance) }
                if let t = f[barText], let len = f[barLength] { #expect(len.minY >= t.minY - tolerance) }
            }
        }
    }

    @Test("Line Flatten · Zero wrap together: when the first line cannot hold them, both drop to the next line")
    func flattenAndZeroWrapAsOne() async throws {
        let h = host(try await store(channel: "DeflectionRetrace", bar: Self.settings[0]), width: 667)
        var sawWrap = false
        for width in stride(from: CGFloat(720), through: 330, by: -10) {
            h.resize(to: width)
            let f = h.probe.frames
            guard let c = f[channel], let lf = f[flatten], let z = f[zero] else { continue }
            #expect(sameLine(lf, z), "Line Flatten and Zero split @\(Int(width))")
            if lf.minY > c.minY + tolerance { sawWrap = true; #expect(lf.minX <= tolerance, "wrapped unit starts the next line @\(Int(width))") }
        }
        #expect(sawWrap, "the unit must wrap somewhere between 720 and 330pt")
    }

    @Test("Switching Scale Bar mode moves nothing in the first region")
    func scaleBarModeDoesNotMoveRegionOne() async throws {
        for width in widths {
            let hosts = try await Self.settings.asyncMap { host(try await store(channel: "DeflectionRetrace", bar: $0), width: width) }
            for key in [channel, level, flatten, zero, regionOne] {
                let rects = hosts.compactMap { $0.probe.frames[key] }
                #expect(rects.count == hosts.count)
                for r in rects.dropFirst() {
                    #expect(abs(r.minX - rects[0].minX) <= tolerance && abs(r.minY - rects[0].minY) <= tolerance && abs(r.width - rects[0].width) <= tolerance, "\(key) moved with Scale Bar mode @\(Int(width))")
                }
            }
        }
    }

    @Test("A long channel name wraps the whole unit and nothing is clipped")
    func longChannelNameWrapsWhole() async throws {
        let h = host(try await store(channel: "Amplitude Error Retrace (flattened, second pass)", bar: Self.settings[2]), width: 667)
        for width in widths {
            h.resize(to: width)
            let problems = ControlsGeometry.problems(h.probe, width: width)
            #expect(problems.isEmpty, "long channel @\(Int(width)): \(problems)")
            let f = h.probe.frames
            print("[AFM-SPECIFIC-LONG] @\(Int(width)) channel=\(box(f, channel)) leveling=\(box(f, level)) flatten=\(box(f, flatten)) zero=\(box(f, zero))")
            #expect(sameLine(f[flatten]!, f[zero]!) || width < 364)
            #expect((f[channel]?.width ?? 0) > (f[level]?.width ?? 0), "Channel menu follows its longest name")
        }
    }

    @Test("Menus take their intrinsic width: identical for every Scale Bar selection, never the shared wide width")
    func menuWidthsAreContentFit() async throws {
        var byMode: [[String: CGFloat]] = []
        for setting in Self.settings {
            let f = host(try await store(channel: "DeflectionRetrace", bar: setting), width: 720).probe.frames
            byMode.append([channel, level, flatten, zero, bar].reduce(into: [:]) { $0[$1] = f[$1 + "#content"]?.width })
            for key in [channel, level, flatten, zero, bar] {
                let w = f[key + "#content"]?.width ?? 0
                #expect(w >= WorkbenchInputWidth.menuMinimum, "\(key) below the menu minimum")
                #expect(w < WorkbenchInputWidth.wide, "\(key) stretched to the shared wide width (\(w))")
            }
        }
        for w in byMode.dropFirst() { #expect(w == byMode[0], "menu width must not follow the selection") }
        print("[AFM-SPECIFIC-WIDTHS] \(byMode[0])")
    }

    @Test("Placeholder selection: displayed, never stored; only a real pick writes")
    func placeholderSelectionIsNeverStored() {
        var stored = "gone"
        let binding = WorkbenchMenuPlaceholder.binding(Binding(get: { stored }, set: { stored = $0 }))
        #expect(WorkbenchMenuPlaceholder.isActive(selection: stored, options: ["c"]), "stale id → placeholder")
        #expect(WorkbenchMenuPlaceholder.isActive(selection: "", options: [String]()), "no options → placeholder")
        #expect(!WorkbenchMenuPlaceholder.isActive(selection: "c", options: ["c"]))
        #expect(binding.wrappedValue == nil, "the placeholder row is the selected one")
        binding.wrappedValue = nil
        #expect(stored == "gone", "selecting the placeholder writes nothing")
        binding.wrappedValue = "c"
        #expect(stored == "c", "picking a real channel writes its id")
    }

    @Test("Channel menu never renders blank, and follows the same live store from empty to loaded to stale")
    func channelMenuPlaceholders() async throws {
        let appState = SpinLabAppState()
        let store = AFMWorkspaceStore(workflowID: "afm")
        struct Live: View {
            let store: AFMWorkspaceStore
            let appState: SpinLabAppState
            var body: some View {
                WorkbenchControlsSurface(descriptor: store.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:])))
            }
        }
        let h = ControlsSurfaceHost(width: 720) { Live(store: store, appState: appState) }
        func width() -> CGFloat { h.resize(to: 720); return h.probe.frames[channel + "#content"]?.width ?? 0 }

        // Empty: a readable, disabled "No channel"; the empty id is not replaced by anything fake.
        let emptyWidth = width()
        print("[AFM-CHANNEL] empty=\(emptyWidth)")
        #expect(emptyWidth > WorkbenchInputWidth.menuMinimum + 30, "No channel text takes real width")
        #expect(store.processingConfiguration.activeChannelID == "")
        #expect(ControlsGeometry.problems(h.probe, width: 720).isEmpty)

        // Data loads into the same store: the same live view now shows the real channel.
        try await load(store, channel: "DeflectionRetrace", bar: Self.settings[0])
        let validWidth = width()
        print("[AFM-CHANNEL] valid=\(validWidth)")
        #expect(validWidth > emptyWidth, "the real name replaces the placeholder width")
        #expect(store.processingConfiguration.activeChannelID == "c")

        // Stale selection on the same store: placeholder is active but never written.
        store.processingConfiguration.activeChannelID = "gone"
        let staleWidth = width()
        #expect(staleWidth >= validWidth, "the menu still lists the real channel")
        #expect(store.processingConfiguration.activeChannelID == "gone", "rendering never rewrites the selection")
        let row = try #require(store.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:])).specific.groups.flatMap(\.rows).first { $0.id == "channel" })
        #expect(row.rowLabel == "Channel")

        // Back to a valid selection: width follows current content only.
        store.processingConfiguration.activeChannelID = "c"
        #expect(width() == validWidth)
    }

    @Test("Leveling shows Off / Plane / Robust; the full name stays in the accessibility semantics; stored values unchanged")
    func levelingNamesAndSemantics() async throws {
        let appState = SpinLabAppState()
        let store = try await store(channel: "DeflectionRetrace", bar: Self.settings[0])
        let d = store.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:]))
        let row = try #require(d.specific.groups.flatMap(\.rows).first { $0.id == "surfaceLevel" })
        #expect(row.rowLabel == "Leveling")
        #expect(d.specific.groups.flatMap(\.rows).first { $0.id == "zero" }?.rowLabel == "Zero")
        #expect(d.specific.groups.flatMap(\.rows).first { $0.id == "lineFlatten" }?.rowLabel == "Line Flatten")
        store.updateSurfaceLevel(.robustPlane)
        #expect(store.processingConfiguration.surfaceLevel == .robustPlane)
        #expect(AFMSurfaceLevel.robustPlane.fullName == "Robust Plane Leveling")
        #expect(AFMSurfaceLevel.plane.fullName == "Plane Leveling")
        #expect(AFMSurfaceLevel.allCases.map(\.fullName).count == 3)
    }

    @Test("Other workflows keep their group containers; AFM keeps its three semantic groups and identifiers")
    func otherWorkflowsKeepGroups() {
        let appState = SpinLabAppState()
        for kind in WorkbenchWorkflowKind.allCases where kind != .afm {
            #expect(!kind.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:])).specific.usesLines, "\(kind)")
        }
        let d = WorkbenchWorkflowKind.afm.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:]))
        #expect(d.specific.groups.map(\.id) == ["dataChannel", "processing", "plotDecoration"])
        #expect(d.specific.groups.map(\.title) == ["Data Channel", "Processing", "Plot Decoration"])
        #expect(d.specific.groups.flatMap(\.rows).map(\.id).prefix(5) == ["channel", "surfaceLevel", "lineFlatten", "zero", "scaleBar"])
        #expect(d.specific.groups.flatMap(\.rows).filter { $0.cluster != nil }.map(\.id) == ["lineFlatten", "zero"], "only Line Flatten · Zero are clustered")
        #expect(d.specific.groups.flatMap(\.rows).filter(\.accessory).allSatisfy { ["barText", "barLength"].contains($0.id) }, "only the conditional Scale Bar companions are accessories")
    }

    @Test("Processing edits reach the store unchanged")
    func processingBindingsUnchanged() {
        let store = AFMWorkspaceStore(workflowID: "afm")
        store.updateSurfaceLevel(.robustPlane); store.updateLineFlattenOrder(.order2); store.updateZeroReference(.minimum)
        let configuration = store.processingConfiguration
        #expect(configuration.surfaceLevel == .robustPlane)
        #expect(configuration.lineFlattenOrder == .order2)
        #expect(configuration.zeroReference == .minimum)
    }
}

private extension Array {
    @MainActor func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var out: [T] = []
        for element in self { out.append(try await transform(element)) }
        return out
    }
}
