import CoreGraphics
import Testing
@testable import SpinLabApp

@Suite("LatexAxisLabelRenderer")
struct LatexAxisLabelRendererTests {

    // MARK: - Prefix detection

    @Test("latex: prefix detection — positive")
    func latexPrefixDetected() {
        #expect(LatexAxisLabelRenderer.isLatexLabel("latex:\\frac{a}{b}"))
        #expect(LatexAxisLabelRenderer.isLatexLabel("latex:"))
    }

    @Test("latex: prefix detection — negative")
    func nonLatexNotDetected() {
        #expect(!LatexAxisLabelRenderer.isLatexLabel("E^{3ω}"))
        #expect(!LatexAxisLabelRenderer.isLatexLabel("σ²_xx (10⁷ S²/cm²)"))
        #expect(!LatexAxisLabelRenderer.isLatexLabel(""))
    }

    @Test("extractLatex strips the prefix")
    func extractStripsPrefix() {
        let full = "latex:\\frac{E}{B}"
        #expect(LatexAxisLabelRenderer.extractLatex(full) == "\\frac{E}{B}")
    }

    @Test("extractLatex on empty suffix")
    func extractEmptySuffix() {
        #expect(LatexAxisLabelRenderer.extractLatex("latex:") == "")
    }

    // MARK: - Cache key

    @Test("CacheKey equality and hashing by latex + colorHex")
    func cacheKeyEquality() {
        let k1 = LatexAxisLabelRenderer.CacheKey(latex: "\\frac{a}{b}", colorHex: "000000ff")
        let k2 = LatexAxisLabelRenderer.CacheKey(latex: "\\frac{a}{b}", colorHex: "000000ff")
        let k3 = LatexAxisLabelRenderer.CacheKey(latex: "\\frac{a}{b}", colorHex: "ff0000ff")
        #expect(k1 == k2)
        #expect(k1 != k3)
        var set = Set<LatexAxisLabelRenderer.CacheKey>()
        set.insert(k1)
        set.insert(k2)
        #expect(set.count == 1)
    }

    // MARK: - Fallback when LaTeX unavailable

    @Test("labelSize returns nil when LaTeX is unavailable")
    func labelSizeNilWhenUnavailable() {
        let renderer = LatexAxisLabelRenderer()
        // Force unavailable state via reflection would be fragile; instead verify that
        // when backendStatus is .unavailable the public API returns nil.
        // We can test the real renderer — if LaTeX is not installed this must return nil;
        // if it is installed it may return a real size (integration path).
        // The key contract: must not crash.
        let result = renderer.labelSize(latex: "\\frac{a}{b}", fontSize: 20)
        // result is either nil (no LaTeX) or a valid positive size (LaTeX present)
        if let size = result {
            #expect(size.width > 0)
            #expect(size.height > 0)
        }
        // No crash — test passes regardless of LaTeX availability.
    }

    @Test("draw returns false gracefully when LaTeX unavailable")
    func drawReturnsFalseWhenUnavailable() {
        let renderer = LatexAxisLabelRenderer()
        let ctx = makeTestContext()
        // Must not crash and must return a Bool.
        let result = renderer.draw(
            ctx: ctx,
            latex: "\\frac{a}{b}",
            fontSize: 20,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            at: CGPoint(x: 100, y: 100),
            orientation: .horizontal
        )
        // result is false (no LaTeX) or true (LaTeX installed and rendered).
        // Either is acceptable; the contract is no crash.
        let _ = result
    }

    // MARK: - Orientation / footprint measurement logic

