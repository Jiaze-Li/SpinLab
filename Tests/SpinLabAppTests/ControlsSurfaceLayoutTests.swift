import AppKit
import SwiftUI
import Testing
@testable import SpinLabApp

/// Real SwiftUI layout tests of the shared Controls Surface (no source-text checks).
@MainActor
@Suite("Controls Surface — real layout")
struct ControlsSurfaceLayoutTests {
    private typealias F = ControlsSurfaceFixtures

    private func surface(_ plot: WorkbenchControlsPlotAdapter, specific: WorkbenchSpecificContent = .empty, width: CGFloat) async -> ControlsSurfaceHost<WorkbenchControlsSurface> {
        // Host creation is expensive; yield afterwards so other main-actor work (and its
        // time-based expectations) is never starved for the length of a whole test.
        let host = ControlsSurfaceHost(width: width) { WorkbenchControlsSurface(descriptor: F.descriptor(plot, specific: specific)) }
        await Task.yield()
        return host
    }

    private func allPlots() -> [(String, WorkbenchControlsPlotAdapter)] {
        [("cartesianXY", .cartesianXY(F.cartesian())), ("dualAxis", .dualAxis(F.dualAxis())), ("heatmap", .heatmap(F.heatmap()))]
    }

    @Test("Each Plot Mode mounts Common + Plot with sound geometry at every representative width")
    func geometryAtRepresentativeWidths() async {
        for (name, plot) in allPlots() {
            let host = await surface(plot, width: F.representativeWidths[0])
            for width in F.representativeWidths {
                host.resize(to: width)
                await Task.yield()
                let problems = ControlsGeometry.problems(host.probe, width: width)
                #expect(problems.isEmpty, "\(name)@\(Int(width)): \(problems)")
                #expect(host.probe.frames.keys.contains { $0.hasPrefix("controls.common.") })
                #expect(host.probe.frames.keys.contains { $0.hasPrefix("controls.plot.") })
            }
        }
    }

    @Test("Narrow widths wrap groups: more lines at 300 than at 720")
    func narrowWrapsMore() async {
        for (name, plot) in allPlots() {
            let narrow = await surface(plot, width: 300)
            let wide = await surface(plot, width: 720)
            let narrowHeight = ControlsGeometry.groupIDs(narrow.probe).compactMap { narrow.probe.frames[$0]?.maxY }.max() ?? 0
            let wideHeight = ControlsGeometry.groupIDs(wide.probe).compactMap { wide.probe.frames[$0]?.maxY }.max() ?? 0
            #expect(narrowHeight > wideHeight, "\(name): narrow \(narrowHeight) should be taller than wide \(wideHeight)")
        }
    }

    @Test("Common is identical for every Plot Mode: same ids, same order, same widths")
    func commonIdentity() async {
        func signature(_ host: ControlsSurfaceHost<WorkbenchControlsSurface>) -> [String] {
            host.probe.frames.keys.filter { $0.hasPrefix("controls.common.") }
                .sorted { (host.probe.frames[$0]!.minY, host.probe.frames[$0]!.minX, $0) < (host.probe.frames[$1]!.minY, host.probe.frames[$1]!.minX, $1) }
                .map { id in
                    let f = host.probe.frames[id]!
                    return "\(id)|\(Int(f.minX.rounded()))|\(Int(f.minY.rounded()))|\(Int(f.width.rounded()))"
                }
        }
        var hosts: [ControlsSurfaceHost<WorkbenchControlsSurface>] = []
        for (_, plot) in allPlots() { hosts.append(await surface(plot, width: F.representativeWidths[0])) }
        for width in F.representativeWidths {
            for h in hosts { h.resize(to: width); await Task.yield() }
            let signatures = hosts.map(signature)
            #expect(signatures[0] == signatures[1], "cartesian vs dual @\(Int(width))")
            #expect(signatures[0] == signatures[2], "cartesian vs heatmap @\(Int(width))")
            #expect(signatures[0].count >= 4)
        }
    }

    @Test("Same Plot Mode, different workflow state: identical control inventory and order")
    func plotModeIdentity() async {
        func inventory(title: String, capabilities: CartesianXYCapabilities = []) -> [String] {
            let host = ControlsSurfaceHost(width: 520) {
                WorkbenchControlsSurface(descriptor: WorkbenchControlsDescriptor(
                    common: F.common(title: title), plot: .cartesianXY(F.cartesian(capabilities: capabilities))))
            }
            return host.probe.frames.keys.sorted()
        }
        #expect(inventory(title: "AHE") == inventory(title: "IV with a much longer rendered title"))
    }

