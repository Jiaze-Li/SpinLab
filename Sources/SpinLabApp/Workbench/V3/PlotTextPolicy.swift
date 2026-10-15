import CoreGraphics
import CoreText
import Foundation

/// Single entry point for scientific-plot text: font family and text color.
///
/// Implements `specs/05_PLOT_RULES.md`. Every CoreText font or text line used by the
/// Cartesian XY, DualAxis and Heatmap renderers (and their measurement code) is created
/// here, so preview, PNG and PDF cannot drift apart and legacy font settings cannot leak
/// a non-Arial face into a figure.
enum PlotTextPolicy {

    // MARK: - Font

    static let regularFontName = "ArialMT"
    static let boldFontName = "Arial-BoldMT"
    static let italicFontName = "Arial-ItalicMT"
    static let boldItalicFontName = "Arial-BoldItalicMT"
    static let familyName = "Arial"

    /// PostScript names that already belong to the Arial family.
    static let allowedFontNames: Set<String> = [
        "Arial", regularFontName, boldFontName, italicFontName, boldItalicFontName,
    ]

    /// Returns an Arial-family PostScript name. Arial names pass through (Regular, Bold and
    /// Italic may coexist); anything else (e.g. a legacy "TimesNewRomanPSMT" from an old Pack
    /// or user setting) resolves to the Arial face for the requested weight slot.
    static func resolvedFontName(_ requested: String, bold: Bool = false) -> String {
        if bold, requested == "Arial" || requested == regularFontName { return boldFontName }
        if allowedFontNames.contains(requested) { return requested }
        return bold ? boldFontName : regularFontName
    }

    static func font(name requested: String, size: CGFloat, bold: Bool = false) -> CTFont {
        CTFontCreateWithName(resolvedFontName(requested, bold: bold) as CFString, size, nil)
    }

    /// True when the installed Arial resolves to the Arial family (false on a host without Arial).
    static var isArialInstalled: Bool {
        let f = CTFontCreateWithName(regularFontName as CFString, 12, nil)
        return (CTFontCopyFamilyName(f) as String) == familyName
    }

    // MARK: - Color

    static let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    /// Snaps any requested text color to opaque pure black or pure white.
    /// Only a (near-)white request yields white; every other color — gray, series colors,
    /// translucent colors — yields black. Curves, markers, gradients and grid lines never go
    /// through this function.
    static func resolvedTextColor(_ requested: CGColor) -> CGColor {
        guard let srgb = requested.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil
        ), let c = srgb.components, c.count >= 3 else { return black }
        let alpha = c.count >= 4 ? c[3] : 1
        let isWhite = alpha >= 0.999 && c[0] >= 0.95 && c[1] >= 0.95 && c[2] >= 0.95
        return isWhite ? white : black
    }

    // MARK: - Text line

    /// The shared plain-text line factory: Arial font, black/white foreground, no stroke
    /// and no shadow attributes.
    static func line(
        text: String,
        size: CGFloat,
        bold: Bool,
        color: CGColor,
        fontName: String,
        boldFontName: String
    ) -> CTLine {
        let font = font(name: bold ? boldFontName : fontName, size: size, bold: bold)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: resolvedTextColor(color),
        ]
        let attrStr = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attrs as CFDictionary)!
        return CTLineCreateWithAttributedString(attrStr)
    }
}

extension WorkbenchChartStyle {
    /// Plain text line in this style's (Arial-resolved) font; use for all plot text.
    func makeTextLine(_ text: String, size: CGFloat, bold: Bool = false, color: CGColor) -> CTLine {
        PlotTextPolicy.line(
            text: text, size: size, bold: bold, color: color,
            fontName: fontName, boldFontName: boldFontName
        )
    }
}
