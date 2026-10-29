import AppKit
import SwiftUI
import Testing
@testable import SpinLabApp

/// Real SwiftUI layout checks for the Heatmap content-fit menus and the DualAxis Left / Right
/// repeated-row alignment. Also records the real control sizes each assertion saw.
@MainActor
@Suite("Controls Surface — compact menus and repeated-row alignment")
struct ControlsRepeatedRowAndCompactMenuTests {
    private typealias F = ControlsSurfaceFixtures
    private let tolerance: CGFloat = 1.0

    private func host(_ plot: WorkbenchControlsPlotAdapter, width: CGFloat) async -> ControlsSurfaceHost<WorkbenchControlsSurface> {
        let host = ControlsSurfaceHost(width: width) { WorkbenchControlsSurface(descriptor: F.descriptor(plot)) }
        await Task.yield()
        return host
    }

    // MARK: Heatmap

    /// What a real SwiftUI menu Picker needs for `titles` in an environment, measured on its own
    /// (no production sizing code involved). A Picker sizes to its widest option, whatever is selected.
    private struct IntrinsicPicker<Env: ViewModifier>: View {
        let titles: [String]
        let env: Env
        @State var selection = 0
        var body: some View {
            Picker("", selection: $selection) { ForEach(titles.indices, id: \.self) { Text(titles[$0]).tag($0) } }
                .labelsHidden().pickerStyle(.menu).fixedSize().modifier(env)
        }
    }
    private struct Plain: ViewModifier { func body(content: Content) -> some View { content } }

    private func intrinsicWidth<E: ViewModifier>(_ titles: [String], env: E = Plain()) -> CGFloat {
        NSHostingView(rootView: IntrinsicPicker(titles: titles, env: env)).fittingSize.width
    }

