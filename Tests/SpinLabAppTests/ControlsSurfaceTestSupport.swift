import AppKit
import SwiftUI
@testable import SpinLabApp

/// Shared fixtures for Controls Surface contract tests. Models are built from plain values so
/// the real shared components run in a real SwiftUI layout pass without any workflow store.
@MainActor
enum ControlsSurfaceFixtures {
    static let representativeWidths: [CGFloat] = [300, 364, 420, 520, 720]

    static func common(title: String = "Title", showTitle: Bool = true) -> WorkbenchCommonControlsModel {
        WorkbenchCommonControlsModel(
            showTitle: showTitle, titleOverride: "", renderedTitle: title, sourceResetToken: "t",
            globalPlotDefaults: .constant([:]),
            onShowTitleChange: { _ in }, onTitleOverride: { _ in }, onStyleChange: {})
    }

    static func cartesian(capabilities: CartesianXYCapabilities = []) -> CartesianXYControlsModel {
        CartesianXYControlsModel(
            capabilities: capabilities,
            titleTemplate: .constant("#tab"), numericDisplayCache: [:],
            stackOffset: .constant(0.5), minGapFraction: .constant(0.15), showGrid: .constant(true),
            seriesRenderMode: .constant(.line), globalPlotDefaults: .constant([:]),
            chartStyleOverrides: .constant([:]),
            series: CartesianXYSeriesControls(
                payload: nil, controlModel: nil, currentOrder: nil, hiddenKeys: [], labelOverrides: [:],
                canReorder: false, onOrderCommit: { _ in }, onVisibilityChange: { _, _ in }, onRenameLabel: { _, _ in }),
            xLabelOverride: "", yLabelOverride: "", renderedXLabel: "X", renderedYLabel: "Y",
            sourceResetToken: "t", onXLabelOverride: { _ in }, onYLabelOverride: { _ in },
            activeLayout: nil, axisRangeOverride: nil, onAxisBoundUpdate: { _, _ in }, onResetRanges: {},
            tickOverride: nil, onTickCountUpdate: { _, _ in }, onChange: {}, onTransientChange: {})
    }

    static func dualAxis() -> DualAxisControlsModel {
        DualAxisControlsModel(
            displayState: .constant(DualAxisDisplayState()), titleTemplate: .constant("#tab"),
            numericDisplayCache: [:], globalPlotDefaults: .constant([:]), chartStyleOverrides: .constant([:]),
            activeLayout: nil, sourceResetToken: "t", renderedXLabel: "T", renderedLeftYLabel: "L",
            renderedRightYLabel: "R", onDisplayStateChange: {}, onTransientChange: {}, onResetRanges: {})
    }

    static func heatmap(mode: HeatmapZDomainMode = .auto) -> HeatmapControlsModel {
        HeatmapControlsModel(
            colorScaleMode: .linear, interpolationMode: .nearest,
            zDomainState: HeatmapZDomainState(mode: mode), showColorbar: true,
            onColorScaleModeChange: { _ in }, onInterpolationModeChange: { _ in },
            onZDomainStateChange: { _ in }, onShowColorbarChange: { _ in })
    }

    static func descriptor(_ plot: WorkbenchControlsPlotAdapter, specific: WorkbenchSpecificContent = .empty,
                           title: String = "Title") -> WorkbenchControlsDescriptor {
        WorkbenchControlsDescriptor(common: common(title: title), plot: plot, specific: specific)
    }
}

/// Hosts a view in a real window, runs a real layout pass at a given width and returns the
/// facts reported by the shared layout containers.
@MainActor
final class ControlsSurfaceHost<Content: View> {
    let probe = WorkbenchLayoutProbe()
    private let window: NSWindow
    private let hosting: NSHostingView<AnyView>

    init(width: CGFloat, @ViewBuilder content: () -> Content) {
        let probe = self.probe
        hosting = NSHostingView(rootView: AnyView(
            ScrollView(.vertical) { content().padding(.horizontal, 0) }
                .environment(\.workbenchLayoutProbe, probe)
        ))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 900),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 900)
        settle()
    }

    func resize(to width: CGFloat) {
        window.setContentSize(NSSize(width: width, height: 900))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 900)
        settle()
    }

    private func settle() {
        for _ in 0..<3 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    var width: CGFloat { hosting.bounds.width }
}

/// Geometry checks shared by the layout tests.
enum ControlsGeometry {
    /// Top-level semantic units: `controls.<section>.<group>`.
    static func groupIDs(_ probe: WorkbenchLayoutProbe) -> [String] {
        probe.frames.keys.filter { $0.split(separator: ".").count == 3 && $0.hasPrefix("controls.") }
            .sorted { lhs, rhs in
                let a = probe.frames[lhs]!, b = probe.frames[rhs]!
                return a.minY == b.minY ? a.minX < b.minX : a.minY < b.minY
            }
    }

    /// Returns human-readable problems (empty = geometry is sound).
    static func problems(_ probe: WorkbenchLayoutProbe, width: CGFloat) -> [String] {
        var out: [String] = []
        let groups = groupIDs(probe)
        for id in groups {
            let f = probe.frames[id]!
            if f.minX < -0.5 || f.maxX > width + 0.5 { out.append("\(id) out of bounds \(f) for width \(width)") }
        }
        for (i, a) in groups.enumerated() {
            for b in groups[(i + 1)...] {
                let fa = probe.frames[a]!, fb = probe.frames[b]!
                let inter = fa.insetBy(dx: 0.5, dy: 0.5).intersection(fb.insetBy(dx: 0.5, dy: 0.5))
                if !inter.isNull && inter.width > 0 && inter.height > 0 { out.append("\(a) overlaps \(b)") }
            }
        }
        for (id, frame) in probe.frames where id.hasSuffix("#content") {
            let rowID = String(id.dropLast("#content".count))
            if let row = probe.frames[rowID], frame.maxX > row.maxX + 0.5 {
                out.append("\(rowID) input overflows its row (clipped): content \(frame.maxX) > row \(row.maxX)")
            }
        }
        for (id, frame) in probe.frames where id.split(separator: ".").count > 3 && !id.hasSuffix("#content") {
            let parts = id.split(separator: ".")
            let parent = parts.prefix(3).joined(separator: ".")
            if let pf = probe.frames[parent], !pf.insetBy(dx: -1, dy: -1).contains(frame) {
                out.append("\(id) escapes its group \(parent)")
            }
        }
        for clip in probe.clips { out.append("\(clip.id) clipped: needs \(clip.required), given \(clip.given)") }
        return out
    }
}
