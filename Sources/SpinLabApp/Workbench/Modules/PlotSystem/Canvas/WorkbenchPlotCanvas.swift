import SwiftUI
import AppKit

// MARK: - DecodedPlotImageCache

/// Single-slot cache of the decoded plot image. `NSImage(data:)` is lazy, so the expensive
/// pixel decode happens on first draw of a given `NSImage` instance; reusing the instance is
/// what avoids re-decoding. Invalidation is by PNG content (not size or identity), so a new
/// plot of identical dimensions never reuses a stale image, and a nil/undecodable PNG drops it.
final class DecodedPlotImageCache {
    private var cachedData: Data?
    private var cachedImage: NSImage?
    /// Number of `NSImage(data:)` constructions; exposed for tests.
    private(set) var decodeCount = 0

    func image(for data: Data?) -> NSImage? {
        guard let data else {
            cachedData = nil
            cachedImage = nil
            return nil
        }
        if let cachedImage, let cachedData, cachedData == data {
            return cachedImage
        }
        decodeCount += 1
        let image = NSImage(data: data)
        cachedData = image == nil ? nil : data
        cachedImage = image
        return image
    }
}

// MARK: - WorkbenchPlotCanvas

/// 通用图像显示组件。
/// 有数据时显示渲染好的 PNG，无数据时显示占位符。
/// Supports display-only interaction: legend drag, point dot toggle, Copy PNG, hover preview.
/// Text/style editing (title, axis, legend labels, font sizes, tick density) lives in Plot Controls.
struct WorkbenchPlotCanvas: View {
    /// Render-path-agnostic PNG/PDF artifacts for the active plot tab. The canvas displays
    /// `exportArtifacts.pngData` and copies whichever artifact the user asks for directly —
    /// it never knows which render path (Cartesian XY, DualAxis, Heatmap/RSM) produced them.
    var exportArtifacts: WorkbenchGraphicExportArtifacts
    /// Layout from the most recent render. Nil = hit-testing disabled.
    var layout: WorkbenchPlotLayout? = nil
    /// Optional explicit legend geometry for non-Cartesian render paths.
    var legendDragGeometry: PlotLegendDragGeometry? = nil

    /// Called with a plotRect-normalized point (x,y ∈ [0,1], y=0 bottom, y=1 top)
    /// when the user finishes a drag over the plot area. Nil = drag disabled.
    var onLegendDrag: ((CGPoint) -> Void)? = nil
    /// Point-dot toggle callback: (key, pointIndex) — key is sampleID or Int-string fallback.
    var onTogglePointLabelVisibility: ((String, Int) -> Void)? = nil
    /// Manifest payload for the active chart; used for point-label hit metadata.
    var seriesPayload: WorkbenchPlotPayload? = nil

    /// Related charts for hover popover (nil or empty = no popover).
    var relatedCharts: [WorkbenchResultReference]? = nil
    /// Library root for loading chart thumbnails.
    var libraryRootURL: URL? = nil

    /// Placeholder height for the empty state only; a displayed plot is never height-clamped.
    var minHeight: CGFloat = 360

    /// Screen-space bounding rect of the legend drag preview box (nil when not dragging).
    @State private var dragPreviewLegendBoxScreenRect: CGRect? = nil
    /// CG-space offset from legend origin to cursor at drag start.
    @State private var dragGrabOffsetCG: CGSize? = nil
    /// Last valid adjusted normalized point during an active drag.
    @State private var lastValidDragNorm: CGPoint? = nil
    /// Keeps the decoded `NSImage` alive across body re-evaluations (e.g. every frame of a
    /// column-width drag) so the PNG is decoded once per distinct content, not once per body.
    @State private var decodedImageCache = DecodedPlotImageCache()

