import CoreGraphics
import Testing
@testable import SpinLabApp

@Suite("MathMarkupRenderer")
struct MathMarkupRendererTests {

    // MARK: - Parse

    @Test("E_{AHE}^{(3ω)} parses into base E, subscript AHE, superscript (3ω)")
    func parseEAHE3omega() {
        let segments = MathMarkupRenderer.parse("E_{AHE}^{(3ω)}")
        #expect(segments == [.base("E"), .sub("AHE"), .sup("(3ω)")])
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
        let segments = MathMarkupRenderer.parse("E_{AHE}^{(3ω)} / (E_{xx}^{3} · σ_{xx})")
        #expect(segments == [
            .base("E"), .sub("AHE"), .sup("(3ω)"),
            .base(" / (E"), .sub("xx"), .sup("3"),
            .base(" · σ"), .sub("xx"),
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
        let markupLabel = "E_{AHE}^{(3ω)} / (E_{xx}^{3} · σ_{xx})"
        let markupWidth = MathMarkupRenderer.measuredWidth(
            text: markupLabel, size: 20, fontName: style.fontName)
        // The markup width should be positive.
        #expect(markupWidth > 0)
        // The markup width must be less than the raw string width (markup chars inflating count).
        let rawWidth = MathMarkupRenderer.measuredWidth(
            text: markupLabel.replacingOccurrences(of: "_{", with: "_")
                              .replacingOccurrences(of: "^{", with: "^")
                              .replacingOccurrences(of: "}", with: ""),
            size: 20, fontName: style.fontName)
        // Markup-aware width must not exceed the raw string width.
        #expect(markupWidth <= rawWidth + 1)
    }

    @Test("measuredWidth grows with longer markup label")
    func measuredWidthGrowsWithLength() {
        let style = WorkbenchChartStyle()
        let short = MathMarkupRenderer.measuredWidth(
            text: "σ_{xx}", size: 20, fontName: style.fontName)
        let long = MathMarkupRenderer.measuredWidth(
            text: "E_{AHE}^{(3ω)} / (E_{xx}^{3} · σ_{xx})", size: 20, fontName: style.fontName)
        #expect(long > short)
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
            axisTitleText: "E_{AHE}^{(3ω)} / (E_{xx}^{3} · σ_{xx})",
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
                yField: "E_{AHE}^{(3ω)} / (E_{xx}^{3} · σ_{xx})"
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