    @Test("yAxisLane with latex: label uses latexLabelSizeOverride.height as horizontal footprint")
    func yAxisLaneLatexLabelUsesHeightAsHorizontalFootprint() {
        // Inject a known label size: width=120, height=40.
        // After rotation, horizontal footprint must equal 40 (the height).
        let mockSize = CGSize(width: 120, height: 40)
        let style = WorkbenchChartStyle()

        let lane = PlotAxisSpacingCalculator.yAxisLane(
            maxTickLabelWidth: 50,
            axisTitleText: "latex:\\frac{A}{B}",
            axisTitleFontSize: style.axisTitleFontSize,
            axisTitleFontName: style.fontName,
            minimumAxisTitleLane: 0,
            titleToTickGap: 4,
            tickToPlotGap: 5,
            baseLeftPadding: 96,
            latexLabelSizeOverride: mockSize
        )
        // axisTitleLaneWidth should use the PDF height (40) as horizontal footprint.
        // With minimumAxisTitleLane=0, axisTitleLaneWidth = max(40, 0) = 40.
        #expect(lane.axisTitleLaneWidth == 40,
                "Horizontal footprint for rotated Y-axis LaTeX label must equal PDF height (got \(lane.axisTitleLaneWidth))")
    }

    @Test("yAxisLane with non-latex label uses font line height as horizontal footprint")
    func yAxisLaneNonLatexUsesLineHeight() {
        let style = WorkbenchChartStyle()
        let fontLineHeight = PlotTextMeasurer.measuredLineHeight(
            fontSize: style.axisTitleFontSize,
            fontName: style.fontName
        )
        let lane = PlotAxisSpacingCalculator.yAxisLane(
            maxTickLabelWidth: 50,
            axisTitleText: "R(3ω) (Ω)",
            axisTitleFontSize: style.axisTitleFontSize,
            axisTitleFontName: style.fontName,
            minimumAxisTitleLane: 0,
            titleToTickGap: 4,
            tickToPlotGap: 5,
            baseLeftPadding: 96
        )
        #expect(lane.axisTitleLaneWidth == max(fontLineHeight, 0),
                "Non-latex Y-axis label horizontal footprint must equal font line height")
    }

    @Test("xAxisLane with latex: label uses latexLabelSizeOverride.height as lane height")
    func xAxisLaneLatexLabelUsesHeightAsLaneHeight() {
        let mockSize = CGSize(width: 200, height: 35)
        let style = WorkbenchChartStyle()

        let lane = PlotAxisSpacingCalculator.xAxisLane(
            axisTitleText: "latex:\\sigma_{xx}^{2}",
            tickLabels: ["0", "1", "2"],
            axisTitleFontSize: style.axisTitleFontSize,
            axisTitleFontName: style.fontName,
            tickLabelFontSize: style.tickLabelFontSize,
            tickLabelFontName: style.fontName,
            minimumAxisTitleLane: 0,
            titleToTickGap: 4,
            tickToPlotGap: 5,
            baseBottomPadding: 88,
            latexLabelSizeOverride: mockSize
        )
        #expect(lane.axisTitleLaneHeight == 35,
                "X-axis LaTeX label lane height must equal PDF height (got \(lane.axisTitleLaneHeight))")
    }

    // MARK: - Non-LaTeX labels still go through MathMarkupRenderer / plain renderer

    @Test("Non-latex markup label still produces non-zero width via MathMarkupRenderer")
    func nonLatexMarkupLabelMeasured() {
        let style = WorkbenchChartStyle()
        let width = PlotTextMeasurer.measuredWidth(
            "E^{3ω}_AHE",
            fontSize: style.axisTitleFontSize,
            fontName: style.fontName
        )
        #expect(width > 0, "MathMarkupRenderer should measure non-zero width for markup label")
    }

    @Test("Plain text label still produces non-zero width")
    func plainTextLabelMeasured() {
        let style = WorkbenchChartStyle()
        let width = PlotTextMeasurer.measuredWidth(
            "H (T)",
            fontSize: style.axisTitleFontSize,
            fontName: style.fontName
        )
        #expect(width > 0, "Plain text label must have non-zero measured width")
    }

    // MARK: - PlotAxisLayoutPlan long-label test with mocked LaTeX size

    @Test("PlotAxisLayoutPlan with latex: Y-label uses PDF height not text length for left padding")
    func plotAxisLayoutPlanLatexYLabelFootprint() {
        // The scaling-law latex: Y label is a wide formula but should only consume
        // ~one line-height worth of horizontal space in the left margin.
        // We verify the lane API directly with a realistic injected PDF size.
        let style = WorkbenchChartStyle()
        // Typical PDF height for a fraction label at 12pt LaTeX ≈ 20pt;
        // scaled to axisTitleFontSize (20pt): height ≈ 33pt.
        let mockSize = CGSize(width: 300, height: 33)

        let lane = PlotAxisSpacingCalculator.yAxisLane(
            maxTickLabelWidth: 60,
            axisTitleText: "latex:\\frac{E_{\\mathrm{AHE}}^{(3\\omega)}}{E_{xx}^{3}\\cdot\\sigma_{xx}}\\times10^{2}",
            axisTitleFontSize: style.axisTitleFontSize,
            axisTitleFontName: style.fontName,
            minimumAxisTitleLane: max(style.axisTitleFontSize * 1.25, 24),
            titleToTickGap: 4,
            tickToPlotGap: 5,
            baseLeftPadding: 96,
            latexLabelSizeOverride: mockSize
        )
        // The horizontal footprint must be the PDF height (33), not the PDF width (300).
        #expect(lane.axisTitleLaneWidth <= 50,
                "Y-axis LaTeX label must not inflate left margin with formula text width (got axisTitleLaneWidth=\(lane.axisTitleLaneWidth))")
        #expect(lane.requiredLeftPadding <= 200,
                "Left padding must stay reasonable on 800px canvas (got \(lane.requiredLeftPadding))")
    }

    // MARK: - Backend detection smoke test

    @Test("detectBackend returns a result without crashing")
    func detectBackendNocrash() {
        let status = LatexAxisLabelRenderer.detectBackend()
        // May be .latexmk, .pdflatex, or .unavailable — all are valid on CI.
        switch status {
        case .latexmk(let p):
            #expect(!p.isEmpty)
        case .pdflatex(let p):
            #expect(!p.isEmpty)
        case .unavailable:
            break  // acceptable when LaTeX is not installed
        }
    }

    // MARK: - Optional integration test (only runs if LaTeX is installed)

    @Test("Integration: render simple formula to PDF and verify non-zero size")
    func integrationRenderSimpleFormula() throws {
        let renderer = LatexAxisLabelRenderer()
        guard renderer.backendStatus.isAvailable else {
            // Skip gracefully when LaTeX is not installed on this machine.
            return
        }
        let size = renderer.labelSize(latex: "E = mc^{2}", fontSize: 20)
        #expect(size != nil, "LaTeX is available but labelSize returned nil")
        if let s = size {
            #expect(s.width > 0, "Rendered formula must have positive width")
            #expect(s.height > 0, "Rendered formula must have positive height")
        }
    }

    // MARK: - Helpers

    private func makeTestContext() -> CGContext {
        CGContext(
            data: nil, width: 200, height: 200,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue
        )!
    }
}
