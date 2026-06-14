import SwiftUI
import AppKit

// MARK: - WorkbenchPlotCanvas

/// 通用图像显示组件。
/// 有数据时显示渲染好的 PNG，无数据时显示占位符。
/// Supports display-only interaction: legend drag, point dot toggle, Copy PNG, hover preview.
/// Text/style editing (title, axis, legend labels, font sizes, tick density) lives in Plot Controls.
struct WorkbenchPlotCanvas: View {
    let imageData: Data?
    /// Layout from the most recent render. Nil = hit-testing disabled.
    var layout: WorkbenchPlotLayout? = nil

    /// Called with a plotRect-normalized point (x,y ∈ [0,1], y=0 bottom, y=1 top)
    /// when the user finishes a drag over the plot area. Nil = drag disabled.
    var onLegendDrag: ((CGPoint) -> Void)? = nil
    /// Point-dot toggle callback: (key, pointIndex) — key is sampleID or Int-string fallback.
    var onTogglePointLabelVisibility: ((String, Int) -> Void)? = nil
    /// Copy PNG at a given pixel scale; returns PNG data or nil if unavailable.
    var onCopyPNG: ((CGFloat) -> Data?)? = nil
    /// Manifest payload for the active chart; used for point-label hit metadata.
    var seriesPayload: WorkbenchPlotPayload? = nil

    /// Related charts for hover popover (nil or empty = no popover).
    var relatedCharts: [WorkbenchResultReference]? = nil
    /// Library root for loading chart thumbnails.
    var libraryRootURL: URL? = nil

    // TODO(用户设计): 调整最小高度、背景样式、空状态文字
    var minHeight: CGFloat = 360

    @State private var canvasSize: CGSize = .zero
    /// Screen-space bounding rect of the legend drag preview box (nil when not dragging).
    @State private var dragPreviewLegendBoxScreenRect: CGRect? = nil
    /// CG-space offset from legend origin to cursor at drag start.
    @State private var dragGrabOffsetCG: CGSize? = nil
    /// Last valid adjusted normalized point during an active drag.
    @State private var lastValidDragNorm: CGPoint? = nil
    /// Pixel size of the current rendered PNG used for coordinate conversion.
    @State private var rendererPixelSize: CGSize = CGSize(width: 800, height: 600)

    private static let defaultRendererSize = CGSize(width: 800, height: 600)
    static let copyPNGScales: [CGFloat] = [1, 2, 3]

