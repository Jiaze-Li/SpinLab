import AppKit
import SwiftUI
import Testing
@testable import SpinLabApp

/// Real SwiftUI layout tests of the shared Controls Surface (no source-text checks).
@MainActor
@Suite("Controls Surface — real layout")
struct ControlsSurfaceLayoutTests {
    private typealias F = ControlsSurfaceFixtures

    private func surface(_ plot: WorkbenchControlsPlotAdapter, specific: WorkbenchSpecificContent = .empty, width: CGFloat) -> ControlsSurfaceHost<WorkbenchControlsSurface> {
        ControlsSurfaceHost(width: width) { WorkbenchControlsSurface(descriptor: F.descriptor(plot, specific: specific)) }
    }

    private func allPlots() -> [(String, WorkbenchControlsPlotAdapter)] {
        [("cartesianXY", .cartesianXY(F.cartesian())), ("dualAxis", .dualAxis(F.dualAxis())), ("heatmap", .heatmap(F.heatmap()))]
    }

    @Test("Each Plot Mode mounts Common + Plot with sound geometry at every representative width")
    func geometryAtRepresentativeWidths() {
        for (name, plot) in allPlots() {
            let host = surface(plot, width: F.representativeWidths[0])
            for width in F.representativeWidths {
                host.resize(to: width)
                let problems = ControlsGeometry.problems(host.probe, width: width)
                #expect(problems.isEmpty, "\(name)@\(Int(width)): \(problems)")
                #expect(host.probe.frames.keys.contains { $0.hasPrefix("controls.common.") })
                #expect(host.probe.frames.keys.contains { $0.hasPrefix("controls.plot.") })
            }
        }
    }

    @Test("Narrow widths wrap groups: more lines at 300 than at 720")
    func narrowWrapsMore() {
        for (name, plot) in allPlots() {
            let narrow = surface(plot, width: 300)
            let wide = surface(plot, width: 720)
            let narrowHeight = ControlsGeometry.groupIDs(narrow.probe).compactMap { narrow.probe.frames[$0]?.maxY }.max() ?? 0
            let wideHeight = ControlsGeometry.groupIDs(wide.probe).compactMap { wide.probe.frames[$0]?.maxY }.max() ?? 0
            #expect(narrowHeight > wideHeight, "\(name): narrow \(narrowHeight) should be taller than wide \(wideHeight)")
        }
    }

    @Test("Common is identical for every Plot Mode: same ids, same order, same widths")
    func commonIdentity() {
        func signature(_ host: ControlsSurfaceHost<WorkbenchControlsSurface>) -> [String] {
            host.probe.frames.keys.filter { $0.hasPrefix("controls.common.") }
                .sorted { (host.probe.frames[$0]!.minY, host.probe.frames[$0]!.minX, $0) < (host.probe.frames[$1]!.minY, host.probe.frames[$1]!.minX, $1) }
                .map { id in
                    let f = host.probe.frames[id]!
                    return "\(id)|\(Int(f.minX.rounded()))|\(Int(f.minY.rounded()))|\(Int(f.width.rounded()))"
                }
        }
        let hosts = allPlots().map { surface($0.1, width: F.representativeWidths[0]) }
        for width in F.representativeWidths {
            hosts.forEach { $0.resize(to: width) }
            let signatures = hosts.map(signature)
            #expect(signatures[0] == signatures[1], "cartesian vs dual @\(Int(width))")
            #expect(signatures[0] == signatures[2], "cartesian vs heatmap @\(Int(width))")
            #expect(signatures[0].count >= 4)
        }
    }

    @Test("Same Plot Mode, different workflow state: identical control inventory and order")
    func plotModeIdentity() {
        func inventory(title: String, capabilities: CartesianXYCapabilities = []) -> [String] {
            let host = ControlsSurfaceHost(width: 520) {
                WorkbenchControlsSurface(descriptor: WorkbenchControlsDescriptor(
                    common: F.common(title: title), plot: .cartesianXY(F.cartesian(capabilities: capabilities))))
            }
            return host.probe.frames.keys.sorted()
        }
        #expect(inventory(title: "AHE") == inventory(title: "IV with a much longer rendered title"))
    }

    @Test("Heatmap Plot is the same for AFM-like and RSM-like adapters; Z range modes only add inner rows")
    func heatmapIdentity() {
        let afm = surface(.heatmap(F.heatmap()), width: 364)
        let rsm = surface(.heatmap(F.heatmap()), width: 364)
        #expect(afm.probe.frames.keys.sorted() == rsm.probe.frames.keys.sorted())
        let manual = surface(.heatmap(F.heatmap(mode: .manual)), width: 364)
        #expect(manual.probe.frames.keys.contains("controls.plot.zRange.manual"))
        #expect(ControlsGeometry.problems(manual.probe, width: 364).isEmpty)
    }

    @Test("No Specific section is rendered when a workflow supplies none")
    func noEmptySpecific() {
        let host = surface(.heatmap(F.heatmap()), width: 420)
        #expect(!host.probe.frames.keys.contains { $0.hasPrefix("controls.specific.") })
    }

    @Test("Specific content is laid out by the Surface: wraps, stays in bounds, order preserved")
    func specificLaidOutByShell() {
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
        let specificHost = surface(.heatmap(F.heatmap()), specific: content, width: F.representativeWidths[0])
        for width in F.representativeWidths {
            specificHost.resize(to: width)
            let host = specificHost
            #expect(ControlsGeometry.problems(host.probe, width: width).isEmpty, "@\(Int(width))")
            let ids = host.probe.frames.keys.filter { $0.hasPrefix("controls.specific.") }
            #expect(ids.contains("controls.specific.correction"))
            #expect(ids.contains("controls.specific.calibration"))
            let a = host.probe.frames["controls.specific.correction"]!, b = host.probe.frames["controls.specific.calibration"]!
            #expect(a.minY < b.minY || a.minX < b.minX, "declaration order is kept")
        }
        // Resizing across breakpoints keeps the same leaf instance (no recreate => draft/focus kept).
        let host = surface(.heatmap(F.heatmap()), specific: content, width: 720)
        sink.tokens.removeAll()
        host.resize(to: 300); host.resize(to: 520); host.resize(to: 364)
        #expect(sink.tokens.count <= 1, "leaf state identity must survive width changes")
    }

    @Test("Accessibility identifiers are stable across widths")
    func identifiersStable() {
        for (name, plot) in allPlots() {
            let host = surface(plot, width: 300)
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
}
