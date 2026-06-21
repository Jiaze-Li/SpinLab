import CoreGraphics
import Foundation
import Testing
@testable import SpinLabApp

@Suite("MathMarkupRenderer")
struct MathMarkupRendererTests {

    // MARK: - parse (linear segments, backward-compatible)

    @Test("math: prefix detection")
    func mathPrefixDetected() {
        #expect(MathMarkupRenderer.isMathLabel("math:σ_{xx}^{2}"))
        #expect(MathMarkupRenderer.isMathLabel("math:"))
        #expect(!MathMarkupRenderer.isMathLabel("σ_{xx}^{2}"))
    }

    @Test("extractMathMarkup strips the prefix")
    func extractMathMarkupStripsPrefix() {
        #expect(MathMarkupRenderer.extractMathMarkup("math:σ_{xx}^{2}") == "σ_{xx}^{2}")
        #expect(MathMarkupRenderer.extractMathMarkup("math:") == "")
    }

    @Test("E_{AHE}^{3ω} parses into base E, subscript AHE, superscript 3ω")
    func parseEAHE3omega() {
        let segments = MathMarkupRenderer.parse("E_{AHE}^{3ω}")
        #expect(segments == [.base("E"), .sub("AHE"), .sup("3ω")])
    }

    @Test("E_{AHE}^{3ω} parses into one atom with sub and sup")
    func parseAtomsEAHE3omegaAtom() {
        let nodes = MathMarkupRenderer.parseAtoms("E_{AHE}^{3ω}")
        #expect(nodes == [.atom(base: "E", sub: "AHE", sup: "3ω")])
    }

    @Test("renderer source contains no negative kern overlap logic")
    func rendererSourceContainsNoNegativeKernOverlapLogic() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent("Sources/SpinLabApp/Workbench/V3/MathMarkupRenderer.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        #expect(!source.contains("kern: -subW"))
        #expect(!source.contains("kern: -supW"))
        #expect(!source.contains("max(subW, supW)"))
        #expect(!source.contains("-subW"))
        #expect(!source.contains("-supW"))
    }

    @Test("E_{xx}^{3} parses correctly")
    func parseExx3() {
        let segments = MathMarkupRenderer.parse("E_{xx}^{3}")
        #expect(segments == [.base("E"), .sub("xx"), .sup("3")])
    }

    @Test("σ_{xx}^{2} parses correctly")
    func parseSigmaXX2() {
        let segments = MathMarkupRenderer.parse("σ_{xx}^{2}")
        #expect(segments == [.base("σ"), .sub("xx"), .sup("2")])
    }

