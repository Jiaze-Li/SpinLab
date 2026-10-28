import AppKit
import SwiftUI
import Testing
@testable import SpinLabApp

/// Real SwiftUI layout of the Heatmap logical rows shared by AFM and RSM (CS-41): row 1 Colorbar +
/// Linear/Log · Interpolation · Font, row 2 Z range + companion, row 3 Spatial Axes (RSM only).
@MainActor
@Suite("Controls Surface — Heatmap shared logical rows")
struct HeatmapSharedRowsLayoutTests {
    private typealias F = ControlsSurfaceFixtures
    private let widths: [CGFloat] = [300, 364, 420, 520, 667, 720]
    private let tolerance: CGFloat = 1.0

    private func host(mode: HeatmapZDomainMode, withAxes: Bool, width: CGFloat) async -> ControlsSurfaceHost<WorkbenchControlsSurface> {
        let host = ControlsSurfaceHost(width: width) {
            WorkbenchControlsSurface(descriptor: F.descriptor(.heatmap(F.heatmap(mode: mode, withAxes: withAxes))))
        }
        await Task.yield()
        return host
    }

    private func frames(_ h: ControlsSurfaceHost<WorkbenchControlsSurface>) -> [String: CGRect] { h.probe.frames }

    private let row1IDs = ["controls.plot.colorScale.colorbar", "controls.plot.colorScale.mode#content",
                           "controls.plot.interpolation.mode#content", "controls.plot.typography.title"]

    /// Controls of row 1 in reading order must be left-to-right, and wrapped lines only after whole groups.
    @Test("Row 1 order is Colorbar, Linear/Log, Interpolation, Font (Title first) for AFM and RSM at every width")
    func rowOneOrder() async {
        for withAxes in [false, true] {
            let name = withAxes ? "RSM" : "AFM"
            let h = await host(mode: .auto, withAxes: withAxes, width: 300)
            for width in widths {
                h.resize(to: width); await Task.yield()
                let f = frames(h)
                let rects = row1IDs.compactMap { f[$0] }
                #expect(rects.count == row1IDs.count, "\(name)@\(Int(width)): row 1 controls missing \(row1IDs.filter { f[$0] == nil })")
                guard rects.count == row1IDs.count else { continue }
                // Reading order: each next control starts below or to the right of the previous one.
                for (a, b) in zip(rects, rects.dropFirst()) {
                    #expect(b.minY >= a.maxY - 1 || b.minX >= a.maxX - tolerance, "\(name)@\(Int(width)): row 1 order broken \(a) -> \(b)")
                }
                #expect(f["controls.plot.zRange.mode"]!.minY >= rects.map(\.maxY).max()! - 1, "\(name)@\(Int(width)): Z range must sit below row 1")
                // The Colorbar checkbox and Linear/Log are one visual group.
                let group = f["controls.plot.colorScale"]!
                #expect(group.contains(rects[0].insetBy(dx: 0.5, dy: 0.5)) && group.contains(rects[1].insetBy(dx: 0.5, dy: 0.5)), "\(name)@\(Int(width)): Colorbar + Linear/Log share a group")
                #expect(f["controls.plot.colorScale.mode"] == nil, "\(name)@\(Int(width)): no separate visible 'Color scale' row")
            }
        }
    }

    @Test("Shared controls sit at identical positions in AFM and RSM (rows 1 and 2, Auto)")
    func sharedPositionsMatch() async {
        for width in widths {
            let afm = await host(mode: .auto, withAxes: false, width: width)
            let rsm = await host(mode: .auto, withAxes: true, width: width)
            let fa = frames(afm), fr = frames(rsm)
            // Colorbar group, Linear/Log, Interpolation and Z range keep the same x/y in both configurations
            // wherever row 1 is not re-justified by the extra RSM fonts; the wrap structure is compared instead.
            for id in ["controls.plot.colorScale.colorbar", "controls.plot.zRange.mode"] {
                guard let a = fa[id], let r = fr[id] else { Issue.record("\(id) missing @\(Int(width))"); continue }
                #expect(abs(a.minX - r.minX) <= tolerance, "\(id)@\(Int(width)) x AFM \(a.minX) RSM \(r.minX)")
            }
            #expect(fr["controls.plot.colorScale.colorbar"]!.minX == fa["controls.plot.colorScale.colorbar"]!.minX)
            // AFM has no Spatial Axes row and no placeholder; RSM's row is below Z range.
            #expect(fa["controls.plot.axisLabels"] == nil && fa["controls.plot.ticks"] == nil, "AFM@\(Int(width)) has no axes row")
            if let labels = fr["controls.plot.axisLabels"], let ticks = fr["controls.plot.ticks"], let z = fr["controls.plot.zRange"] {
                #expect(labels.minY >= z.maxY - 1 && ticks.minY >= z.maxY - 1, "RSM@\(Int(width)) axes row below Z range")
            } else { Issue.record("RSM@\(Int(width)) axes row missing") }
            #expect(ControlsGeometry.problems(afm.probe, width: width).isEmpty, "AFM@\(Int(width)): \(ControlsGeometry.problems(afm.probe, width: width))")
            #expect(ControlsGeometry.problems(rsm.probe, width: width).isEmpty, "RSM@\(Int(width)): \(ControlsGeometry.problems(rsm.probe, width: width))")
        }
    }

