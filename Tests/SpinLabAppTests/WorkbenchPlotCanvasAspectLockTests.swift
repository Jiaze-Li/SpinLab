import AppKit
import SwiftUI
import Testing
@testable import SpinLabApp

/// Records the size the canvas reports for a width-only proposal, as a parent
/// `ScrollView`/`VStack` would give it (unbounded height).
private struct ProbeLayout: Layout {
    let record: @MainActor (CGSize) -> Void
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(proposal) ?? .zero
        MainActor.assumeIsolated { record(size) }
        return size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: proposal)
    }
}

@MainActor
@Suite("Workbench Plot Canvas Aspect Lock Tests")
struct WorkbenchPlotCanvasAspectLockTests {

    private func png(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        return rep.representation(using: .png, properties: [:])!
    }

    /// Canvas size when hosted at `width` with unbounded height.
    private func canvasSize(png: Data?, width: CGFloat) -> CGSize {
        var measured = CGSize.zero
        let canvas = WorkbenchPlotCanvas(exportArtifacts: .init(pngData: png, pdfData: nil))
        let root = ProbeLayout(record: { measured = $0 }) { canvas }
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 2000)
        host.layoutSubtreeIfNeeded()
        return measured
    }

    @Test("height follows PNG aspect ratio at every width, with no minHeight clamp", arguments: [
        (400, 300), (2400, 1800), (1200, 600), (300, 900),
    ])
    func heightFollowsAspect(imgW: Int, imgH: Int) {
        let data = png(width: imgW, height: imgH)
        for width in stride(from: CGFloat(800), through: 150, by: -50) + [CGFloat(1000)] {
            let size = canvasSize(png: data, width: width)
            let expected = width * CGFloat(imgH) / CGFloat(imgW)
            #expect(abs(size.width - width) < 0.5, "width \(size.width) vs \(width)")
            #expect(abs(size.height - expected) < 0.5, "w=\(width) img=\(imgW)x\(imgH): height \(size.height) vs \(expected)")
        }
    }

    @Test("narrowing and widening give identical sizes (no hysteresis)")
    func noHysteresis() {
        let data = png(width: 800, height: 600)
        let widths: [CGFloat] = [800, 700, 500, 300, 500, 700, 800]
        let heights = widths.map { canvasSize(png: data, width: $0).height }
        #expect(heights[1] == heights[5])
        #expect(heights[2] == heights[4])
        #expect(heights[0] == heights[6])
    }

    @Test("empty state keeps its placeholder height")
    func emptyKeepsPlaceholder() {
        let size = canvasSize(png: nil, width: 500)
        #expect(size.height >= 360)
    }
}
