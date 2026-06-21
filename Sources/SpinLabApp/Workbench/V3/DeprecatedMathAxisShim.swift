import CoreGraphics

protocol LegacyAxisLabelRendering {
    func draw(
        ctx: CGContext,
        source: String,
        fontSize: CGFloat,
        color: CGColor,
        at center: CGPoint,
        orientation: LegacyAxisLabelRenderer.Orientation
    ) -> Bool
}

typealias LatexAxisLabelRendering = LegacyAxisLabelRendering

final class LegacyAxisLabelRenderer: LegacyAxisLabelRendering {
    static let shared = LegacyAxisLabelRenderer()
    static let sourcePrefix = "latex:"

    enum Orientation {
        case horizontal
        case rotated90
    }

    static func isSourceLabel(_ text: String) -> Bool {
        text.hasPrefix(sourcePrefix)
    }

    static func extractSource(_ text: String) -> String {
        String(text.dropFirst(sourcePrefix.count))
    }

    func draw(
        ctx: CGContext,
        source: String,
        fontSize: CGFloat,
        color: CGColor,
        at center: CGPoint,
        orientation: Orientation
    ) -> Bool {
        false
    }
}

typealias LatexAxisLabelRenderer = LegacyAxisLabelRenderer
