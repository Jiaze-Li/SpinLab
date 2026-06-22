import CoreGraphics
import CoreText
import Foundation

/// Segment produced by parsing a math markup string.
enum MathMarkupSegment: Equatable {
    case base(String)
    case sub(String)
    case sup(String)
}

/// Atom-aware node produced by grouping parsed segments.
///
/// A `.text` node is a base with no sub/sup following it.
/// An `.atom` node groups a base with its subscript and/or superscript;
/// when both sub and sup are present, the subscript stays closest to the base
/// and the superscript is placed outward/rightward to avoid crowding long
/// subscripts such as `E_{AHE}^{3ω}`.
enum MathMarkupNode: Equatable {
    case text(String)
    case atom(base: String, sub: String?, sup: String?)
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
/// When both sub and sup are present on a base, the subscript stays closest to
/// the base and the superscript is placed outward/rightward to reduce collisions
/// for longer subscripts such as `E_{AHE}^{3ω}`.
struct MathMarkupRenderer {

    static let mathPrefix = "math:"

    static func containsMarkup(_ text: String) -> Bool {
        text.contains("_") || text.contains("^")
    }

    static func isMathLabel(_ text: String) -> Bool {
        text.hasPrefix(mathPrefix)
    }

    static func extractMathMarkup(_ text: String) -> String {
        String(text.dropFirst(mathPrefix.count))
    }

    /// Parses a markup string into a sequence of typed segments (linear model, backward-compatible).
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
                segments.append(isSub ? .sub(String(next)) : .sup(String(next)))
            }
        }
        flushBase()
        return segments
    }

    /// Groups linear segments into atom-aware nodes.
    ///
    /// Each base segment that is immediately followed by sub and/or sup segments
    /// becomes one `.atom`; a base with nothing following becomes `.text`.
    static func parseAtoms(_ text: String) -> [MathMarkupNode] {
        let segs = parse(text)
        var nodes: [MathMarkupNode] = []
        var i = 0
        while i < segs.count {
            switch segs[i] {
            case .base(let b):
                var sub: String? = nil
                var sup: String? = nil
                var j = i + 1
                outer: while j < segs.count {
                    switch segs[j] {
                    case .sub(let s) where sub == nil:
                        sub = s; j += 1
                    case .sup(let u) where sup == nil:
                        sup = u; j += 1
                    default:
                        break outer
                    }
                }
                nodes.append(sub == nil && sup == nil
                    ? .text(b)
                    : .atom(base: b, sub: sub, sup: sup))
                i = j
            case .sub(let s):
                nodes.append(.atom(base: "", sub: s, sup: nil))
                i += 1
            case .sup(let u):
                nodes.append(.atom(base: "", sub: nil, sup: u))
                i += 1
            }
        }
        return nodes
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
        return attributedLineFromAtoms(
            nodes: parseAtoms(text),
            font: font, subFont: subFont, supFont: supFont,
            size: size, color: color
        )
    }

    /// Returns the rendered width of a markup string in the given font at the given size.
    ///
    /// Uses the same atom-aware attributed-string construction as rendering so the
    /// measured width matches the drawn line.
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
        let line = attributedLineFromAtoms(
            nodes: parseAtoms(text),
            font: font, subFont: subFont, supFont: supFont,
            size: size, color: dummy
        )
        return max(0, CTLineGetBoundsWithOptions(line, []).width)
    }

    // MARK: - Private helpers

    /// Builds a CTLine from atom-aware nodes.
    ///
    /// For atoms with both sub and sup, the subscript is placed immediately after
    /// the base and the superscript is placed outward/rightward with a small gap.
    private static func attributedLineFromAtoms(
        nodes: [MathMarkupNode],
        font: CTFont,
        subFont: CTFont,
        supFont: CTFont,
        size: CGFloat,
        color: CGColor
    ) -> CTLine {
        let result = NSMutableAttributedString()

        let baseAttrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font,
            NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): color,
        ]
        let scriptPairGap = size * 0.06
        let scriptTrailingGap = size * 0.08

        func subAttrs() -> [NSAttributedString.Key: Any] {
            let d: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(rawValue: kCTFontAttributeName as String): subFont,
                NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): color,
                .baselineOffset: NSNumber(value: -size * 0.24),
            ]
            return d
        }

        func supAttrs(kern: CGFloat? = nil) -> [NSAttributedString.Key: Any] {
            var d: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(rawValue: kCTFontAttributeName as String): supFont,
                NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): color,
                .baselineOffset: NSNumber(value: size * 0.38),
            ]
            if let k = kern { d[.kern] = NSNumber(value: k) }
            return d
        }

        func appendScriptTrailingGap() {
            // Thin space keeps script atoms from crowding the following operator
            // or delimiter while still matching measured width.
            result.append(NSAttributedString(
                string: "\u{200A}",
                attributes: baseAttrs.merging([.kern: NSNumber(value: scriptTrailingGap)]) { _, new in new }
            ))
        }

        for node in nodes {
            switch node {
            case .text(let s):
                result.append(NSAttributedString(string: s, attributes: baseAttrs))

            case .atom(let base, let sub, let sup):
                if !base.isEmpty {
                    result.append(NSAttributedString(string: base, attributes: baseAttrs))
                }
                if let sub = sub, let sup = sup {
                    result.append(NSAttributedString(string: sub, attributes: subAttrs()))
                    result.append(NSAttributedString(string: sup, attributes: supAttrs(kern: scriptPairGap)))
                    appendScriptTrailingGap()
                } else if let sub = sub {
                    result.append(NSAttributedString(string: sub, attributes: subAttrs()))
                    appendScriptTrailingGap()
                } else if let sup = sup {
                    result.append(NSAttributedString(string: sup, attributes: supAttrs()))
                    appendScriptTrailingGap()
                }
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
