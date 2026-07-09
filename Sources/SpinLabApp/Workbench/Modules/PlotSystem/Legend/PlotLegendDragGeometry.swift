import CoreGraphics

/// Shared legend-drag geometry contract for Plot System layouts.
///
/// `currentLegendOriginCG` uses the same renderer-space origin convention as the
/// existing XY canvas path: the row-0 legend origin in CG coordinates.
struct PlotLegendDragGeometry: Sendable {
    let rendererSize: CGSize
    let plotRect: CGRect
    let legendBoxRect: CGRect?
    let currentLegendOriginCG: CGPoint
}

struct PlotLegendDragResult: Sendable {
    let grabOffset: CGSize
    let adjustedLegendPoint: CGPoint
    let previewRect: CGRect
}

enum PlotLegendDragEngine {

    static func isInsideLegend(
        location: CGPoint,
        geometry: PlotLegendDragGeometry,
        coordinateContext: CoordinateContext
    ) -> Bool {
        guard let legendBoxRect = geometry.legendBoxRect else { return false }
        return coordinateContext.rendererToScreen(legendBoxRect).contains(location)
    }

    static func dragStep(
        start: CGPoint,
        current: CGPoint,
        geometry: PlotLegendDragGeometry,
        coordinateContext: CoordinateContext,
        existingGrabOffset: CGSize? = nil
    ) -> PlotLegendDragResult? {
        guard let legendBoxRect = geometry.legendBoxRect else { return nil }

        let cursorCG = coordinateContext.screenToRenderer(current)
        let grab: CGSize
        if let existingGrabOffset {
            grab = existingGrabOffset
        } else {
            let startCG = coordinateContext.screenToRenderer(start)
            grab = CGSize(
                width: startCG.x - geometry.currentLegendOriginCG.x,
                height: startCG.y - geometry.currentLegendOriginCG.y
            )
        }

        let rawOriginCG = CGPoint(
            x: cursorCG.x - grab.width,
            y: cursorCG.y - grab.height
        )
        let clampedOriginCG = clampLegendOrigin(
            rawOriginCG,
            geometry: geometry,
            legendBoxRect: legendBoxRect
        )

        let previewRect = coordinateContext.rendererToScreen(
            legendBoxRect.offsetBy(
                dx: clampedOriginCG.x - geometry.currentLegendOriginCG.x,
                dy: clampedOriginCG.y - geometry.currentLegendOriginCG.y
            )
        )

        let plotRect = geometry.plotRect
        let adjustedLegendPoint = CGPoint(
            x: (clampedOriginCG.x - plotRect.minX) / plotRect.width,
            y: (clampedOriginCG.y - plotRect.minY) / plotRect.height
        )

        return PlotLegendDragResult(
            grabOffset: grab,
            adjustedLegendPoint: adjustedLegendPoint,
            previewRect: previewRect
        )
    }

    static func clampLegendOrigin(
        _ rawOriginCG: CGPoint,
        geometry: PlotLegendDragGeometry,
        legendBoxRect: CGRect
    ) -> CGPoint {
        let boundary = geometry.plotRect
        let currentOrigin = geometry.currentLegendOriginCG
        let minX = boundary.minX - (legendBoxRect.minX - currentOrigin.x)
        let maxX = boundary.maxX - (legendBoxRect.maxX - currentOrigin.x)
        let minY = boundary.minY - (legendBoxRect.minY - currentOrigin.y)
        let maxY = boundary.maxY - (legendBoxRect.maxY - currentOrigin.y)

        return CGPoint(
            x: min(max(rawOriginCG.x, minX), maxX),
            y: min(max(rawOriginCG.y, minY), maxY)
        )
    }
}