    @Test("Heatmap Plot: same capability configuration gives the same inventory; Axes/Typography follow the configuration; Z range modes only add inner rows")
    func heatmapIdentity() async {
        let afm = await surface(.heatmap(F.heatmap()), width: 364)
        let afm2 = await surface(.heatmap(F.heatmap()), width: 364)
        #expect(afm.probe.frames.keys.sorted() == afm2.probe.frames.keys.sorted())
        let rsm = await surface(.heatmap(F.heatmap(withAxes: true)), width: 364)
        let axisIDs = Set(rsm.probe.frames.keys).subtracting(afm.probe.frames.keys)
        #expect(axisIDs.contains("controls.plot.axisLabels.x") && axisIDs.contains("controls.plot.axisLabels.y"))
        #expect(axisIDs.contains("controls.plot.ticks.row"))
        #expect(Set(afm.probe.frames.keys).subtracting(rsm.probe.frames.keys).isEmpty, "the axis-free configuration is a strict subset")
        #expect(ControlsGeometry.problems(rsm.probe, width: 364).isEmpty)
        let manual = await surface(.heatmap(F.heatmap(mode: .manual)), width: 364)
        #expect(manual.probe.frames.keys.contains("controls.plot.zRange.manual"))
        #expect(ControlsGeometry.problems(manual.probe, width: 364).isEmpty)
    }

    @Test("No Specific section is rendered when a workflow supplies none")
    func noEmptySpecific() async {
        let host = await surface(.heatmap(F.heatmap()), width: 420)
        #expect(!host.probe.frames.keys.contains { $0.hasPrefix("controls.specific.") })
    }

    @Test("Specific content is laid out by the Surface: wraps, stays in bounds, order preserved")
    func specificLaidOutByShell() async {
        struct Probe: WorkbenchLeafInput {
            @State private var token = UUID()
            let sink: TokenSink
            var body: some View {
                let _ = { sink.tokens.insert(token) }()
                HStack { Text("φ"); TextField("0", text: .constant("")).frame(width: 64) }
            }
        }
        final class TokenSink { var tokens: Set<UUID> = [] }
        let sink = TokenSink()
        let content = WorkbenchSpecificContent {
            WorkbenchSpecificGroup("correction", title: "Data Correction") {
                WorkbenchSpecificRow("flags", label: "Options") {
                    WorkbenchSpecificInput.toggle("center", title: "Center", isOn: .constant(true))
                    WorkbenchSpecificInput.toggle("detrend", title: "Detrend", isOn: .constant(false))
                }
            }
            WorkbenchSpecificGroup("calibration", title: "Per-file Calibration") {
                WorkbenchSpecificRow("phi", label: "φ offset") {
                    WorkbenchSpecificInput.control("editor", Probe(sink: sink))
                }
            }
        }
        let specificHost = await surface(.heatmap(F.heatmap()), specific: content, width: F.representativeWidths[0])
        for width in F.representativeWidths {
            specificHost.resize(to: width)
            await Task.yield()
            let host = specificHost
            #expect(ControlsGeometry.problems(host.probe, width: width).isEmpty, "@\(Int(width))")
            let ids = host.probe.frames.keys.filter { $0.hasPrefix("controls.specific.") }
            #expect(ids.contains("controls.specific.correction"))
            #expect(ids.contains("controls.specific.calibration"))
            let a = host.probe.frames["controls.specific.correction"]!, b = host.probe.frames["controls.specific.calibration"]!
            #expect(a.minY < b.minY || a.minX < b.minX, "declaration order is kept")
        }
        // Resizing across breakpoints keeps the same leaf instance (no recreate => draft/focus kept).
        let host = await surface(.heatmap(F.heatmap()), specific: content, width: 720)
        sink.tokens.removeAll()
        host.resize(to: 300); host.resize(to: 520); host.resize(to: 364)
        #expect(sink.tokens.count <= 1, "leaf state identity must survive width changes")
    }

    @Test("Accessibility identifiers are stable across widths")
    func identifiersStable() async {
        for (name, plot) in allPlots() {
            let host = await surface(plot, width: 300)
            let narrow = host.probe.frames.keys.sorted()
            host.resize(to: 720)
            let wide = host.probe.frames.keys.sorted()
            #expect(narrow == wide, "\(name): ids must not depend on width")
            #expect(narrow.allSatisfy { $0.hasPrefix("controls.") })
        }
    }

    // The geometry checker must be able to fail — otherwise "no problems" proves nothing.
    @Test("Checker detects overlapping groups")
    func checkerDetectsOverlap() {
        let host = ControlsSurfaceHost(width: 400) {
            ZStack(alignment: .topLeading) {
                WorkbenchControlGroup(id: "controls.plot.alpha") { Text("alpha group content").frame(width: 200, height: 40) }
                WorkbenchControlGroup(id: "controls.plot.beta") { Text("beta group content").frame(width: 200, height: 40) }
                    .offset(x: 60, y: 10)
            }
            .coordinateSpace(name: WorkbenchControlMetrics.coordinateSpaceName)
        }
        let problems = ControlsGeometry.problems(host.probe, width: 400)
        #expect(problems.contains { $0.contains("overlaps") }, "\(problems)")
    }

