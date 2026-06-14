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

    /// Screen-space bounding rect of the legend drag preview box (nil when not dragging).
    @State private var dragPreviewLegendBoxScreenRect: CGRect? = nil
    /// CG-space offset from legend origin to cursor at drag start.
    @State private var dragGrabOffsetCG: CGSize? = nil
    /// Last valid adjusted normalized point during an active drag.
    @State private var lastValidDragNorm: CGPoint? = nil

    static let copyPNGScales: [CGFloat] = [1, 2, 3]

    var body: some View {
        if let imageData, let nsImage = NSImage(data: imageData) {
            // GeometryReader provides the container size so we can compute the exact rect
            // where SwiftUI places the displayed image. All overlays use this same rect —
            // no independent guess of the display bounds.
            GeometryReader { geo in
                let containerSize = geo.size
                if let layout, let coordinateContext = CoordinateContext(
                    rendererSize: layout.rendererSize,
                    imageSize: nsImage.size,
                    containerSize: containerSize
                ) {
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .frame(width: coordinateContext.displayRect.width, height: coordinateContext.displayRect.height)
                            .position(x: coordinateContext.displayRect.midX, y: coordinateContext.displayRect.midY)
                        legendDragPreview()
                        PlotCanvasMouseTracker(
                            isEnabled: true,
                            onTap: { handleTap(at: $0, coordinateContext: coordinateContext) },
                            onDragChanged: { start, current in
                                if !_isInLegendFrame(start, coordinateContext: coordinateContext) { return }
                                guard onLegendDrag != nil else { return }
                                guard let step = legendDragStep(
                                    start: start,
                                    current: current,
                                    coordinateContext: coordinateContext,
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
                                    lastValidDragNorm = nil
                                    if let callback = onLegendDrag, let finalNorm = last {
                                        callback(finalNorm)
                                    }
                                }
                            }
                        )
                    }
                    .frame(width: containerSize.width, height: containerSize.height)
                } else {
                    Color.clear
                        .frame(width: containerSize.width, height: containerSize.height)
                }
            }
            .frame(maxWidth: .infinity, minHeight: minHeight)
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
        guard let layout else { return nil }
        let context = CoordinateContext(rendererSize: layout.rendererSize, displayRect: fittedRect)
        return legendDragStep(start: start, current: current, coordinateContext: context, existingGrabOffset: existingGrabOffset)
    }

    func legendDragStep(
        start: CGPoint,
        current: CGPoint,
        coordinateContext: CoordinateContext,
        existingGrabOffset: CGSize?   // CG-space offset: cursor minus legend origin at drag start
    ) -> LegendDragStep? {
        guard let layout, let cgBox = layout.legendBoxRect else { return nil }

        let cursorCG = coordinateContext.screenToRenderer(current)
        let grab: CGSize
        if let existingGrabOffset {
            grab = existingGrabOffset
        } else {
            let startCG  = coordinateContext.screenToRenderer(start)
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

        let previewRect = coordinateContext.rendererToScreen(translatedBoxCG)

        // Convert clamped CG origin back to normalized for persistence
        let pr = layout.plotRect
        let adjustedNorm = CGPoint(
            x: (clampedOriginCG.x - pr.minX) / pr.width,
            y: (clampedOriginCG.y - pr.minY) / pr.height
        )

        return LegendDragStep(grabOffset: grab, adjustedNorm: adjustedNorm, previewRect: previewRect)
    }

    @ViewBuilder
    private func legendDragPreview() -> some View {
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
        guard let layout else { return false }
        let context = CoordinateContext(rendererSize: layout.rendererSize, displayRect: fittedRect)
        return _isInLegendFrame(location, coordinateContext: context)
    }

    func _isInLegendFrame(_ location: CGPoint, coordinateContext: CoordinateContext) -> Bool {
        guard let l = layout, let cgBox = l.legendBoxRect else { return false }
        let screenRect = coordinateContext.rendererToScreen(cgBox)
        return screenRect.contains(location)
    }

    // MARK: - Legend origin helpers

    func currentLegendOriginCG() -> CGPoint {
        guard let layout, !layout.legendRows.isEmpty else { return .zero }
        let row0 = layout.legendRows[0]
        return CGPoint(x: row0.cgOriginX, y: row0.cgRowY + row0.style.rowHeight * 0.4)
    }

    // MARK: - Tap hit-testing (point dot toggle only)

    private func handleTap(at location: CGPoint, coordinateContext: CoordinateContext) {
        guard let layout else { return }
        if onTogglePointLabelVisibility != nil, !layout.pointDotHitTargets.isEmpty {
            for target in layout.pointDotHitTargets {
                if coordinateContext.rendererToScreen(target.hitRect).contains(location) {
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
}
