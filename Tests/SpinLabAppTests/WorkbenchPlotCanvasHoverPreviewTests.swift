import AppKit
import SwiftUI
import Testing
@testable import SpinLabApp

@MainActor
@Suite("WorkbenchPlotCanvasHoverPreview")
struct WorkbenchPlotCanvasHoverPreviewTests {

    private func png() -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        return rep.representation(using: .png, properties: [:])!
    }

    private func reference() -> WorkbenchResultReference {
        WorkbenchResultReference(
            chartIdentityKey: "k", chartImagePath: "charts/a.png", manifestPath: "charts/a.json",
            workflowID: "afm", generatedAt: Date(timeIntervalSince1970: 0), tabKey: nil
        )
    }

    /// True when the realised view tree (only the branch actually taken) contains the hover popover modifier.
    private func mountsHoverPopover(_ canvas: WorkbenchPlotCanvas) -> Bool {
        func walk(_ value: Any, depth: Int) -> Bool {
            if depth > 14 { return false }
            // Base type name only: generic arguments of the untaken `_ConditionalContent` branch also
            // mention the modifier, but only a realised branch stores an actual modifier value.
            let name = String(describing: type(of: value))
            if name.prefix(while: { $0 != "<" }) == "HoverPopoverModifier" { return true }
            return Mirror(reflecting: value).children.contains { walk($0.value, depth: depth + 1) }
        }
        return walk(canvas.body, depth: 0)
    }

    private func canvas(related: [WorkbenchResultReference]?) -> WorkbenchPlotCanvas {
        WorkbenchPlotCanvas(
            exportArtifacts: .init(pngData: png(), pdfData: nil),
            relatedCharts: related
        )
    }

    @Test("predicate: only a non-empty related-chart list needs a hover preview")
    func predicate() {
        #expect(!WorkbenchPlotCanvas.shouldMountHoverPreview(relatedCharts: nil))
        #expect(!WorkbenchPlotCanvas.shouldMountHoverPreview(relatedCharts: []))
        #expect(WorkbenchPlotCanvas.shouldMountHoverPreview(relatedCharts: [reference()]))
    }

    @Test("no related charts: the hover popover modifier is not in the view tree at all")
    func notMountedWithoutRelatedCharts() {
        #expect(!mountsHoverPopover(canvas(related: nil)))
        #expect(!mountsHoverPopover(canvas(related: [])))
    }

    @Test("related charts present: the hover popover is mounted")
    func mountedWithRelatedCharts() {
        #expect(mountsHoverPopover(canvas(related: [reference()])))
    }

    @Test("the mounted state follows the current related-chart list (nil, non-empty, empty)")
    func dynamicChange() {
        #expect(!mountsHoverPopover(canvas(related: nil)))
        #expect(mountsHoverPopover(canvas(related: [reference()])))
        #expect(!mountsHoverPopover(canvas(related: [])))
    }
}