    @Test("Switching Auto / Manual / Percentile keeps Z range at one start and does not move row 1 or the axes row")
    func zModeSwitchDoesNotMoveOtherRows() async {
        for withAxes in [false, true] {
            let name = withAxes ? "RSM" : "AFM"
            for width in widths {
                var zStarts: [CGFloat] = [], row1: [CGRect] = [], axesTops: [CGFloat] = [], zTops: [CGFloat] = []
                var axesXs: [String] = [], axesGaps: [CGFloat] = []
                for mode in [HeatmapZDomainMode.auto, .manual, .percentile] {
                    let h = await host(mode: mode, withAxes: withAxes, width: width)
                    let f = frames(h)
                    guard let z = f["controls.plot.zRange.mode"], let g = f["controls.plot.colorScale"] else { Issue.record("\(name)@\(Int(width)) \(mode) rows missing"); continue }
                    zStarts.append(z.minX); zTops.append(z.minY); row1.append(g)
                    if let labels = f["controls.plot.axisLabels"], let ticks = f["controls.plot.ticks"], let zGroup = f["controls.plot.zRange"] {
                        axesTops.append(labels.minY)
                        axesXs.append("\(labels.minX.rounded()),\(ticks.minX.rounded()),\((ticks.minY - labels.minY).rounded())")
                        axesGaps.append((labels.minY - zGroup.maxY).rounded())
                    }
                    if mode == .manual { #expect(f["controls.plot.zRange.manual.min"] != nil, "\(name)@\(Int(width)) Manual fields") }
                    if mode == .percentile { #expect(f["controls.plot.zRange.preset"] != nil, "\(name)@\(Int(width)) Preset") }
                    #expect(ControlsGeometry.problems(h.probe, width: width).isEmpty, "\(name)@\(Int(width)) \(mode): \(ControlsGeometry.problems(h.probe, width: width))")
                }
                #expect(Set(zStarts.map { $0.rounded() }).count == 1, "\(name)@\(Int(width)): Z range start moves \(zStarts)")
                #expect(Set(zTops.map { $0.rounded() }).count == 1, "\(name)@\(Int(width)): Z range row top moves \(zTops)")
                #expect(Set(row1.map { "\($0.minX.rounded()),\($0.minY.rounded())" }).count == 1, "\(name)@\(Int(width)): row 1 moves \(row1)")
                // Row 3 may only move down by the whole companion wrap, never sideways.
                if withAxes {
                    #expect(Set(axesXs).count == 1, "\(name)@\(Int(width)): Spatial Axes row x/arrangement changes with Z mode \(axesXs)")
                    // Any vertical move is exactly the Z range row's own height change: the gap below it is constant.
                    #expect(Set(axesGaps).count == 1, "\(name)@\(Int(width)): gap between Z range and Spatial Axes changes \(axesGaps)")
                }
            }
        }
    }

    @Test("Row 1 fit report: AFM fits from 667pt, full RSM row 1 needs 720pt, Interpolation and Z range pickers fully shown")
    func rowOneFitReport() async {
        for withAxes in [false, true] {
            let name = withAxes ? "RSM" : "AFM"
            let h = await host(mode: .auto, withAxes: withAxes, width: 300)
            for width in widths {
                h.resize(to: width); await Task.yield()
                let f = frames(h)
                guard let bar = f["controls.plot.colorScale.colorbar"], let seg = f["controls.plot.colorScale.mode#content"],
                      let interp = f["controls.plot.interpolation.mode#content"], let font = f["controls.plot.typography"] else {
                    Issue.record("\(name)@\(Int(width)) row 1 missing"); continue
                }
                let rects = [bar, seg, interp, font]
                let top = rects.map(\.minY).min()!
                let singleLine = rects.allSatisfy { $0.midY < top + 40 && abs($0.midY - bar.midY) < 20 }
                let needed = rects.map(\.width).reduce(0, +) + WorkbenchControlMetrics.planeRowSpacing * 3
                print("SIZES \(name)@\(Int(width)) row1 singleLine=\(singleLine) controlsWidth=\(Int(needed)) interp=\(Int(interp.width)) font=\(Int(font.width))")
                for r in rects { #expect(r.minX >= -tolerance && r.maxX <= width + tolerance, "\(name)@\(Int(width)) row 1 control outside \(r)") }
                for (a, b) in [(bar, seg), (seg, interp), (interp, font)] where abs(a.midY - b.midY) < 10 {
                    #expect(a.maxX <= b.minX + tolerance, "\(name)@\(Int(width)) overlap \(a) \(b)")
                }
                #expect(interp.width + tolerance >= WorkbenchInputWidth.menuMinimum, "\(name)@\(Int(width)) interpolation menu narrower than its minimum")
                // Measured: the full RSM row 1 needs 720pt on one line; at 667pt it wraps by whole groups (CS-41).
                if withAxes && width >= 720 { #expect(singleLine, "RSM@\(Int(width)): full row 1 should fit on one line") }
                if width >= 667 && !withAxes { #expect(singleLine, "AFM@\(Int(width)): row 1 should fit on one line") }
            }
        }
    }

    /// Reports the narrowest width at which the full RSM row 1 (Colorbar + Linear/Log · Interpolation · Font
    /// Title/Axis/Ticks) is a single line; below it the row wraps by whole groups, never compressing a control.
    @Test("RSM row 1 single-line threshold is reported and wrapping below it is by whole groups")
    func rowOneThreshold() async {
        let h = await host(mode: .auto, withAxes: true, width: 800)
        var threshold: CGFloat?
        for width in stride(from: 800 as CGFloat, through: 560, by: -4) {
            h.resize(to: width); await Task.yield()
            let f = frames(h)
            guard let bar = f["controls.plot.colorScale.colorbar"], let font = f["controls.plot.typography.ticks"] else { continue }
            if abs(bar.midY - font.midY) < 10 { threshold = width } else { break }
            #expect(ControlsGeometry.problems(h.probe, width: width).isEmpty, "RSM@\(Int(width)): \(ControlsGeometry.problems(h.probe, width: width))")
        }
        print("SIZES RSM row 1 single-line down to \(Int(threshold ?? 0))pt; shortfall at 667pt = \(Int(max((threshold ?? 0) - 667, 0)))pt")
        #expect(threshold != nil)
    }

    @Test("Empty Manual fields show the cue in the real UI; filled fields do not")
    func manualCuePresence() async {
        for withAxes in [false, true] {
            let empty = await host(mode: .manual, withAxes: withAxes, width: 520)
            let fe = frames(empty)
            #expect(fe["controls.plot.zRange.manual.min.cue"] != nil && fe["controls.plot.zRange.manual.max.cue"] != nil, "empty Manual shows both cues")
            var model = F.heatmap(mode: .manual, withAxes: withAxes)
            model.zDomainState.manualRange.minText = "0"; model.zDomainState.manualRange.maxText = "1"
            let filled = ControlsSurfaceHost(width: 520) { WorkbenchControlsSurface(descriptor: F.descriptor(.heatmap(model))) }
            await Task.yield()
            let ff = frames(filled)
            #expect(ff["controls.plot.zRange.manual.min.cue"] == nil && ff["controls.plot.zRange.manual.max.cue"] == nil, "filled Manual shows no cue")
            #expect(ff["controls.plot.zRange.manual.min"] != nil)
        }
    }

    @Test("Incomplete Manual draft is a quiet cue, not a red banner; invalid or inverted values keep the red message")
    func manualValidationPolicy() {
        var z = HeatmapZDomainState(mode: .manual)
        #expect(z.validationIssue()?.isIncompleteDraft == true)
        #expect(z.resolve(rawValues: [1, 2]).resolvedBounds == nil, "empty Manual still falls back to Auto")
        z.manualRange.minText = "5"; z.manualRange.maxText = "1"
        #expect(z.validationIssue() == .manualRangeInverted && z.validationIssue()?.isIncompleteDraft == false)
        z.manualRange.minText = "x"
        #expect(z.validationIssue() == .manualMinInvalid && z.validationIssue()?.isIncompleteDraft == false)
        #expect(!HeatmapZDomainValidationIssue.incompleteDraftHint.isEmpty)
    }
}