    var body: some View {
        // Always consult the cache (even with nil data) so an emptied plot releases the image.
        let decodedImage = decodedImageCache.image(for: exportArtifacts.pngData)
        if let imageData = exportArtifacts.pngData, let nsImage = decodedImage {
            // Width comes from the column; height follows the PNG aspect ratio exactly
            // (no minHeight, no state feedback). The GeometryReader fills the already
            // aspect-locked frame, so the image occupies the whole canvas.
            let imageAspect = Self.aspectRatio(of: nsImage.size)
            GeometryReader { geo in
                let fittedRect = CGRect(origin: .zero, size: geo.size)
                let legendGeometry = legendDragGeometry ?? layout?.legendDragGeometry
                let rendererSize = legendGeometry?.rendererSize ?? layout?.rendererSize
                if let rendererSize {
                    let coordinateContext = CoordinateContext(
                        rendererSize: rendererSize,
                        displayRect: fittedRect
                    )
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .frame(width: fittedRect.width, height: fittedRect.height)
                        legendDragPreview()
                        PlotCanvasMouseTracker(
                            isEnabled: true,
                            onTap: { handleTap(at: $0, coordinateContext: coordinateContext) },
                            onDragChanged: { start, current in
                                guard let legendGeometry else { return }
                                if !PlotLegendDragEngine.isInsideLegend(
                                    location: start,
                                    geometry: legendGeometry,
                                    coordinateContext: coordinateContext
                                ) { return }
                                guard onLegendDrag != nil else { return }
                                guard let step = PlotLegendDragEngine.dragStep(
                                    start: start,
                                    current: current,
                                    geometry: legendGeometry,
                                    coordinateContext: coordinateContext,
                                    existingGrabOffset: dragGrabOffsetCG
                                ) else { return }
                                dragGrabOffsetCG = step.grabOffset
                                lastValidDragNorm = step.adjustedLegendPoint
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
                    .frame(width: fittedRect.width, height: fittedRect.height, alignment: .topLeading)
                } else {
                    // layout: nil and no explicit legend geometry — display image without hit-testing (heatmap V1 path)
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: fittedRect.width, height: fittedRect.height)
                }
            }
            .aspectRatio(imageAspect, contentMode: .fit)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                .background,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contextMenu {
                Button("Copy PNG") {
                    WorkbenchPasteboardWriter.copyPNG(imageData)
                }
                if let pdfData = exportArtifacts.pdfData {
                    Button("Copy PDF") {
                        WorkbenchPasteboardWriter.copyPDF(pdfData)
                    }
                }
            }
            .relatedChartsHoverPreview(
                relatedCharts: relatedCharts,
                libraryRootURL: libraryRootURL,
                isSuspended: dragPreviewLegendBoxScreenRect != nil
            )
        } else {
            ContentUnavailableView(
                "No Plot",
                systemImage: "chart.xyaxis.line",
                description: Text("Select measurements and press Plot.")
            )
            .frame(maxWidth: .infinity, minHeight: minHeight)
        }
    }

    /// The hover preview is only mounted when there is something to preview. Attaching
    /// `hoverPopover` even while disabled adds a popover anchor to the canvas that is
    /// re-resolved on every width change, which dominates main-thread time while the
    /// right column is being resized.
    static func shouldMountHoverPreview(relatedCharts: [WorkbenchResultReference]?) -> Bool {
        relatedCharts?.isEmpty == false
    }

    /// Width / height of the PNG; a degenerate size falls back to 4:3 so layout never divides by zero.
    static func aspectRatio(of imageSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 4.0 / 3.0 }
        return imageSize.width / imageSize.height
    }

    /// Aspect-correct display rect for an image inside an arbitrary container. The live canvas no longer
    /// needs letterboxing (its frame is aspect-locked, so the rect is the full frame); this stays as the
    /// pure helper for callers that do fit into a fixed container.
    /// Preserves displayedWidth / displayedHeight == imageWidth / imageHeight.
    /// If the container is taller than the proportional image (e.g. Due to minHeight),
    /// the image is centered vertically.
    static func displayRect(
        imageSize: CGSize,
        containerSize: CGSize
    ) -> CGRect {
        guard containerSize.width > 0, containerSize.height > 0,
              imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        let imageAspect = imageSize.width / imageSize.height
        let displayWidth = containerSize.width
        let displayHeight = displayWidth / imageAspect
        let yOffset = max(0, (containerSize.height - displayHeight) / 2)
        return CGRect(x: 0, y: yOffset, width: displayWidth, height: displayHeight)
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
        guard let geometry = legendDragGeometry ?? layout?.legendDragGeometry else { return nil }
        let context = CoordinateContext(rendererSize: geometry.rendererSize, displayRect: fittedRect)
        return legendDragStep(
            start: start,
            current: current,
            geometry: geometry,
            coordinateContext: context,
            existingGrabOffset: existingGrabOffset
        )
    }

    func legendDragStep(
        start: CGPoint,
        current: CGPoint,
        geometry: PlotLegendDragGeometry,
        coordinateContext: CoordinateContext,
        existingGrabOffset: CGSize?
    ) -> LegendDragStep? {
        guard let step = PlotLegendDragEngine.dragStep(
            start: start,
            current: current,
            geometry: geometry,
            coordinateContext: coordinateContext,
            existingGrabOffset: existingGrabOffset
        ) else { return nil }
        return LegendDragStep(
            grabOffset: step.grabOffset,
            adjustedNorm: step.adjustedLegendPoint,
            previewRect: step.previewRect
        )
    }

    func currentLegendOriginCG() -> CGPoint {
        guard let geometry = legendDragGeometry ?? layout?.legendDragGeometry else { return .zero }
        return geometry.currentLegendOriginCG
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
        guard let geometry = legendDragGeometry ?? layout?.legendDragGeometry else { return false }
        let context = CoordinateContext(rendererSize: geometry.rendererSize, displayRect: fittedRect)
        return _isInLegendFrame(location, coordinateContext: context)
    }

    func _isInLegendFrame(_ location: CGPoint, coordinateContext: CoordinateContext) -> Bool {
        guard let geometry = legendDragGeometry ?? layout?.legendDragGeometry else { return false }
        return PlotLegendDragEngine.isInsideLegend(location: location, geometry: geometry, coordinateContext: coordinateContext)
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

private extension View {
    @ViewBuilder
    func relatedChartsHoverPreview(
        relatedCharts: [WorkbenchResultReference]?,
        libraryRootURL: URL?,
        isSuspended: Bool
    ) -> some View {
        if WorkbenchPlotCanvas.shouldMountHoverPreview(relatedCharts: relatedCharts), let relatedCharts {
            hoverPopover(
                showDelay: .seconds(1),
                dismissDelay: .milliseconds(500),
                arrowEdge: .trailing,
                isEnabled: !isSuspended
            ) { onHoverChanged, onDialogActiveChanged in
                MeasurementPlotPreviewPanel(
                    references: relatedCharts,
                    libraryRootURL: libraryRootURL,
                    onHoverChanged: onHoverChanged,
                    onDialogActiveChanged: onDialogActiveChanged
                )
            }
        } else {
            self
        }
    }
}
