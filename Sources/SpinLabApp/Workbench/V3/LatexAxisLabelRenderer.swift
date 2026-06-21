import Foundation
import CoreGraphics

/// Axis-specific LaTeX label renderer.
///
/// Owns: latex: prefix detection and stripping, axis orientation (horizontal /
/// rotated90), footprint conventions, and fallback policy when LaTeX is unavailable.
///
/// Compilation, caching, and rasterisation are delegated to LatexRenderService.
/// This type has no knowledge of the LaTeX backend or cache internals.
final class LatexAxisLabelRenderer {

    static let shared = LatexAxisLabelRenderer()

    // MARK: - Prefix helpers

    static let latexPrefix = "latex:"

    static func isLatexLabel(_ text: String) -> Bool {
        text.hasPrefix(latexPrefix)
    }

    static func extractLatex(_ text: String) -> String {
        String(text.dropFirst(latexPrefix.count))
    }

    // MARK: - Orientation

    enum Orientation {
        case horizontal
        case rotated90
    }

    // MARK: - Dependencies

    private let service: LatexRenderService

    /// Designated init; inject a custom LatexRenderService for tests.
    init(service: LatexRenderService = .shared) {
        self.service = service
    }

    // MARK: - Measurement API (axis-aware)

    /// Returns the rendered size for the formula at the given font size, or nil when unavailable.
    ///
    /// Footprint conventions for rotated Y-axis labels (applied by PlotAxisSpacingCalculator):
    ///   horizontal footprint = returned size.height   (PDF height becomes width after 90° rotation)
    ///   vertical footprint   = returned size.width
    func labelSize(latex: String, fontSize: CGFloat) -> CGSize? {
        service.naturalSize(latex: latex, fontSize: fontSize)
    }

    // MARK: - Draw API (axis-aware)

    /// Draws the LaTeX formula into ctx centered at the given point.
    /// Returns false when LaTeX is unavailable so the caller can fall back to MathMarkupRenderer.
    @discardableResult
    func draw(
        ctx: CGContext,
        latex: String,
        fontSize: CGFloat,
        color: CGColor,
        at center: CGPoint,
        orientation: Orientation
    ) -> Bool {
        guard let asset = service.render(latex: latex, color: color) else {
            print("[LatexAxisLabelRenderer] LaTeX not available — falling back to MathMarkupRenderer")
            return false
        }
        let scale = fontSize / 12.0
        let drawSize = CGSize(
            width:  asset.naturalSize.width  * scale,
            height: asset.naturalSize.height * scale
        )
        ctx.saveGState()
        switch orientation {
        case .horizontal:
            let origin = CGPoint(
                x: center.x - drawSize.width  / 2,
                y: center.y - drawSize.height / 2
            )
            ctx.draw(asset.image, in: CGRect(origin: origin, size: drawSize))
        case .rotated90:
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: .pi / 2)
            let origin = CGPoint(x: -drawSize.width / 2, y: -drawSize.height / 2)
            ctx.draw(asset.image, in: CGRect(origin: origin, size: drawSize))
        }
        ctx.restoreGState()
        return true
    }
}