    @Test("Full scaling-law y-axis label parses correctly")
    func parseScalingLawYLabel() {
        let segments = MathMarkupRenderer.parse("E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})")
        #expect(segments == [
            .base("E"), .sub("AHE"), .sup("3ω"),
            .base(" / (E"), .sub("xx"), .sup("3"),
            .base("·σ"), .sub("xx"),
            .base(") × 10"), .sup("2"),
            .base(" (Ω·μm"), .sup("3"),
            .base("·V"), .sup("-2"),
            .base(")"),
        ])
    }

    @Test("Plain label H (T) produces a single base segment")
    func parsePlainLabel() {
        let segments = MathMarkupRenderer.parse("H (T)")
        #expect(segments == [.base("H (T)")])
    }

    @Test("Plain label R (Ω) produces a single base segment")
    func parsePlainOmegaLabel() {
        let segments = MathMarkupRenderer.parse("R (Ω)")
        #expect(segments == [.base("R (Ω)")])
    }

    @Test("Empty string produces empty segments")
    func parseEmpty() {
        #expect(MathMarkupRenderer.parse("").isEmpty)
    }

    @Test("Backward-compatible single-char _X syntax still works")
    func parseSingleCharSubscript() {
        let segments = MathMarkupRenderer.parse("R_x")
        #expect(segments == [.base("R"), .sub("x")])
    }

    @Test("Backward-compatible single-char ^X syntax still works")
    func parseSingleCharSuperscript() {
        let segments = MathMarkupRenderer.parse("R^2")
        #expect(segments == [.base("R"), .sup("2")])
    }

    @Test("Trailing marker with no following character is treated as base text")
    func parseTrailingMarker() {
        let segments = MathMarkupRenderer.parse("R_")
        #expect(segments == [.base("R_")])
    }

    // MARK: - parseAtoms (atom-aware grouping)

    @Test("parseAtoms groups E_{AHE}^{3ω} into one atom")
    func parseAtomsEAHE3omega() {
        let nodes = MathMarkupRenderer.parseAtoms("E_{AHE}^{3ω}")
        #expect(nodes == [.atom(base: "E", sub: "AHE", sup: "3ω")])
    }

    @Test("parseAtoms groups E_{xx}^{3} into one atom")
    func parseAtomsExx3() {
        let nodes = MathMarkupRenderer.parseAtoms("E_{xx}^{3}")
        #expect(nodes == [.atom(base: "E", sub: "xx", sup: "3")])
    }

    @Test("parseAtoms groups σ_{xx}^{2} into one atom")
    func parseAtomsSigmaXX2() {
        let nodes = MathMarkupRenderer.parseAtoms("σ_{xx}^{2}")
        #expect(nodes == [.atom(base: "σ", sub: "xx", sup: "2")])
    }

    @Test("parseAtoms handles 10^{2} as atom with sup only")
    func parseAtoms10Sup2() {
        let nodes = MathMarkupRenderer.parseAtoms("10^{2}")
        #expect(nodes == [.atom(base: "10", sub: nil, sup: "2")])
    }

    @Test("parseAtoms handles V^{-2} as atom with sup only")
    func parseAtomsVMinus2() {
        let nodes = MathMarkupRenderer.parseAtoms("V^{-2}")
        #expect(nodes == [.atom(base: "V", sub: nil, sup: "-2")])
    }

    @Test("parseAtoms produces text node for plain label")
    func parseAtomsPlainLabel() {
        let nodes = MathMarkupRenderer.parseAtoms("H (T)")
        #expect(nodes == [.text("H (T)")])
    }

    @Test("parseAtoms backward-compatible single-char _X")
    func parseAtomsSingleCharSubscript() {
        let nodes = MathMarkupRenderer.parseAtoms("R_x")
        #expect(nodes == [.atom(base: "R", sub: "x", sup: nil)])
    }

    @Test("parseAtoms backward-compatible single-char ^X")
    func parseAtomsSingleCharSuperscript() {
        let nodes = MathMarkupRenderer.parseAtoms("R^2")
        #expect(nodes == [.atom(base: "R", sub: nil, sup: "2")])
    }

    @Test("parseAtoms groups full scaling-law label into correct atoms")
    func parseAtomsFullScalingLawLabel() {
        // Final scaling-law Y-axis label template
        let label = "E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})"
        let nodes = MathMarkupRenderer.parseAtoms(label)
        #expect(nodes == [
            .atom(base: "E",       sub: "AHE", sup: "3ω"),
            .atom(base: " / (E",   sub: "xx",  sup: "3"),
            .atom(base: "·σ",      sub: "xx",  sup: nil),
            .atom(base: ") × 10",  sub: nil,   sup: "2"),
            .atom(base: " (Ω·μm",  sub: nil,   sup: "3"),
            .atom(base: "·V",      sub: nil,   sup: "-2"),
            .text(")"),
        ])
    }

    // MARK: - containsMarkup

    @Test("containsMarkup returns true for strings with _ or ^")
    func containsMarkupDetectsMarkers() {
        #expect(MathMarkupRenderer.containsMarkup("E_{xx}^{3}"))
        #expect(MathMarkupRenderer.containsMarkup("σ_xx"))
        #expect(MathMarkupRenderer.containsMarkup("R^2"))
    }

    @Test("containsMarkup returns false for plain strings")
    func containsMarkupReturnsFalseForPlain() {
        #expect(!MathMarkupRenderer.containsMarkup("H (T)"))
        #expect(!MathMarkupRenderer.containsMarkup("R (Ω)"))
        #expect(!MathMarkupRenderer.containsMarkup(""))
    }

    // MARK: - measuredWidth

    @Test("measuredWidth of empty string is zero")
    func measuredWidthEmpty() {
        let w = MathMarkupRenderer.measuredWidth(
            text: "", size: 20, fontName: WorkbenchChartStyle().fontName)
        #expect(w == 0)
    }

    @Test("measuredWidth of plain label is positive")
    func measuredWidthPlain() {
        let w = MathMarkupRenderer.measuredWidth(
            text: "H (T)", size: 20, fontName: WorkbenchChartStyle().fontName)
        #expect(w > 0)
    }

    @Test("measuredWidth of markup label is positive and less than naive character-count estimate")
    func measuredWidthMarkupIsSmaller() {
        let style = WorkbenchChartStyle()
        let markupLabel = "E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})"
        let markupWidth = MathMarkupRenderer.measuredWidth(
            text: markupLabel, size: 20, fontName: style.fontName)
        #expect(markupWidth > 0)
        let rawWidth = MathMarkupRenderer.measuredWidth(
            text: markupLabel.replacingOccurrences(of: "_{", with: "_")
                              .replacingOccurrences(of: "^{", with: "^")
                              .replacingOccurrences(of: "}", with: ""),
            size: 20, fontName: style.fontName)
        #expect(markupWidth <= rawWidth + 1)
    }

    @Test("measuredWidth grows with longer markup label")
    func measuredWidthGrowsWithLength() {
        let style = WorkbenchChartStyle()
        let short = MathMarkupRenderer.measuredWidth(
            text: "σ_{xx}", size: 20, fontName: style.fontName)
        let long = MathMarkupRenderer.measuredWidth(
            text: "E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})", size: 20, fontName: style.fontName)
        #expect(long > short)
    }

    @Test("atom measuredWidth(E_{AHE}^{3ω}) leaves room for sub and sup spacing")
    func measuredWidthAtomLeavesRoomForSubAndSupSpacing() {
        let style = WorkbenchChartStyle()
        let atomWidth = MathMarkupRenderer.measuredWidth(
            text: "E_{AHE}^{3ω}", size: 20, fontName: style.fontName)
        let eW   = MathMarkupRenderer.measuredWidth(text: "E",    size: 20,        fontName: style.fontName)
        let subW = MathMarkupRenderer.measuredWidth(text: "AHE",  size: 20 * 0.65, fontName: style.fontName)
        let supW = MathMarkupRenderer.measuredWidth(text: "3ω", size: 20 * 0.65, fontName: style.fontName)
        #expect(atomWidth > eW + subW,
                "Atom width \(atomWidth) must exceed base+subscript width \(eW + subW)")
        #expect(atomWidth > eW + supW,
                "Atom width \(atomWidth) must exceed base+superscript width \(eW + supW)")
    }

    @Test("measuredWidth grows when superscript atom is followed by a delimiter")
    func measuredWidthAtomGrowsBeforeDelimiter() {
        let style = WorkbenchChartStyle()
        let atomWidth = MathMarkupRenderer.measuredWidth(
            text: "E_{AHE}^{3ω}", size: 20, fontName: style.fontName)
        let slashWidth = MathMarkupRenderer.measuredWidth(
            text: "E_{AHE}^{3ω}/", size: 20, fontName: style.fontName)
        #expect(slashWidth > atomWidth)
    }

    @Test("measuredWidth keeps a gap before grouped units")
    func measuredWidthKeepsGapBeforeUnits() {
        let style = WorkbenchChartStyle()
        let left = MathMarkupRenderer.measuredWidth(
            text: "σ_{x}^{2}(10^{7})", size: 20, fontName: style.fontName)
        let sigma = MathMarkupRenderer.measuredWidth(
            text: "σ_{x}^{2}", size: 20, fontName: style.fontName)
        let units = MathMarkupRenderer.measuredWidth(
            text: "(10^{7})", size: 20, fontName: style.fontName)
        #expect(left > sigma + units * 0.5)
    }

    @Test("atom measuredWidth(E_{xx}^{3}) leaves room for sub and sup spacing")
    func measuredWidthExx3AtomLeavesRoomForSubAndSupSpacing() {
        let style = WorkbenchChartStyle()
        let atomWidth = MathMarkupRenderer.measuredWidth(
            text: "E_{xx}^{3}", size: 20, fontName: style.fontName)
        let eW   = MathMarkupRenderer.measuredWidth(text: "E",  size: 20,        fontName: style.fontName)
        let subW = MathMarkupRenderer.measuredWidth(text: "xx", size: 20 * 0.65, fontName: style.fontName)
        let supW = MathMarkupRenderer.measuredWidth(text: "3",  size: 20 * 0.65, fontName: style.fontName)
        #expect(atomWidth > eW + subW,
                "Atom width \(atomWidth) must exceed base+subscript width \(eW + subW)")
        #expect(atomWidth > eW + supW,
                "Atom width \(atomWidth) must exceed base+superscript width \(eW + supW)")
    }

    // MARK: - Rotated Y-axis label footprint regression

    @Test("New-syntax scaling-law Y label does not inflate requiredLeftPadding beyond line height")
    func newSyntaxScalingLawYLabelDoesNotInflatePadding() {
        let style = WorkbenchChartStyle()
        let shortLane = PlotAxisSpacingCalculator.yAxisLane(
            axisTitleText: "R(3ω) (Ω)",
            tickLabels: ["-1.0", "0.0", "1.0"],
            axisTitleFontSize: 25,
            axisTitleFontName: style.fontName,
            axisTitleBold: false,
            axisTitleBoldFontName: style.boldFontName,
            tickLabelFontSize: 24,
            tickLabelFontName: style.fontName,
            tickLabelBold: false,
            tickLabelBoldFontName: style.boldFontName,
            minimumAxisTitleLane: 24,
            titleToTickGap: 4,
            tickToPlotGap: 5,
            baseLeftPadding: 80
        )
        let longLane = PlotAxisSpacingCalculator.yAxisLane(
            axisTitleText: "math:E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})",
            tickLabels: ["-1.0", "0.0", "1.0"],
            axisTitleFontSize: 25,
            axisTitleFontName: style.fontName,
            axisTitleBold: false,
            axisTitleBoldFontName: style.boldFontName,
            tickLabelFontSize: 24,
            tickLabelFontName: style.fontName,
            tickLabelBold: false,
            tickLabelBoldFontName: style.boldFontName,
            minimumAxisTitleLane: 24,
            titleToTickGap: 4,
            tickToPlotGap: 5,
            baseLeftPadding: 80
        )
        #expect(longLane.axisTitleTextWidth > shortLane.axisTitleTextWidth,
                "Scaling-law label must have greater text width than short label (precondition)")
        #expect(abs(longLane.requiredLeftPadding - shortLane.requiredLeftPadding) < 4,
                "requiredLeftPadding must not grow with Y title text length")
        #expect(longLane.axisTitleLaneWidth < longLane.axisTitleTextWidth,
                "axisTitleLaneWidth must be smaller than text width for a rotated title")
    }

    @Test("New-syntax scaling-law Y label does not collapse plotRect on 800 px canvas")
    func newSyntaxScalingLawYLabelDoesNotCollapsePlotRect() {
        let style = WorkbenchChartStyle()
        let payload = WorkbenchPlotPayload(
            workflowID: "scaling",
            workflowDisplayName: "Scaling",
            title: "Scaling Law",
            axisMapping: WorkbenchAxisMapping(
                xField: "σ_{xx}^{2}",
                yField: "math:E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})"
            ),
            series: [
                WorkbenchPlotSeries(
                    label: "Series A",
                    x: [1.0, 2.0, 3.0],
                    y: [0.1, 0.2, 0.15],
                    pointLabels: ["p0", "p1", "p2"]
                )
            ]
        )
        var opts = WorkbenchChartRenderer.Options()
        opts.width = 800
        opts.height = 600
        let resolved = WorkbenchChartRenderer().resolvedOptions(payload: payload, base: opts, style: style)
        let plan = PlotAxisLayoutPlan.compute(options: resolved, payload: payload, style: style)

        #expect(plan.plotRect.minX <= 220,
                "plotRect.minX must stay ≤ 220 px on an 800 px canvas with new-syntax Y label (got \(plan.plotRect.minX))")
        #expect(plan.plotRect.width > 400,
                "plotRect.width must exceed 400 px on an 800 px canvas (got \(plan.plotRect.width))")
    }
}