    @Test("Heatmap menus: exactly the Picker's own width (never narrower), stable across selections, no overflow")
    func heatmapContentFitMenus() async {
        let interpTitles = HeatmapInterpolationMode.menuOptions.map(\.controlTitle)
        let presetTitles = HeatmapPercentilePreset.visiblePresets.map(\.menuTitle)
        let expectedInterp = intrinsicWidth(interpTitles)
        let expectedPreset = intrinsicWidth(presetTitles)
        for title in interpTitles { #expect(intrinsicWidth([title]) <= expectedInterp + 0.5, "\(title)") }
        for title in presetTitles { #expect(intrinsicWidth([title]) <= expectedPreset + 0.5, "\(title)") }
        #expect(expectedInterp >= WorkbenchInputWidth.menuMinimum && expectedPreset >= WorkbenchInputWidth.menuMinimum)

        for withAxes in [false, true] {
            for mode in [HeatmapZDomainMode.auto, .manual, .percentile] {
                var interpWidths: [CGFloat] = []
                var presetWidths: [CGFloat] = []
                for interpolation in HeatmapInterpolationMode.menuOptions {
                    let name = "\(withAxes ? "RSM" : "AFM")/\(mode)/\(interpolation)"
                    let h = await host(.heatmap(F.heatmap(mode: mode, withAxes: withAxes, interpolation: interpolation)), width: 300)
                    for width in [300, 364, 520, 720] as [CGFloat] {
                        h.resize(to: width)
                        await Task.yield()
                        let problems = ControlsGeometry.problems(h.probe, width: width)
                        #expect(problems.isEmpty, "\(name)@\(Int(width)): \(problems)")
                        let frames = h.probe.frames
                        guard let interp = frames["controls.plot.interpolation.mode#content"], let zMode = frames["controls.plot.zRange.mode"] else {
                            Issue.record("\(name)@\(Int(width)): rows missing"); continue
                        }
                        #expect(interp.width + tolerance >= expectedInterp && interp.width <= expectedInterp + tolerance, "\(name)@\(Int(width)) interpolation \(interp.width) vs \(expectedInterp)")
                        interpWidths.append(interp.width)
                        let preset = frames["controls.plot.zRange.preset"]
                        let presetContent = frames["controls.plot.zRange.preset#content"]
                        if mode == .percentile {
                            guard let preset, let presetContent else { Issue.record("\(name)@\(Int(width)): Preset missing"); continue }
                            #expect(presetContent.width + tolerance >= expectedPreset && presetContent.width <= expectedPreset + tolerance, "\(name)@\(Int(width)) preset \(presetContent.width) vs \(expectedPreset)")
                            presetWidths.append(presetContent.width)
                            let sameLine = preset.minY < zMode.maxY - 1 && zMode.minY < preset.maxY - 1
                            if width >= 520 { #expect(sameLine, "\(name)@\(Int(width)): Preset should share Z range's line (\(zMode) vs \(preset))") }
                            #expect(sameLine ? preset.minX >= zMode.maxX - tolerance : preset.minY >= zMode.maxY - tolerance)
                        } else {
                            #expect(preset == nil, "\(name)@\(Int(width)): Preset must not exist outside Percentile")
                        }
                        print("SIZES \(name)@\(Int(width)) interpolation=\(Int(interp.width))" + (presetContent.map { " preset=\(Int($0.width))" } ?? "")
                              + " zMode=\(Int(zMode.width))x\(Int(zMode.height))")
                    }
                }
                #expect(Set(interpWidths.map { $0.rounded() }).count == 1, "interpolation width jumps with selection: \(interpWidths)")
                #expect(Set(presetWidths.map { $0.rounded() }).count <= 1, "preset width varies: \(presetWidths)")
            }
        }
        print("SIZES intrinsic interpolation=\(expectedInterp) preset=\(expectedPreset)")
    }

    @Test("Regression: the production Picker is never narrower than its own intrinsic width in any environment (clipped to 'N…' / '0…' otherwise)")
    func productionPickerNeverNarrowerThanIntrinsic() {
        struct Production<Env: ViewModifier>: View {
            let titles: [String]
            let env: Env
            @State var selection = 0
            var body: some View {
                Picker("", selection: $selection) { ForEach(titles.indices, id: \.self) { Text(titles[$0]).tag($0) } }
                    .labelsHidden().pickerStyle(.menu).workbenchContentFitMenu().workbenchControl(.menu).modifier(env)
            }
        }
        struct Bold: ViewModifier { func body(content: Content) -> some View { content.environment(\.legibilityWeight, .bold) } }
        struct NoIndicator: ViewModifier { func body(content: Content) -> some View { content.menuIndicator(.hidden) } }
        struct Large: ViewModifier { func body(content: Content) -> some View { content.controlSize(.large) } }
        struct Big: ViewModifier { func body(content: Content) -> some View { content.font(.title) } }
        func check<E: ViewModifier>(_ name: String, _ env: E) {
            for titles in [HeatmapInterpolationMode.menuOptions.map(\.controlTitle), HeatmapPercentilePreset.visiblePresets.map(\.menuTitle)] {
                let need = intrinsicWidth(titles, env: env)
                let got = NSHostingView(rootView: Production(titles: titles, env: env)).fittingSize.width
                #expect(got + 0.5 >= need, "\(name) \(titles): production \(got) < intrinsic \(need)")
                print("SIZES regression \(name) \(titles.first ?? ""): intrinsic=\(need) production=\(got)")
            }
        }
        check("plain", Plain()); check("boldText", Bold()); check("noIndicator", NoIndicator()); check("large", Large()); check("title", Big())
    }

    @Test("Heatmap display text is abbreviated; full name kept for tooltip; stored value unchanged")
    func heatmapTitles() {
        #expect(HeatmapInterpolationMode.logSpaceGaussian1p5x.controlTitle == "Log-Gauss 1.5×")
        #expect(HeatmapInterpolationMode.logSpaceGaussian1p5x.fullName == "Log-Space Gaussian 1.5×")
        #expect(HeatmapInterpolationMode.logSpaceGaussian1p5x.rawValue == "logSpaceGaussian1p5x")
        #expect(HeatmapInterpolationMode.nearest.rawValue == "nearest")
    }

    @Test("Preset menu text is a separate compact range; displayTitle and clamp values are untouched")
    func presetMenuTitles() {
        #expect(HeatmapPercentilePreset.visiblePresets.map(\.menuTitle) == ["0.5%–99.5%", "1%–99%", "2%–98%", "5%–95%", "5%–99%"])
        #expect(HeatmapPercentilePreset.p0_5_99_5.displayTitle == "0.5% - 99.5%")
        #expect(HeatmapPercentilePreset.p0_5_99_5.clamp == HeatmapPercentileClamp(lowerPercent: 0.5, upperPercent: 99.5))
    }

    @Test("Manual Z range: Min / Max [min] – [max] on one line inside the row, independent accessibility labels")
    func manualZRangeLayout() async {
        for withAxes in [false, true] {
            let name = withAxes ? "RSM" : "AFM"
            let manual = await host(.heatmap(F.heatmap(mode: .manual, withAxes: withAxes)), width: 364)
            let auto = await host(.heatmap(F.heatmap(mode: .auto, withAxes: withAxes)), width: 364)
            for width in [300, 364, 520, 720] as [CGFloat] {
                manual.resize(to: width); auto.resize(to: width)
                await Task.yield()
                let problems = ControlsGeometry.problems(manual.probe, width: width)
                #expect(problems.isEmpty, "\(name)@\(Int(width)): \(problems)")
                let frames = manual.probe.frames
                guard let a = frames["controls.plot.zRange.manual.min"], let dash = frames["controls.plot.zRange.manual.dash"],
                      let b = frames["controls.plot.zRange.manual.max"], let row = frames["controls.plot.zRange.manual"] else {
                    Issue.record("\(name)@\(Int(width)): Manual fields missing"); continue
                }
                #expect(abs(a.midY - b.midY) <= 2 && abs(a.midY - dash.midY) <= 6, "\(name)@\(Int(width)): fields and dash share a line")
                #expect(a.maxX <= dash.minX + tolerance && dash.maxX <= b.minX + tolerance, "\(name)@\(Int(width)): order min – max")
                #expect(a.width + 0.5 >= WorkbenchInputWidth.compact && b.width + 0.5 >= WorkbenchInputWidth.compact)
                #expect(row.contains(a.insetBy(dx: 0.5, dy: 0.5)) && row.contains(b.insetBy(dx: 0.5, dy: 0.5)), "\(name)@\(Int(width)): fields inside the row")
                print("SIZES \(name)@\(Int(width)) manual min=\(Int(a.width)) max=\(Int(b.width)) dash=\(Int(dash.width))")
            }
        }
        // The off-screen host exposes no accessibility tree, so the labels are checked at their
        // single source of truth, which the view applies to each field.
        #expect(HeatmapZRangeAccessibility.minimum == "Z minimum")
        #expect(HeatmapZRangeAccessibility.maximum == "Z maximum")
        #expect(HeatmapZRangeAccessibility.minimum != HeatmapZRangeAccessibility.maximum)
    }

    @Test("DualAxis menu tokens cover their longest option")
    func seriesTokensFitText() {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        let chrome: CGFloat = 28
        let choices = ["Solid", "Dashed", "Circle", "Square", "Filled", "Open"].map(width).max() ?? 0
        #expect(choices + chrome <= WorkbenchInputWidth.seriesChoiceMenu, "longest choice \(choices)")
        let presets = ["1", "1.5", "2.5", "6"].map(width).max() ?? 0
        #expect(presets + chrome <= WorkbenchInputWidth.seriesPresetMenu)
    }

    // MARK: DualAxis

    private static let columns = ["line", "w", "marker", "size", "fill"]

    private func dualAxisStates() -> [(String, DualAxisDisplayState)] {
        var varied = DualAxisDisplayState()
        varied.rightSeriesStyle.linePattern = .dashed
        varied.rightSeriesStyle.markerShape = .square
        varied.rightSeriesStyle.markerFill = .open
        varied.rightSeriesStyle.lineWidth = 5
        varied.leftSeriesStyle.pointRadius = 6
        return [("default", DualAxisDisplayState()), ("varied", varied)]
    }

    @Test("DualAxis Left/Right: five columns share X edges and widths at every width, whatever is selected")
    func dualAxisRowsAlign() async {
        var reference: [String: CGRect]?
        for (stateName, state) in dualAxisStates() {
            let h = await host(.dualAxis(F.dualAxis(state: state)), width: 420)
            for width in [420, 520, 667, 720] as [CGFloat] {
                h.resize(to: width)
                await Task.yield()
                let name = "\(stateName)@\(Int(width))"
                let problems = ControlsGeometry.problems(h.probe, width: width)
                #expect(problems.isEmpty, "\(name): \(problems)")
                let frames = h.probe.frames
                let base = "controls.plot.seriesAppearance"
                guard let leftLabel = frames["\(base).left.label"], let rightLabel = frames["\(base).right.label"] else {
                    Issue.record("\(name): row labels missing"); continue
                }
                #expect(abs(leftLabel.minX - rightLabel.minX) <= tolerance, "\(name): row labels")
                if let firstLeft = frames["controls.plot.seriesAppearance.left.line"], let firstRight = frames["controls.plot.seriesAppearance.right.line"] {
                    #expect(abs(leftLabel.midY - firstLeft.midY) <= 6, "\(name): Left label beside the first Left row")
                    #expect(abs(rightLabel.midY - firstRight.midY) <= 6, "\(name): Right label beside the first Right row")
                }
                var line: [String] = []
                for column in Self.columns {
                    guard let l = frames["\(base).left.\(column)"], let r = frames["\(base).right.\(column)"] else {
                        Issue.record("\(name): \(column) missing"); continue
                    }
                    #expect(abs(l.minX - r.minX) <= tolerance, "\(name) \(column): left x \(l.minX) vs right x \(r.minX)")
                    #expect(abs(l.width - r.width) <= tolerance, "\(name) \(column): widths \(l.width) vs \(r.width)")
                    #expect(r.minY > l.minY, "\(name) \(column): Right sits below Left")
                    line.append("\(column)=\(Int(l.minX.rounded()))/\(Int(l.width.rounded()))")
                }
                // Positions must not depend on the current selection.
                if stateName == "default" {
                    reference = reference ?? [:]
                    for column in Self.columns { reference?["\(Int(width)).\(column)"] = frames["\(base).left.\(column)"] }
                } else if let reference {
                    for column in Self.columns {
                        if let was = reference["\(Int(width)).\(column)"], let now = frames["\(base).left.\(column)"] {
                            #expect(abs(was.minX - now.minX) <= tolerance && abs(was.width - now.width) <= tolerance, "\(name) \(column) moved with selection")
                        }
                    }
                }
                print("SIZES dualAxis \(name) label=\(Int(leftLabel.width)) \(line.joined(separator: " "))")
            }
        }
    }

    @Test("DualAxis rows keep both rows whole when narrow: no control below its minimum")
    func dualAxisNarrowWraps() async {
        let h = await host(.dualAxis(F.dualAxis()), width: 364)
        for width in [300, 364] as [CGFloat] {
            h.resize(to: width)
            await Task.yield()
            let problems = ControlsGeometry.problems(h.probe, width: width)
            #expect(problems.isEmpty, "@\(Int(width)): \(problems)")
            let base = "controls.plot.seriesAppearance"
            for column in Self.columns {
                if let l = h.probe.frames["\(base).left.\(column)"], let r = h.probe.frames["\(base).right.\(column)"] {
                    #expect(abs(l.minX - r.minX) <= tolerance, "@\(Int(width)) \(column) misaligned after wrapping")
                    #expect(l.maxX <= width + 0.5 && r.maxX <= width + 0.5)
                }
            }
        }
    }
}
