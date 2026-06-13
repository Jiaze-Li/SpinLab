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
    /// Normalized offset (plot-space, Y-up) from legend origin to cursor at drag start.
    @State private var dragGrabOffsetNorm: CGSize? = nil
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
                                existingGrabOffset: dragGrabOffsetNorm
                            ) else { return }
                            dragGrabOffsetNorm = step.grabOffset
                            lastValidDragNorm = step.adjustedNorm
                            dragPreviewLegendBoxScreenRect = step.previewRect
                        },
                        onDragEnded: { _, _ in
                            if dragPreviewLegendBoxScreenRect != nil {
                                let last = lastValidDragNorm
                                dragPreviewLegendBoxScreenRect = nil
                                dragGrabOffsetNorm = nil
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
        existingGrabOffset: CGSize?
    ) -> LegendDragStep? {
        guard let cursorNorm = plotNormalized(location: current, fittedRect: fittedRect) else { return nil }
        let grab: CGSize
        if let existingGrabOffset {
            grab = existingGrabOffset
        } else {
            let startNorm = plotNormalized(location: start, fittedRect: fittedRect) ?? cursorNorm
            let origin = currentLegendOriginNorm()
            grab = CGSize(
                width: startNorm.x - origin.x,
                height: startNorm.y - origin.y
            )
        }
        let adjusted = CGPoint(
            x: min(max(cursorNorm.x - grab.width,  0), 1),
            y: min(max(cursorNorm.y - grab.height, 0), 1)
        )
        guard let previewRect = translatedLegendBoxRect(for: adjusted, fittedRect: fittedRect) else { return nil }
        return LegendDragStep(
            grabOffset: grab,
            adjustedNorm: adjusted,
            previewRect: previewRect
        )
    }

    @ViewBuilder
    private var legendDragPreview: some View {
        if let rect = dragPreviewLegendBoxScreenRect {
            Rectangle()
                .strokeBorder(
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

    private func currentLegendOriginNorm() -> CGPoint {
        guard let layout, !layout.legendRows.isEmpty else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        let pr = layout.plotRect
        let row0 = layout.legendRows[0]
        let nx = (row0.cgOriginX - pr.minX) / pr.width
        let cgOriginY = row0.cgRowY + WorkbenchPlotLayout.legendRowH * 0.4
        let ny = (cgOriginY - pr.minY) / pr.height
        return CGPoint(x: min(max(nx, 0), 1), y: min(max(ny, 0), 1))
    }

    // MARK: - Legend box translation helpers

    func currentLegendOriginCG() -> CGPoint {
        guard let layout, !layout.legendRows.isEmpty else { return .zero }
        let row0 = layout.legendRows[0]
        return CGPoint(x: row0.cgOriginX, y: row0.cgRowY + WorkbenchPlotLayout.legendRowH * 0.4)
    }

    func legendOriginCG(for normalized: CGPoint) -> CGPoint {
        let pr: CGRect
        if let layout {
            pr = layout.plotRect
        } else {
            let opts = WorkbenchChartRenderer.Options()
            let rSize = rendererPixelSize
            pr = CGRect(
                x: opts.paddingLeft, y: opts.paddingBottom,
                width: rSize.width - opts.paddingLeft - opts.paddingRight,
                height: rSize.height - opts.paddingTop - opts.paddingBottom
            )
        }
        return CGPoint(x: pr.minX + normalized.x * pr.width, y: pr.minY + normalized.y * pr.height)
    }

    func translatedLegendBoxRect(for target: CGPoint, fittedRect: CGRect) -> CGRect? {
        guard let layout, let cgBox = layout.legendBoxRect else { return nil }
        let currentOrigin = currentLegendOriginCG()
        let targetOrigin  = legendOriginCG(for: target)
        let dx = targetOrigin.x - currentOrigin.x
        let dy = targetOrigin.y - currentOrigin.y
        let translatedCG = cgBox.offsetBy(dx: dx, dy: dy)
        return WorkbenchPlotLayout.cgToScreen(
            translatedCG, fittedIn: fittedRect,
            rendererWidth: layout.rendererSize.width, rendererHeight: layout.rendererSize.height
        )
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

