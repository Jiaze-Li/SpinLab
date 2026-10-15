import AppKit
import SwiftUI
import Testing
@testable import SpinLabApp

/// Renders the real AFM controls at several widths so narrow-window layout can be inspected
/// and guarded (no clipping/overflow). Writes PNGs to `SPINLAB_AFM_EXPORT_DIR` when set.
@Suite("AFM controls layout (rendered)")
struct AFMControlsLayoutRenderTests {

    private static let channel = CanonicalAFMChannel(
        id: "c", sourceIndex: 0, sourceLabel: "HeightRetrace", semanticTypeRaw: "Height", displayLabel: "HeightRetrace",
        values: [[0]], canonicalUnit: "nm", sourceUnit: "m",
        provenance: AFMChannelProvenance(planefit: nil, planefitOrder: nil, flattenOrder: nil, planefitOffset: nil, planefitXSlope: nil, planefitYSlope: nil)
    )

    @MainActor
    private func render(width: CGFloat, scaleBar: AFMScaleBarSetting) -> (NSBitmapImageRep, CGSize) {
        let view = AFMPlotControls(
            channels: [Self.channel], activeChannelID: "c", surfaceLevel: .plane, lineFlattenOrder: .order1,
            zeroReference: .mean, scaleBar: scaleBar,
            onChannelChange: { _ in }, onSurfaceLevelChange: { _ in }, onLineFlattenChange: { _ in },
            onZeroReferenceChange: { _ in }, onScaleBarChange: { _ in }
        )
        .frame(width: width)
        .padding(8)
        .background(Color.white)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width + 16, height: 10)
        let fitting = host.fittingSize
        host.frame = NSRect(origin: .zero, size: NSSize(width: width + 16, height: max(fitting.height, 40)))
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        return (rep, host.fittingSize)
    }

    @MainActor
    @Test("controls render at narrow and normal widths; export PNGs for inspection", arguments: [300.0, 380.0, 520.0])
    func rendersAtWidth(width: Double) throws {
        for (name, setting) in [
            ("auto", AFMScaleBarSetting(mode: .auto)),
            ("manualBlack", AFMScaleBarSetting(mode: .manual, manualLengthMicrometers: 2, color: .black)),
        ] {
            let (rep, fit) = render(width: CGFloat(width), scaleBar: setting)
            #expect(fit.width <= CGFloat(width) + 16 + 1, "controls overflow their column at width \(width): fitting \(fit.width)")
            if let dir = ProcessInfo.processInfo.environment["SPINLAB_AFM_EXPORT_DIR"] {
                let png = rep.representation(using: .png, properties: [:])!
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("controls-\(Int(width))-\(name).png"))
            }
        }
    }
}
