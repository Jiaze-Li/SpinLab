import CoreGraphics
import CoreText
import Foundation

/// Segment produced by parsing a math markup string.
enum MathMarkupSegment: Equatable {
    case base(String)
    case sub(String)
    case sup(String)
}

/// Lightweight math markup renderer for chart axis labels.
///
/// Syntax:
///   _{text}   subscript group (multi-character)
///   ^{text}   superscript group (multi-character)
///   _X        subscript single character (backward-compatible)
///   ^X        superscript single character (backward-compatible)
///
/// Greek letters (σ, ω, …) and other Unicode characters pass through as base text.
/// Subscripts render at 65 % font size, lowered baseline.
/// Superscripts render at 65 % font size, raised baseline.
struct MathMarkupRenderer {

    static func containsMarkup(_ text: String) -> Bool {
        text.contains("_") || text.contains("^")
    }

    /// Parses a markup string into a sequence of typed segments.
    static func parse(_ text: String) -> [MathMarkupSegment] {
        var segments: [MathMarkupSegment] = []
        var baseBuffer = ""
        var iter = text.unicodeScalars.makeIterator()

        func flushBase() {
            if !baseBuffer.isEmpty {
                segments.append(.base(baseBuffer))
                baseBuffer = ""
            }
        }

        while let scalar = iter.next() {
            guard scalar == "_" || scalar == "^" else {
                baseBuffer.unicodeScalars.append(scalar)
                continue
            }
            let isSub = (scalar == "_")
            guard let next = iter.next() else {
                // Trailing marker with no following character: treat as base.
                baseBuffer.unicodeScalars.append(scalar)
                break
            }
            flushBase()
            if next == "{" {
                var group = ""
                while let gc = iter.next(), gc != "}" {
                    group.unicodeScalars.append(gc)
                }
                segments.append(isSub ? .sub(group) : .sup(group))
            } else {
                // Single-character backward-compatible form.
                segments.append(isSub ? .sub(String(next)) : .sup(String(next)))
            }
        }
        flushBase()
        return segments
    }

    /// Creates a CoreText line for the markup string using the chart style's font.
    static func makeLine(
        text: String,
        size: CGFloat,
        color: CGColor,
        style: WorkbenchChartStyle
    ) -> CTLine {
        guard containsMarkup(text) else {
            return plainLine(text: text, fontName: style.fontName, size: size, color: color)
        }
        let font    = style.ctFont(size: size, bold: false)
        let subFont = style.ctFont(size: size * 0.65, bold: false)
        let supFont = style.ctFont(size: size * 0.65, bold: false)
        return attributedLine(
            segments: parse(text),
            font: font, subFont: subFont, supFont: supFont,
            size: size, color: color
        )
    }

    /// Returns the rendered width of a markup string in the given font at the given size.
    ///
    /// Used by layout measurement so that markup characters (_, ^, {, }) are not
    /// counted as full-width glyphs.
    static func measuredWidth(text: String, size: CGFloat, fontName: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        guard containsMarkup(text) else {
            let font = CTFontCreateWithName(fontName as CFString, size, nil)
            let attrs: [CFString: Any] = [kCTFontAttributeName: font]
            guard let attrStr = CFAttributedStringCreate(
                kCFAllocatorDefault, text as CFString, attrs as CFDictionary
            ) else { return 0 }
            return max(0, CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(attrStr), []).width)
        }
        let font    = CTFontCreateWithName(fontName as CFString, size, nil)
        let subFont = CTFontCreateWithName(fontName as CFString, size * 0.65, nil)
        let supFont = CTFontCreateWithName(fontName as CFString, size * 0.65, nil)
        let dummy   = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let line = attributedLine(
            segments: parse(text),
            font: font, subFont: subFont, supFont: supFont,
            size: size, color: dummy
        )
        return max(0, CTLineGetBoundsWithOptions(line, []).width)
    }

    // MARK: - Private helpers

    private static func attributedLine(
        segments: [MathMarkupSegment],
        font: CTFont,
        subFont: CTFont,
        supFont: CTFont,
        size: CGFloat,
        color: CGColor
    ) -> CTLine {
        let result = NSMutableAttributedString()
        for segment in segments {
            switch segment {
            case .base(let s):
                result.append(NSAttributedString(string: s, attributes: [
                    NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font,
                    NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): color,
                ]))
            case .sub(let s):
                result.append(NSAttributedString(string: s, attributes: [
                    NSAttributedString.Key(rawValue: kCTFontAttributeName as String): subFont,
                    NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): color,
                    .baselineOffset: NSNumber(value: -size * 0.20),
                ]))
            case .sup(let s):
                result.append(NSAttributedString(string: s, attributes: [
                    NSAttributedString.Key(rawValue: kCTFontAttributeName as String): supFont,
                    NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): color,
                    .baselineOffset: NSNumber(value: size * 0.30),
                ]))
            }
        }
        return CTLineCreateWithAttributedString(result)
    }

    private static func plainLine(text: String, fontName: String, size: CGFloat, color: CGColor) -> CTLine {
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
        let attrStr = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attrs as CFDictionary)!
        return CTLineCreateWithAttributedString(attrStr)
    }
}
