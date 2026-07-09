import SwiftUI
import AppKit

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

    // TODO(用户设计): 调整最小高度、背景样式、空状态文字
    var minHeight: CGFloat = 360

    /// Screen-space bounding rect of the legend drag preview box (nil when not dragging).
    @State private var dragPreviewLegendBoxScreenRect: CGRect? = nil
    /// CG-space offset from legend origin to cursor at drag start.
    @State private var dragGrabOffsetCG: CGSize? = nil
    /// Last valid adjusted normalized point during an active drag.
    @State private var lastValidDragNorm: CGPoint? = nil
    /// Measured container width, used to derive the height that matches the image aspect ratio.
    @State private var measuredContainerWidth: CGFloat = 0

    var body: some View {
        if let imageData = exportArtifacts.pngData, let nsImage = NSImage(data: imageData) {
            let displayHeight = Self.displayHeight(
                imageSize: nsImage.size,
                measuredContainerWidth: measuredContainerWidth,
                minHeight: minHeight
            )
            GeometryReader { geo in
                let containerSize = CGSize(width: geo.size.width, height: displayHeight)
                let legendGeometry = legendDragGeometry ?? layout?.legendDragGeometry
                let rendererSize = legendGeometry?.rendererSize ?? layout?.rendererSize
                if let rendererSize {
                    let coordinateContext = CoordinateContext(
                        rendererSize: rendererSize,
                        displayRect: CGRect(origin: .zero, size: containerSize)
                    )
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
                    .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
                } else {
                    // layout: nil and no explicit legend geometry — display image without hit-testing (heatmap V1 path)
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: containerSize.width, height: containerSize.height)
                }
            }
            .frame(maxWidth: .infinity, minHeight: displayHeight, idealHeight: displayHeight, maxHeight: displayHeight, alignment: .topLeading)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            measuredContainerWidth = geo.size.width
                        }
                        .onChange(of: geo.size.width) { _, newWidth in
                            measuredContainerWidth = newWidth
                        }
                }
            )
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

    private static func displayHeight(
        imageSize: CGSize,
        measuredContainerWidth: CGFloat,
        minHeight: CGFloat
    ) -> CGFloat {
        guard measuredContainerWidth > 0 else { return minHeight }
        let fitted = CoordinateContext.widthDrivenDisplayRect(
            imageSize,
            in: CGSize(width: measuredContainerWidth, height: minHeight)
        )
        return max(minHeight, fitted?.height ?? minHeight)
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