    @Test("Checker detects clipping and out-of-bounds content")
    func checkerDetectsClipAndBounds() {
        let host = ControlsSurfaceHost(width: 300) {
            WorkbenchControlRow(id: "controls.plot.rigid.row", label: "Rigid") {
                Color.clear.frame(width: 400, height: 20)
            }
            .coordinateSpace(name: WorkbenchControlMetrics.coordinateSpaceName)
        }
        let problems = ControlsGeometry.problems(host.probe, width: 300)
        #expect(problems.contains { $0.contains("overflows") }, "rigid 400pt content in 300pt must be reported: \(problems)")
    }

    // MARK: Visual contract (VC-1…VC-5)

    @Test("Stack slider keeps its own minimum at every width, in Cartesian XY")
    func stackSliderKeepsMinimum() async {
        let host = await surface(.cartesianXY(F.cartesian()), width: F.representativeWidths[0])
        for width in F.representativeWidths {
            host.resize(to: width)
            await Task.yield()
            let sliders = host.probe.controlFrames(.slider)
            #expect(sliders.count == 1, "@\(Int(width))")
            for frame in sliders {
                #expect(frame.width + 0.5 >= WorkbenchInputWidth.sliderMinimum, "slider \(frame.width) @\(Int(width))")
                #expect(frame.width <= WorkbenchInputWidth.sliderIdeal + 0.5)
            }
            #expect(host.probe.undersizedControls.isEmpty, "\(host.probe.undersizedControls) @\(Int(width))")
        }
    }

    @Test("Common labels, checkboxes and fields use the shared label role in every Plot Mode")
    func commonUsesSharedRoles() async {
        let expected: [String: WorkbenchTextRole] = [
            "controls.common.showTitle.checkbox": .label, "controls.common.plotTitle.field": .label,
            "controls.common.titleTemplate.field": .label, "controls.common.transparent.checkbox": .label,
        ]
        for (name, plot) in allPlots() {
            let host = await surface(plot, width: 420)
            #expect(ControlsGeometry.roleProblems(host.probe, expecting: expected).isEmpty, "\(name)")
        }
    }

    @Test("Common groups share a first-text baseline when they share a line")
    func commonBaselineAligned() async {
        let host = await surface(.heatmap(F.heatmap()), width: F.representativeWidths[0])
        for width in F.representativeWidths {
            host.resize(to: width)
            await Task.yield()
            #expect(ControlsGeometry.baselineProblems(host.probe).isEmpty, "@\(Int(width)): \(ControlsGeometry.baselineProblems(host.probe))")
            #expect(host.probe.baselineOffsets["controls.common.showTitle"] != nil)
        }
    }

    @Test("Compound pairs stay on one line at every width; Gap wraps as a unit")
    func stackPairsStayTogether() async {
        let host = await surface(.cartesianXY(F.cartesian()), width: F.representativeWidths[0])
        for width in F.representativeWidths {
            host.resize(to: width)
            await Task.yield()
            #expect(host.probe.splitPairs.isEmpty, "@\(Int(width)): \(host.probe.splitPairs)")
        }
    }

    @Test("Checker detects a logical pair split across lines by wrapping")
    func checkerDetectsSplitPair() {
        let host = ControlsSurfaceHost(width: 120) {
            WorkbenchControlFlow {
                Slider(value: .constant(0.5), in: 0...1).frame(width: 100).workbenchPairMember("stack")
                Text("0.5×").frame(width: 60).workbenchPairMember("stack")
            }
        }
        #expect(host.probe.splitPairs.contains { $0.contains("stack") }, "\(host.probe.splitPairs)")
    }

    @Test("Checker detects a slider squeezed below its minimum")
    func checkerDetectsShortSlider() {
        let host = ControlsSurfaceHost(width: 400) {
            Slider(value: .constant(0.5), in: 0...1).frame(width: 30).workbenchControl(.slider)
        }
        let problems = ControlsGeometry.problems(host.probe, width: 400)
        #expect(problems.contains { $0.contains("slider") }, "\(problems)")
    }

    @Test("Checker detects a Common control that bypasses the shared text role")
    func checkerDetectsRoleBypass() {
        let host = ControlsSurfaceHost(width: 400) {
            Toggle("Show Title", isOn: .constant(true)).toggleStyle(.checkbox)
        }
        let problems = ControlsGeometry.roleProblems(host.probe, expecting: ["controls.common.showTitle.checkbox": .label])
        #expect(!problems.isEmpty)
    }

    @Test("Checker detects groups on one line whose baselines differ")
    func checkerDetectsBaselineMismatch() {
        let probe = WorkbenchLayoutProbe()
        probe.record(frame: CGRect(x: 0, y: 0, width: 100, height: 30), for: "controls.common.a")
        probe.record(frame: CGRect(x: 120, y: 0, width: 100, height: 30), for: "controls.common.b")
        probe.record(baselineOffset: 12, for: "controls.common.a")
        probe.record(baselineOffset: 20, for: "controls.common.b")
        #expect(!ControlsGeometry.baselineProblems(probe).isEmpty)
    }
}
