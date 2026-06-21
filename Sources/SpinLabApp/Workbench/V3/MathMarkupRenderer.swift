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
/// both sub and sup attach at the same horizontal column after the base.
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
/// When both sub and sup are present on a base, they share the same x attachment column.
struct MathMarkupRenderer {

    static func containsMarkup(_ text: String) -> Bool {
        text.contains("_") || text.contains("^")
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
    /// Uses atom-aware layout: combined sub+sup atoms contribute max(subWidth, supWidth)
    /// rather than subWidth + supWidth, matching the visual rendering.
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

    /// Width of a plain string in a given CTFont (no markup).
    private static func stringWidth(_ text: String, font: CTFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let attrs: [CFString: Any] = [kCTFontAttributeName: font]
        guard let attrStr = CFAttributedStringCreate(
            kCFAllocatorDefault, text as CFString, attrs as CFDictionary
        ) else { return 0 }
        return max(0, CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(attrStr), []).width)
    }

    /// Builds a CTLine from atom-aware nodes.
    ///
    /// For atoms with both sub and sup, the narrower element is appended first and the
    /// wider element is given kern = -(narrowerWidth) so that both start at the same
    /// x column after the base.  The resulting typographic width equals
    /// baseWidth + max(subWidth, supWidth).
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

        func subAttrs(kern: CGFloat? = nil) -> [NSAttributedString.Key: Any] {
            var d: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(rawValue: kCTFontAttributeName as String): subFont,
                NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): color,
                .baselineOffset: NSNumber(value: -size * 0.20),
            ]
            if let k = kern { d[.kern] = NSNumber(value: k) }
            return d
        }

        func supAttrs(kern: CGFloat? = nil) -> [NSAttributedString.Key: Any] {
            var d: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(rawValue: kCTFontAttributeName as String): supFont,
                NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): color,
                .baselineOffset: NSNumber(value: size * 0.30),
            ]
            if let k = kern { d[.kern] = NSNumber(value: k) }
            return d
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
                    let subW = stringWidth(sub, font: subFont)
                    let supW = stringWidth(sup, font: supFont)
                    // Narrower first (no kern), wider second with kern = -narrowerWidth.
                    // This aligns both at the same x column and makes the typographic
                    // advance equal to max(subW, supW).
                    if supW >= subW {
                        result.append(NSAttributedString(string: sub, attributes: subAttrs()))
                        result.append(NSAttributedString(string: sup, attributes: supAttrs(kern: -subW)))
                    } else {
                        result.append(NSAttributedString(string: sup, attributes: supAttrs()))
                        result.append(NSAttributedString(string: sub, attributes: subAttrs(kern: -supW)))
                    }
                } else if let sub = sub {
                    result.append(NSAttributedString(string: sub, attributes: subAttrs()))
                } else if let sup = sup {
                    result.append(NSAttributedString(string: sup, attributes: supAttrs()))
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
