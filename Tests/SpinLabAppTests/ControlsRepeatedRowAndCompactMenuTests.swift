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

    @Test("Heatmap menus: content-fit width, no overflow, Preset beside Z range when it fits, in every mode")
    func heatmapCompactMenus() async {
        let modes: [HeatmapZDomainMode] = [.auto, .manual, .percentile]
        let interpolations: [HeatmapInterpolationMode] = [.nearest, .logSpaceGaussian1p5x]
        for withAxes in [false, true] {
            for mode in modes {
                for interpolation in interpolations {
                    let name = "\(withAxes ? "RSM" : "AFM")/\(mode)/\(interpolation)"
                    let h = await host(.heatmap(F.heatmap(mode: mode, withAxes: withAxes, interpolation: interpolation)), width: 364)
                    for width in [364, 520, 720] as [CGFloat] {
                        h.resize(to: width)
                        await Task.yield()
                        let problems = ControlsGeometry.problems(h.probe, width: width)
                        #expect(problems.isEmpty, "\(name)@\(Int(width)): \(problems)")
                        let frames = h.probe.frames
                        guard let interp = frames["controls.plot.interpolation.mode#content"],
                              let zMode = frames["controls.plot.zRange.mode"] else {
                            Issue.record("\(name)@\(Int(width)): rows missing"); continue
                        }
                        #expect(interp.width <= WorkbenchInputWidth.interpolationMenu + tolerance, "\(name)@\(Int(width)) interpolation \(interp.width)")
                        let preset = frames["controls.plot.zRange.preset"]
                        let presetContent = frames["controls.plot.zRange.preset#content"]
                        if mode == .percentile {
                            guard let preset, let presetContent else { Issue.record("\(name)@\(Int(width)): Preset missing"); continue }
                            #expect(presetContent.width <= WorkbenchInputWidth.percentilePresetMenu + tolerance, "\(name)@\(Int(width)) preset \(presetContent.width)")
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
            }
        }
    }

    @Test("Heatmap display text is abbreviated; full name kept in tooltip text; stored value unchanged")
    func heatmapTitles() {
        #expect(HeatmapInterpolationMode.logSpaceGaussian1p5x.controlTitle == "Log-Gauss 1.5×")
        #expect(HeatmapInterpolationMode.logSpaceGaussian1p5x.fullName == "Log-Space Gaussian 1.5×")
        #expect(HeatmapInterpolationMode.logSpaceGaussian1p5x.rawValue == "logSpaceGaussian1p5x")
        #expect(HeatmapInterpolationMode.nearest.rawValue == "nearest")
    }

    @Test("Menu widths cover their longest title")
    func menuTokensFitText() {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        let chrome: CGFloat = 28 // popup arrows + inset
        let longestPreset = HeatmapPercentilePreset.visiblePresets.map { width($0.displayTitle) }.max() ?? 0
        #expect(longestPreset + chrome <= WorkbenchInputWidth.percentilePresetMenu)
        let longestInterp = [HeatmapInterpolationMode.nearest, .logSpaceGaussian1p5x].map { width($0.controlTitle) }.max() ?? 0
        #expect(longestInterp + chrome <= WorkbenchInputWidth.interpolationMenu)
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
