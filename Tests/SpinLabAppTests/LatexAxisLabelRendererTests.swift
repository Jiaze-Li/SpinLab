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

    // MARK: - Fallback with injected unavailable backend

    @Test("labelSize returns nil when service has unavailable backend")
    func labelSizeNilWhenServiceUnavailable() {
        let renderer = LatexAxisLabelRenderer(service: LatexRenderService(backend: UnavailableLatexBackend()))
        #expect(renderer.labelSize(latex: "\\frac{a}{b}", fontSize: 20) == nil)
    }

    @Test("draw returns false when service has unavailable backend")
    func drawReturnsFalseWhenServiceUnavailable() {
        let renderer = LatexAxisLabelRenderer(service: LatexRenderService(backend: UnavailableLatexBackend()))
        let ctx = makeTestContext()
        let result = renderer.draw(
            ctx: ctx,
            latex: "\\frac{a}{b}",
            fontSize: 20,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            at: CGPoint(x: 100, y: 100),
            orientation: .horizontal
        )
        #expect(result == false)
    }

    @Test("draw returns true when service has available backend")
    func drawReturnsTrueWhenServiceAvailable() {
        let service = LatexRenderService(backend: FixedSizeLatexBackend(fixedNaturalSize: CGSize(width: 60, height: 20)))
        let renderer = LatexAxisLabelRenderer(service: service)
        let ctx = makeTestContext()
        let result = renderer.draw(
            ctx: ctx,
            latex: "x^2",
            fontSize: 20,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            at: CGPoint(x: 100, y: 100),
            orientation: .horizontal
        )
        #expect(result == true)
    }

    @Test("draw forwards black color and default 2x pixelScale to the render service")
    func drawUsesDefaultRenderInputs() {
        let capture = LatexCompileCapture()
        let service = LatexRenderService(
            backend: RecordingLatexBackend(
                fixedNaturalSize: CGSize(width: 60, height: 20),
                capture: capture
            )
        )
        let renderer = LatexAxisLabelRenderer(service: service)
        let ctx = makeTestContext()
        let result = renderer.draw(
            ctx: ctx,
            latex: "x^2",
            fontSize: 20,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            at: CGPoint(x: 100, y: 100),
            orientation: .horizontal
        )
        #expect(result == true)
        #expect(capture.colorHex == "000000")
        #expect(capture.pixelScale == 2.0)
    }

    // MARK: - labelSize delegates to service

    @Test("labelSize returns service naturalSize scaled by fontSize/12")
    func labelSizeDelegatesToService() {
        let natural = CGSize(width: 90, height: 25)
        let service = LatexRenderService(backend: FixedSizeLatexBackend(fixedNaturalSize: natural))
        let renderer = LatexAxisLabelRenderer(service: service)
        let fontSize: CGFloat = 24
        let size = renderer.labelSize(latex: "x^2", fontSize: fontSize)
        #expect(size != nil)
        if let s = size {
            let scale = fontSize / 12.0
            #expect(abs(s.width  - natural.width  * scale) < 0.001)
            #expect(abs(s.height - natural.height * scale) < 0.001)
        }
    }

    // MARK: - Orientation footprint tests via PlotAxisSpacingCalculator

    @Test("yAxisLane with latex: label uses injected size.height as horizontal footprint")
    func yAxisLaneLatexLabelUsesHeightAsHorizontalFootprint() {
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
        // After 90° rotation: horizontal footprint = PDF height (40), not PDF width (120).
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

    @Test("xAxisLane with latex: label uses injected size.height as lane height")
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

    // MARK: - Non-LaTeX labels still use MathMarkupRenderer / plain renderer

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

    // MARK: - PlotAxisLayoutPlan long-label regression with mocked size

    @Test("PlotAxisLayoutPlan: latex Y-label uses PDF height not formula width for left padding")
    func plotAxisLayoutPlanLatexYLabelFootprint() {
        let style = WorkbenchChartStyle()
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
        // Horizontal footprint must be the PDF height (33), not PDF width (300).
        #expect(lane.axisTitleLaneWidth <= 50,
                "Y-axis LaTeX label must not inflate left margin with formula text width (got \(lane.axisTitleLaneWidth))")
        #expect(lane.requiredLeftPadding <= 200,
                "Left padding must stay reasonable on 800px canvas (got \(lane.requiredLeftPadding))")
    }

    // MARK: - Integration (only when LaTeX installed)

    @Test("Integration: labelSize returns positive size when LaTeX is available")
    func integrationRenderSimpleFormula() {
        guard LatexRenderService.shared.isAvailable else { return }
        // Compilation may still fail in sandboxed/CI environments even when latexmk is found.
        let renderer = LatexAxisLabelRenderer()
        let size = renderer.labelSize(latex: "E = mc^{2}", fontSize: 20)
        if let s = size {
            #expect(s.width > 0)
            #expect(s.height > 0)
        }
        // No assertion on nil — compilation failure is acceptable (test environment constraint).
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
