import CoreGraphics

/// Shared coordinate bridge between renderer space and screen space.
///
/// Renderer space uses the chart renderer's logical pixel grid with origin at bottom-left.
/// Screen space uses the displayed PNG rect inside the container with origin at top-left.
struct CoordinateContext: Sendable {
    let rendererSize: CGSize
    let displayRect: CGRect

    init(rendererSize: CGSize, displayRect: CGRect) {
        self.rendererSize = rendererSize
        self.displayRect = displayRect
    }

    init?(rendererSize: CGSize, imageSize: CGSize, containerSize: CGSize) {
        guard rendererSize.width > 0, rendererSize.height > 0 else { return nil }
        guard let fitted = Self.widthDrivenDisplayRect(imageSize, in: containerSize) else { return nil }
        self.rendererSize = rendererSize
        self.displayRect = fitted
    }

    func rendererToScreen(_ point: CGPoint) -> CGPoint {
        let scaleX = displayRect.width / rendererSize.width
        let scaleY = displayRect.height / rendererSize.height
        return CGPoint(
            x: displayRect.minX + point.x * scaleX,
            y: displayRect.minY + (rendererSize.height - point.y) * scaleY
        )
    }

    func rendererToScreen(_ rect: CGRect) -> CGRect {
        let scaleX = displayRect.width / rendererSize.width
        let scaleY = displayRect.height / rendererSize.height
        return CGRect(
            x: displayRect.minX + rect.minX * scaleX,
            y: displayRect.minY + (rendererSize.height - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
    }

    func screenToRenderer(_ point: CGPoint) -> CGPoint {
        let scaleX = displayRect.width / rendererSize.width
        let scaleY = displayRect.height / rendererSize.height
        return CGPoint(
            x: (point.x - displayRect.minX) / scaleX,
            y: rendererSize.height - (point.y - displayRect.minY) / scaleY
        )
    }

    func screenToRenderer(_ rect: CGRect) -> CGRect {
        let topLeft = screenToRenderer(CGPoint(x: rect.minX, y: rect.minY))
        let bottomRight = screenToRenderer(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(
            x: topLeft.x,
            y: bottomRight.y,
            width: bottomRight.x - topLeft.x,
            height: topLeft.y - bottomRight.y
        )
    }

    /// Uses the available container width as the primary driver for display size.
    /// This preserves aspect ratio while letting the plot grow smoothly as the
    /// plot column widens.
    static func widthDrivenDisplayRect(_ imageSize: CGSize, in container: CGSize) -> CGRect? {
        guard container.width > 0, container.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return nil }
        let imageAspect = imageSize.width / imageSize.height
        let w = container.width
        let h = w / imageAspect
        return CGRect(x: 0, y: 0, width: w, height: h)
    }
}
