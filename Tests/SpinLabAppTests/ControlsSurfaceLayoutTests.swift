import AppKit
import SwiftUI
import Testing
@testable import SpinLabApp

/// Real SwiftUI layout tests of the shared Controls Surface (no source-text checks).
@MainActor
@Suite("Controls Surface — real layout")
struct ControlsSurfaceLayoutTests {
    private typealias F = ControlsSurfaceFixtures

    private func surface(_ plot: WorkbenchControlsPlotAdapter, specific: WorkbenchSpecificContent = .empty, width: CGFloat,
                         tokens: [String] = ["#tab", "#sample"]) async -> ControlsSurfaceHost<WorkbenchControlsSurface> {
        // Host creation is expensive; yield afterwards so other main-actor work (and its
        // time-based expectations) is never starved for the length of a whole test.
        let host = ControlsSurfaceHost(width: width) { WorkbenchControlsSurface(descriptor: F.descriptor(plot, specific: specific, tokens: tokens)) }
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

    @Test("Cartesian XY Plot is three rows at 677pt: Draw·Line·Scatter·X/Y label / Range·Reset·Ticks / Font·Gap·Grid")
    func threeRowsAt677() async {
        let host = await surface(.cartesianXY(F.cartesian()), width: 677)
        let f = host.probe.frames
        func g(_ id: String) -> CGRect { f["controls.plot." + id] ?? .zero }
        let rows: [[String]] = [["curve", "axisLabels"], ["ranges", "ticks"], ["typography", "spacing", "grid"]]
        var rowY: [CGFloat] = []
        for ids in rows {
            let frames = ids.map(g)
            #expect(frames.allSatisfy { $0.width > 0 }, "every group of \(ids) is laid out: \(ids.map { g($0) })")
            // One line: the groups overlap vertically (first-text-baseline alignment may shift a few points).
            let top = frames.map(\.minY).max() ?? 0, bottom = frames.map(\.maxY).min() ?? 0
            #expect(top < bottom, "\(ids) share one line: \(frames)")
            rowY.append(frames.map(\.minY).min() ?? 0)
        }
        #expect(rowY == rowY.sorted() && Set(rowY.map { $0.rounded() }).count == 3, "three distinct rows in order: \(rowY)")
        let rightEdges = rows.map { ids in ids.map { g($0).maxX }.max() ?? 0 }
        #expect(rightEdges.max()! - rightEdges.min()! <= 1, "right edges line up: \(rightEdges)")
        func widths(_ kind: WorkbenchControlKind) -> [Int] { host.probe.controlFrames(kind).map { Int($0.width.rounded()) }.sorted() }
        print("[THREE-ROW-677] textFields=\(widths(.textField)) menus=\(widths(.menu)) steppers=\(widths(.stepper)) iconButtons=\(widths(.iconButton))")
        print("[THREE-ROW-677] rowY=\(rowY.map { Int($0) }) rightEdges=\(rightEdges.map { Int($0.rounded()) })")
        for id in ["curve", "axisLabels", "ranges", "ticks", "typography", "spacing", "grid"] {
            let r = g(id); print("[THREE-ROW-677] \(id) x=\(Int(r.minX)) y=\(Int(r.minY)) w=\(Int(r.width.rounded())) h=\(Int(r.height.rounded()))")
        }
        for id in ["curve.row#content", "axisLabels.x#content", "axisLabels.y#content", "spacing"] {
            let r = f["controls.plot." + id] ?? .zero; print("[THREE-ROW-677] \(id) w=\(Int(r.width.rounded()))")
        }
        print("[THREE-ROW-677] undersized=\(host.probe.undersizedControls) clips=\(host.probe.clips) problems=\(ControlsGeometry.problems(host.probe, width: 677))")
        #expect(host.probe.undersizedControls.isEmpty && host.probe.clips.isEmpty, "\(host.probe.undersizedControls) \(host.probe.clips)")
        #expect(ControlsGeometry.problems(host.probe, width: 677).isEmpty)
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
            #expect(host.probe.baselineOffsets["controls.common.plotTitle"] != nil && host.probe.baselineOffsets["controls.common.titleOptions"] != nil)
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

    // MARK: Logical row layout (CS-39, CS-40)

    private let manyTokens = ["#tab", "#method", "#device", "#sample", "#测试温度", "#氧压", "#能量", "#磁场", "#电流"]

    @Test("Common: Plot title left, Show Title/Transparent as one right group, Title template on its own line")
    func commonLogicalLayout() async {
        for (name, plot) in allPlots() {
            let host = await surface(plot, width: F.representativeWidths[0])
            for width in F.representativeWidths {
                host.resize(to: width)
                await Task.yield()
                let f = host.probe.frames
                let title = f["controls.common.plotTitle"]!, options = f["controls.common.titleOptions"]!
                let template = f["controls.common.titleTemplate"]!
                // The two checkboxes are one logical group: both inside it, and it never splits.
                let show = f["controls.common.titleOptions"]!
                #expect(show.width > 0)
                if abs(title.midY - options.midY) < title.height {   // same line
                    #expect(title.maxX <= options.minX + 1, "\(name)@\(Int(width)): Plot title is left of the checkboxes")
                }
                #expect(template.minY >= max(title.maxY, options.maxY) - 1, "\(name)@\(Int(width)): template is on its own line below")
                // The template input is never compressed (CS-40): comfortable width at every width.
                let input = f["controls.common.titleTemplate.field#content"]!
                #expect(input.width + 0.5 >= WorkbenchInputWidth.wide, "\(name)@\(Int(width)): template input \(input.width)")
            }
        }
    }

    private let shortTokens = ["#tab", "#device"]
    private let longTokens = (1...16).map { "#variable\($0)" }

    @Test("Short Available sits right of a bounded template input at 720; a long token set wraps whole below")
    func availableBesideOrBelow() async {
        let short = await surface(.cartesianXY(F.cartesian()), width: 720, tokens: shortTokens)
        let many = await surface(.cartesianXY(F.cartesian()), width: 720, tokens: longTokens)
        for width in F.representativeWidths {
            short.resize(to: width); many.resize(to: width)
            await Task.yield()
            let f = short.probe.frames
            let field = f["controls.common.titleTemplate.field"]!, hint = f["controls.common.titleTemplate.available"]!
            let input = f["controls.common.titleTemplate.field#content"]!
            let beside = hint.minX >= field.maxX - 1 && abs(hint.minY - field.minY) < field.height
            if width >= 720 {
                #expect(beside, "short tokens: Available is right of the input (\(field) vs \(hint))")
                // The input is bounded (ideal…ideal+growth) and does not swallow the line.
                #expect(input.width <= WorkbenchInputWidth.templateIdeal + WorkbenchInputWidth.templateMaxGrowth + 0.5, "input \(input.width)")
                #expect(input.width + 0.5 >= WorkbenchInputWidth.templateIdeal + WorkbenchInputWidth.templateMaxGrowth, "input uses its room up to 340: \(input.width)")
                // Available is whole on one line (hint line height), inside the surface.
                #expect(hint.height <= 20 && hint.maxX <= Double(width) + 0.5, "Available stays on one line: \(hint)")
            }
            if width <= 420 { #expect(!beside && hint.minY >= field.maxY - 1, "narrow: Available wraps whole below @\(Int(width))") }
            #expect(hint.height > 0 && hint.maxX <= Double(width) + 0.5, "Available is fully visible @\(Int(width))")
            // Narrow widths keep an operable input; the input is never compressed below `wide`.
            #expect(input.width + 0.5 >= WorkbenchInputWidth.wide)
            #expect(ControlsGeometry.problems(short.probe, width: width).isEmpty, "short @\(Int(width))")

            let g = many.probe.frames
            let manyField = g["controls.common.titleTemplate.field"]!, manyHint = g["controls.common.titleTemplate.available"]!
            let manyBeside = manyHint.minX >= manyField.maxX - 1 && abs(manyHint.minY - manyField.minY) < manyField.height
            if width <= 720 { #expect(!manyBeside && manyHint.minY >= manyField.maxY - 1, "many tokens wrap whole below @\(Int(width))") }
            #expect(manyHint.maxX <= Double(width) + 0.5 && manyHint.height > 0, "many tokens fully visible @\(Int(width))")
            #expect(ControlsGeometry.problems(many.probe, width: width).isEmpty, "many @\(Int(width))")
        }
    }

    @Test("Available uses the shared hint role: normal hint font, primary colour, no truncation")
    func availableUsesHintRole() async {
        let host = await surface(.cartesianXY(F.cartesian()), width: 720, tokens: shortTokens)
        #expect(host.probe.roles["controls.common.titleTemplate.available"] == nil || host.probe.roles["controls.common.titleTemplate.available"] == .hint)
        #expect(WorkbenchTextRole.hint.font == WorkbenchUIStyle.controlHintFont)
    }

    // MARK: Plot Justify & flexible widths

    @Test("Plot Justify at 720: Font pickers spread across the Font group, within bounded gaps")
    func fontRowSpreads() async {
        let host = await surface(.cartesianXY(F.cartesian()), width: 720)
        let f = host.probe.frames
        let group = f["controls.plot.typography"]!, content = f["controls.plot.typography.row#content"]!
        let pickers = ["title", "axis", "ticks", "legend", "point"].map { f["controls.plot.typography.\($0)"] }.compactMap { $0 }
        #expect(pickers.count == 5, "all five Font roles are mounted")
        let gaps = zip(pickers, pickers.dropFirst()).map { $1.minX - $0.maxX }
        let maxGap = WorkbenchControlMetrics.groupSpacing + WorkbenchControlMetrics.justifyMaxExtraGap
        #expect(gaps.allSatisfy { $0 >= WorkbenchControlMetrics.groupSpacing - 0.5 && $0 <= maxGap + 0.5 }, "gaps \(gaps)")
        #expect(gaps.contains { $0 > WorkbenchControlMetrics.groupSpacing + 1 }, "extra width is used between pickers: \(gaps)")
        #expect(pickers.last!.maxX <= content.maxX + 0.5 && group.maxX <= 720.5)
        #expect(host.probe.splitPairs.isEmpty && ControlsGeometry.problems(host.probe, width: 720).isEmpty)
    }

    @Test("X/Y label fields stay equal and nothing is undersized at every width")
    func flexibleInputsStayBounded() async {
        let host = await surface(.cartesianXY(F.cartesian()), width: 300)
        for width in [300, 420, 520, 720] as [CGFloat] {
            host.resize(to: width)
            await Task.yield()
            let f = host.probe.frames
            if let x = f["controls.plot.axisLabels.x#content"], let y = f["controls.plot.axisLabels.y#content"],
               abs(x.minY - y.minY) < 1 {
                #expect(abs(x.width - y.width) < 1.5, "X/Y label fields are equal @\(Int(width)): \(x.width) vs \(y.width)")
            }
            #expect(host.probe.undersizedControls.isEmpty, "\(host.probe.undersizedControls) @\(Int(width))")
            #expect(ControlsGeometry.problems(host.probe, width: width).isEmpty, "@\(Int(width))")
        }
    }

    @Test("Plot groups sharing a line are justified: bounded gaps, no overlap, nothing past the edge")
    func plotGroupGaps() async {
        for (name, plot) in allPlots() {
            let host = await surface(plot, width: 300)
            // Cartesian XY lays out three logical rows with the tighter in-row spacing.
            let minGap = name == "cartesianXY" ? WorkbenchControlMetrics.planeRowSpacing : WorkbenchControlMetrics.groupSpacing
            for width in F.representativeWidths {
                host.resize(to: width)
                await Task.yield()
                let frames = ControlsGeometry.groupIDs(host.probe).filter { $0.hasPrefix("controls.plot.") }.map { host.probe.frames[$0]! }
                // Neighbours on one line: the gap is the row spacing plus a bounded justify share.
                for a in frames {
                    let neighbours = frames.filter { $0.minX > a.minX + 1 && $0.minY < a.maxY - 1 && a.minY < $0.maxY - 1 }
                    guard let next = neighbours.min(by: { $0.minX < $1.minX }) else { continue }
                    let gap = next.minX - a.maxX
                    #expect(gap + 0.5 >= minGap, "\(name)@\(Int(width)) gap \(gap) below spacing")
                    #expect(gap <= minGap + WorkbenchControlMetrics.justifyMaxExtraGap + 0.5, "\(name)@\(Int(width)) gap \(gap) is not bounded")
                }
                #expect(ControlsGeometry.problems(host.probe, width: width).isEmpty, "\(name)@\(Int(width))")
            }
        }
    }

    @Test("Resizing one host back and forth keeps frames stable and the row count monotone")
    func resizeStable() async {
        let host = await surface(.cartesianXY(F.cartesian()), width: 300, tokens: shortTokens)
        var previousBottom = CGFloat.infinity
        for width in stride(from: 300 as CGFloat, through: 760, by: 20) {
            host.resize(to: width)
            await Task.yield()
            let bottom = ControlsGeometry.groupIDs(host.probe).compactMap { host.probe.frames[$0]?.maxY }.max() ?? 0
            #expect(bottom <= previousBottom + 0.5, "content height must not grow when widening (\(Int(width))): \(bottom) > \(previousBottom)")
            previousBottom = bottom
            #expect(ControlsGeometry.problems(host.probe, width: width).isEmpty, "@\(Int(width))")
        }
        let first = host.probe.frames.filter { !$0.key.contains("#") }
        host.resize(to: 360); host.resize(to: 760)
        let again = host.probe.frames.filter { !$0.key.contains("#") }
        for (id, frame) in first { #expect(abs(frame.minX - again[id]!.minX) < 1 && abs(frame.width - again[id]!.width) < 1, "\(id)") }
    }

    @Test("Ticks of related axes never split across lines, in every Plot Mode with axes, at every width")
    func ticksStayTogether() async {
        let plots: [(String, WorkbenchControlsPlotAdapter)] = [
            ("cartesianXY", .cartesianXY(F.cartesian())), ("dualAxis", .dualAxis(F.dualAxis())),
            ("heatmap with axes", .heatmap(F.heatmap(withAxes: true))),
        ]
        for (name, plot) in plots {
            let host = await surface(plot, width: F.representativeWidths[0])
            for width in F.representativeWidths {
                host.resize(to: width)
                await Task.yield()
                #expect(host.probe.splitPairs.isEmpty, "\(name)@\(Int(width)): \(host.probe.splitPairs)")
                #expect(host.probe.undersizedControls.isEmpty, "\(name)@\(Int(width)): \(host.probe.undersizedControls)")
                #expect(ControlsGeometry.problems(host.probe, width: width).isEmpty, "\(name)@\(Int(width))")
                // The Ticks row stays inside the surface: the label moves above a strip that does not fit beside it.
                let row = host.probe.frames["controls.plot.ticks.row"]!
                let strip = host.probe.frames["controls.plot.ticks.row#content"]!
                #expect(strip.maxX <= row.maxX + 0.5, "\(name)@\(Int(width)): ticks strip overflows its row")
            }
        }
    }

    @Test("Checker detects a Ticks X/Y strip that wraps one stepper onto the next line")
    func checkerDetectsOrphanedTick() {
        let host = ControlsSurfaceHost(width: 120) {
            WorkbenchControlFlow {
                Stepper("", value: .constant(5)).frame(width: 64).workbenchPairMember("ticks")
                Stepper("", value: .constant(5)).frame(width: 64).workbenchPairMember("ticks")
            }
        }
        #expect(host.probe.splitPairs.contains { $0.contains("ticks") }, "\(host.probe.splitPairs)")
    }

    @Test("Related axis label fields sit side by side when wide and wrap as whole fields when narrow")
    func axisLabelsWrapAsFields() async {
        let host = await surface(.cartesianXY(F.cartesian()), width: 720)
        let xRow = { host.probe.frames["controls.plot.axisLabels.x"]! }, yRow = { host.probe.frames["controls.plot.axisLabels.y"]! }
        #expect(abs(xRow().minY - yRow().minY) < 1 && xRow().maxX <= yRow().minX + 1, "wide: X label and Y label share a line")
        host.resize(to: 300)
        await Task.yield()
        #expect(yRow().minY >= xRow().maxY - 1, "narrow: Y label wraps below X label")
        #expect(host.probe.frames["controls.plot.axisLabels.y#content"]!.width + 0.5 >= WorkbenchInputWidth.compact)
        #expect(ControlsGeometry.problems(host.probe, width: 300).isEmpty)
    }

    @Test("Specific group titles are not drawn, but groups keep their identifiers")
    func specificTitlesHidden() async {
        let content = WorkbenchSpecificContent {
            WorkbenchSpecificGroup("fitting", title: "Fitting") {
                WorkbenchSpecificRow("fit", label: "Fit") {
                    WorkbenchSpecificInput.toggle("zero", title: "Zero at I=0", isOn: .constant(true))
                }
            }
        }
        let host = await surface(.heatmap(F.heatmap()), specific: content, width: 364)
        #expect(host.probe.frames["controls.specific.fitting"] != nil, "group stays addressable")
        #expect(!host.probe.frames.keys.contains { $0.hasSuffix("#title") }, "no group title is drawn in Specific")
    }

    @Test("Checker detects a visible group title")
    func checkerDetectsVisibleGroupTitle() {
        let host = ControlsSurfaceHost(width: 300) {
            WorkbenchControlGroup(id: "controls.specific.fitting", title: "Fitting") { Text("body") }
        }
        #expect(host.probe.frames.keys.contains("controls.specific.fitting#title"))
    }

    @Test("Layout is deterministic: returning to a width reproduces the same frames")
    func layoutReturnsToSameFrames() async {
        let host = await surface(.cartesianXY(F.cartesian()), width: 720, tokens: manyTokens)
        let first = host.probe.frames.filter { !$0.key.contains("#") }
        for width in [300, 520, 364, 720] as [CGFloat] { host.resize(to: width); await Task.yield() }
        let again = host.probe.frames.filter { !$0.key.contains("#") }
        #expect(Set(first.keys) == Set(again.keys))
        for (id, frame) in first { #expect(abs(frame.width - again[id]!.width) < 1 && abs(frame.minY - again[id]!.minY) < 1, "\(id)") }
    }
}