    var body: some View {
        if let imageData, let nsImage = NSImage(data: imageData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(
                    GeometryReader { geo in
                        Color.clear.task(id: geo.size) { canvasSize = geo.size }
                    }
                )
                .overlay { legendDragPreview }
                .overlay {
                    PlotCanvasMouseTracker(
                        isEnabled: true,
                        onTap: { handleTap(at: $0) },
                        onDragChanged: { start, current in
                            let fitted = fittedRect(in: canvasSize)
                            if _isInLegendFrame(start, fittedRect: fitted) {
                                guard onLegendDrag != nil else { return }
                            } else {
                                return
                            }
                            guard onLegendDrag != nil else { return }
                            guard let step = legendDragStep(
                                start: start,
                                current: current,
                                fittedRect: fitted,
                                existingGrabOffset: dragGrabOffsetCG
                            ) else { return }
                            dragGrabOffsetCG = step.grabOffset
                            lastValidDragNorm = step.adjustedNorm
                            dragPreviewLegendBoxScreenRect = step.previewRect
                        },
                        onDragEnded: { _, _ in
                            if dragPreviewLegendBoxScreenRect != nil {
                                let last = lastValidDragNorm
                                dragPreviewLegendBoxScreenRect = nil
                                dragGrabOffsetCG = nil
                                lastValidDragNorm  = nil
                                if let callback = onLegendDrag, let finalNorm = last {
                                    callback(finalNorm)
                                }
                            }
                        }
                    )
                }
                .background(
                    .background,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .contextMenu {
                    Menu("Copy PNG") {
                        ForEach(Self.copyPNGScales, id: \.self) { s in
                            Button("\(Int(s))x") {
                                let d = onCopyPNG?(s) ?? imageData
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setData(d, forType: .png)
                            }
                        }
                    }
                }
                .hoverPopover(
                    showDelay: .seconds(1),
                    dismissDelay: .milliseconds(500),
                    arrowEdge: .trailing,
                    isEnabled: relatedCharts?.isEmpty == false && dragPreviewLegendBoxScreenRect == nil
                ) { onHoverChanged, onDialogActiveChanged in
                    MeasurementPlotPreviewPanel(
                        references: relatedCharts ?? [],
                        libraryRootURL: libraryRootURL,
                        onHoverChanged: onHoverChanged,
                        onDialogActiveChanged: onDialogActiveChanged
                    )
                }
        } else {
            ContentUnavailableView(
                "No Plot",
                systemImage: "chart.xyaxis.line",
                description: Text("Select measurements and press Plot.")
            )
            .frame(maxWidth: .infinity, minHeight: minHeight)
        }
    }

    // MARK: - Legend drag preview

    struct LegendDragStep {
        let grabOffset: CGSize
        let adjustedNorm: CGPoint
        let previewRect: CGRect
    }

    func legendDragStep(
        start: CGPoint,
        current: CGPoint,
        fittedRect: CGRect,
        existingGrabOffset: CGSize?   // CG-space offset: cursor minus legend origin at drag start
    ) -> LegendDragStep? {
        guard let layout, let cgBox = layout.legendBoxRect else { return nil }

        let cursorCG = screenToCG(current, fittedRect: fittedRect)
        let grab: CGSize
        if let existingGrabOffset {
            grab = existingGrabOffset
        } else {
            let startCG  = screenToCG(start, fittedRect: fittedRect)
            let originCG = currentLegendOriginCG()
            grab = CGSize(width: startCG.x - originCG.x, height: startCG.y - originCG.y)
        }

        let rawOriginCG = CGPoint(x: cursorCG.x - grab.width, y: cursorCG.y - grab.height)

        // Clamp so the translated legendBoxRect stays within plotRect.
        // Compute fixed offsets from current origin to box edges, then invert to get origin bounds.
        let currentOriginCG = currentLegendOriginCG()
        let boundary = layout.plotRect
        let clampedOriginCG = CGPoint(
            x: min(max(rawOriginCG.x, boundary.minX - (cgBox.minX - currentOriginCG.x)),
                                      boundary.maxX - (cgBox.maxX - currentOriginCG.x)),
            y: min(max(rawOriginCG.y, boundary.minY - (cgBox.minY - currentOriginCG.y)),
                                      boundary.maxY - (cgBox.maxY - currentOriginCG.y))
        )

        let dx = clampedOriginCG.x - currentOriginCG.x
        let dy = clampedOriginCG.y - currentOriginCG.y
        let translatedBoxCG = cgBox.offsetBy(dx: dx, dy: dy)

        let previewRect = WorkbenchPlotLayout.cgToScreen(
            translatedBoxCG, fittedIn: fittedRect,
            rendererWidth: layout.rendererSize.width, rendererHeight: layout.rendererSize.height
        )

        // TEMP DEBUG — remove after height mismatch is diagnosed
        let debugLegendGeometry = true
        if debugLegendGeometry {
            let scaleY = fittedRect.height / layout.rendererSize.height
            let expectedPreviewHeight = cgBox.height * scaleY
            print("""
[LegendGeometry]
  legendRows.count       = \(layout.legendRows.count)
  legendRowH             = \(WorkbenchPlotLayout.legendRowH)
  boxPad                 = 6  (hard-coded in legendBoxRect)
  legendBoxRect.height   = \(cgBox.height)
  translatedBoxCG.height = \(translatedBoxCG.height)
  previewRect.height     = \(previewRect.height)
  fittedRect.height      = \(fittedRect.height)
  rendererSize.height    = \(layout.rendererSize.height)
  scaleY                 = \(scaleY)
  expectedPreviewHeight  = \(expectedPreviewHeight)
  legendBoxRect  minY/maxY = \(cgBox.minY) / \(cgBox.maxY)
  translatedBoxCG minY/maxY = \(translatedBoxCG.minY) / \(translatedBoxCG.maxY)
  previewRect    minY/maxY = \(previewRect.minY) / \(previewRect.maxY)
  plotRect       minY/maxY = \(layout.plotRect.minY) / \(layout.plotRect.maxY)
  rawOriginCG.y            = \(rawOriginCG.y)
  clampedOriginCG.y        = \(clampedOriginCG.y)
""")
        }

        // Convert clamped CG origin back to normalized for persistence
        let pr = layout.plotRect
        let adjustedNorm = CGPoint(
            x: (clampedOriginCG.x - pr.minX) / pr.width,
            y: (clampedOriginCG.y - pr.minY) / pr.height
        )

        return LegendDragStep(grabOffset: grab, adjustedNorm: adjustedNorm, previewRect: previewRect)
    }

    // Converts a screen point to CG renderer space (origin bottom-left, Y up).
    private func screenToCG(_ point: CGPoint, fittedRect: CGRect) -> CGPoint {
        guard let layout, fittedRect.width > 0, fittedRect.height > 0 else { return .zero }
        let scaleX = fittedRect.width  / layout.rendererSize.width
        let scaleY = fittedRect.height / layout.rendererSize.height
        let cgX = (point.x - fittedRect.minX) / scaleX
        let cgY = layout.rendererSize.height - (point.y - fittedRect.minY) / scaleY
        return CGPoint(x: cgX, y: cgY)
    }

    @ViewBuilder
    private var legendDragPreview: some View {
        if let rect = dragPreviewLegendBoxScreenRect {
            // stroke draws centered on the rect boundary (half outside, half inside),
            // matching the CoreGraphics legend border. strokeBorder was inset-only, making
            // the preview visually smaller than the rendered box.
            Rectangle()
                .stroke(
                    Color.accentColor.opacity(0.85),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    func _isInLegendFrame(_ location: CGPoint, fittedRect: CGRect) -> Bool {
        guard let l = layout, let cgBox = l.legendBoxRect else { return false }
        let screenRect = WorkbenchPlotLayout.cgToScreen(
            cgBox, fittedIn: fittedRect,
            rendererWidth: l.rendererSize.width, rendererHeight: l.rendererSize.height
        )
        return screenRect.contains(location)
    }

    // MARK: - Legend origin helpers

    func currentLegendOriginCG() -> CGPoint {
        guard let layout, !layout.legendRows.isEmpty else { return .zero }
        let row0 = layout.legendRows[0]
        return CGPoint(x: row0.cgOriginX, y: row0.cgRowY + WorkbenchPlotLayout.legendRowH * 0.4)
    }

    // MARK: - Tap hit-testing (point dot toggle only)

    private func handleTap(at location: CGPoint) {
        guard let layout else { return }
        let fitted = fittedRect(in: canvasSize)
        let rW = layout.rendererSize.width
        let rH = layout.rendererSize.height

        func toScreen(_ cr: CGRect) -> CGRect {
            WorkbenchPlotLayout.cgToScreen(cr, fittedIn: fitted, rendererWidth: rW, rendererHeight: rH)
        }

        if onTogglePointLabelVisibility != nil, !layout.pointDotHitTargets.isEmpty {
            for target in layout.pointDotHitTargets {
                if toScreen(target.hitRect).contains(location) {
                    let key: String
                    if let sid = seriesPayload?.series[safe: target.seriesIndex]?.sampleID {
                        key = sid
                    } else {
                        key = String(target.seriesIndex)
                    }
                    onTogglePointLabelVisibility?(key, target.pointIndex)
                    return
                }
            }
        }
    }

    // MARK: - Geometry helpers

    private func fittedRect(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let imageAspect = rendererPixelSize.width / rendererPixelSize.height
        let containerAspect = size.width / size.height
        let w: CGFloat
        let h: CGFloat
        if containerAspect > imageAspect {
            h = size.height; w = h * imageAspect
        } else {
            w = size.width; h = w / imageAspect
        }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func plotNormalized(location: CGPoint, fittedRect: CGRect) -> CGPoint? {
        guard !fittedRect.isEmpty else { return nil }
        let rSize = layout?.rendererSize ?? rendererPixelSize
        let pr = layout?.plotRect ?? {
            let opts = WorkbenchChartRenderer.Options()
            return CGRect(
                x: opts.paddingLeft, y: opts.paddingBottom,
                width: rSize.width - opts.paddingLeft - opts.paddingRight,
                height: rSize.height - opts.paddingTop - opts.paddingBottom
            )
        }()
        let cx = min(max(location.x, fittedRect.minX), fittedRect.maxX)
        let cy = min(max(location.y, fittedRect.minY), fittedRect.maxY)
        let px = (cx - fittedRect.minX) / fittedRect.width  * rSize.width
        let py = (cy - fittedRect.minY) / fittedRect.height * rSize.height
        let plotMinX = pr.minX
        let plotMinY = rSize.height - pr.maxY
        let nx = (px - plotMinX) / pr.width
        let ny = 1.0 - (py - plotMinY) / pr.height
        return CGPoint(x: min(max(nx, 0), 1), y: min(max(ny, 0), 1))
    }

}

