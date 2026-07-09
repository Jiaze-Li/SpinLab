import Foundation
import Testing
@testable import SpinLabApp

/// v5.6.6 — AHE y-axis vocabulary alignment + ordinary-Hall linear background correction.
///
/// Prior to this suite, AHE's rendered y-axis was a plain AHE-local `"R_H (Ω)"` string
/// (`AHEAxisDetector.displayYField`), never routed through
/// `WorkbenchPlotDisplayVocabulary`'s math-markup rendering path the way 3ω's
/// `R_AHE^{1ω}`/`R_AHE^{3ω}` axis labels are (`ThreeOmegaPlotRenderer.rAHE1AxisLabel`, built
/// with `context: .plotAxis`). AHE also plotted/extracted the raw Hall-resistance signal
/// directly, with no ordinary-Hall (linear-in-H) background subtraction — unlike 3ω, which
/// already performs this via `ThreeOmegaFitUseCase._subtractLinearBackground` before fitting
/// R_AHE^{1ω}.
///
/// This suite locks in the fix: `BuildAHEPlotPayloadUseCase` now applies
/// `AHEBackgroundCorrectionUseCase` (built on the shared `LinearBackgroundCorrection`, the same
/// formula 3ω uses) before stacking/gap and unit conversion, and its y-axis label comes from
/// `WorkbenchPlotDisplayVocabulary.label(for: .raheCombined, context:)` — the same vocabulary
/// enum as 3ω's harmonic-resolved R_AHE cases, distinguished only by AHE having no harmonic to
/// tag. Extraction (`ExtractAHEMetricsUseCase`) reads the same corrected series, never the raw
/// or stacked/display-offset one.
@Suite("v5.6.6 - AHE ordinary Hall background correction + y-label vocabulary")
struct V566AHEOrdinaryHallCorrectionTests {

    // MARK: - Y label no longer plain "R_H (Ω)"

    @Test("AHE display payload y label is the math-markup R_AHE vocabulary label, not plain R_H")
    func displayYLabelUsesMathMarkupRAHE() {
        let ingestion = makeIngestion(xTesla: [-1, -0.5, 0, 0.5, 1], y: [-5, -5, 0, 5, 5])
        let payloads = BuildAHEPlotPayloadUseCase().executePayloads(ingestion: ingestion, title: "AHE Test")

        #expect(payloads.displayPayload.axisMapping.yField == WorkbenchPlotDisplayVocabulary.label(for: .raheCombined, context: .plotAxis))
        #expect(payloads.displayPayload.axisMapping.yField != "R_H (\u{03A9})")
    }

    @Test("AHE manifest payload y label is the plain-text R_AHE vocabulary label, not plain R_H")
    func manifestYLabelUsesPlainTextRAHE() {
        let ingestion = makeIngestion(xTesla: [-1, -0.5, 0, 0.5, 1], y: [-5, -5, 0, 5, 5])
        let payloads = BuildAHEPlotPayloadUseCase().executePayloads(ingestion: ingestion, title: "AHE Test")

        #expect(payloads.manifestPayload.axisMapping.yField == WorkbenchPlotDisplayVocabulary.label(for: .raheCombined, context: .manifestPlainText))
        #expect(payloads.manifestPayload.axisMapping.yField != "R_H (\u{03A9})")
    }

    @Test("AHE and 3ω R_AHE labels come from the same WorkbenchPlotDisplayVocabulary quantity family")
    func aheAnd3omegaShareVocabulary() {
        let ahe = WorkbenchPlotDisplayVocabulary.label(for: .raheCombined, context: .plotAxis)
        let threeOmega1 = ThreeOmegaPlotRenderer.rAHE1AxisLabel
        // Both are "math:R_{AHE...} (Ω)" shaped, sourced from the same vocabulary enum —
        // distinct cases (raheCombined vs rahe1omega) because AHE has no harmonic to tag.
        #expect(ahe.hasPrefix("math:R_{AHE"))
        #expect(threeOmega1.hasPrefix("math:R_{AHE"))
    }

    // MARK: - μ₀H x label still unit-aware (unaffected by this fix)

    @Test("AHE x label still auto-selects magnetic field unit by magnitude")
    func xLabelStillUnitAware() {
        let small = makeIngestion(xTesla: [-0.05, 0, 0.05], y: [-1, 0, 1])
        let large = makeIngestion(xTesla: [-7, 0, 7], y: [-1, 0, 1])

        #expect(BuildAHEPlotPayloadUseCase().execute(ingestion: small, title: "T").axisMapping.xField == "μ₀H (mT)")
        #expect(BuildAHEPlotPayloadUseCase().execute(ingestion: large, title: "T").axisMapping.xField == "μ₀H (T)")
    }

    // MARK: - Manual y-label override still wins

    @Test("manual y label override still takes priority over the default vocabulary label")
    func manualOverrideStillWins() throws {
        let ingestion = makeIngestion(xTesla: [-1, -0.5, 0, 0.5, 1], y: [-5, -5, 0, 5, 5])
        var input = WorkbenchRenderPipeline.Input(
            payload: BuildAHEPlotPayloadUseCase().executePayloads(ingestion: ingestion, title: "T").displayPayload
        )
        input.yLabelOverride = "Custom Y"
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.layout.yAxisLabel == "Custom Y")
    }

    // MARK: - Ordinary Hall background correction

    @Test("linear background is removed: high-field slope of corrected series is ~0")
    func correctionRemovesHighFieldSlope() {
        // Synthetic AHE loop: step function (±5 Ω) plus a strong linear-in-H background (20·H).
        let H = stride(from: -1.0, through: 1.0, by: 0.1).map { $0 }
        let y = H.map { h -> Double in
            let step: Double = h >= 0 ? 5.0 : -5.0
            return step + 20.0 * h
        }
        let series = WorkbenchPlotSeries(label: "S", x: H, y: y, sourceRef: "/tmp/a.csv", sampleID: "s1")
        let corrected = AHEBackgroundCorrectionUseCase().correctedSeries([series])[0]

        // High-field slope of the corrected series should be close to zero.
        let highField = zip(H, corrected.y).filter { abs($0.0) > 0.7 }
        let posSlope = LinearBackgroundCorrection.linearSlopeAndIntercept(
            x: highField.filter { $0.0 > 0 }.map(\.0), y: highField.filter { $0.0 > 0 }.map(\.1)
        )?.0 ?? .infinity
        #expect(abs(posSlope) < 1.0)
    }

    @Test("R_AHE metric extracted from corrected series is not contaminated by linear background")
    func metricNotContaminatedByBackground() throws {
        let H = stride(from: -1.0, through: 1.0, by: 0.05).map { $0 }
        let yStepOnly = H.map { $0 >= 0 ? 5.0 : -5.0 }
        let yWithBackground = zip(H, yStepOnly).map { $0.1 + 20.0 * $0.0 }

        let cleanSeries = WorkbenchPlotSeries(label: "S", x: H, y: yStepOnly, sourceRef: "/tmp/a.csv", sampleID: "s1")
        let contaminatedSeries = WorkbenchPlotSeries(label: "S", x: H, y: yWithBackground, sourceRef: "/tmp/a.csv", sampleID: "s1")

        let (_, rAHEClean) = ExtractAHEMetricsUseCase.extractSingleSeriesMetrics(cleanSeries)
        let corrected = AHEBackgroundCorrectionUseCase().correctedSeries([contaminatedSeries])[0]
        let (_, rAHECorrected) = ExtractAHEMetricsUseCase.extractSingleSeriesMetrics(corrected)

        #expect(abs(rAHECorrected - rAHEClean) < 0.5)
    }

    @Test("stack/gap display offset does not affect the corrected extraction metric")
    func stackGapDoesNotAffectExtraction() throws {
        let H = stride(from: -1.0, through: 1.0, by: 0.05).map { $0 }
        let y1 = H.map { h -> Double in (h >= 0 ? 5.0 : -5.0) + 20.0 * h }
        let y2 = H.map { h -> Double in (h >= 0 ? 5.0 : -5.0) + 20.0 * h + 50.0 }
        let series1 = WorkbenchPlotSeries(label: "S1", x: H, y: y1, sourceRef: "/tmp/a.csv", sampleID: "s1")
        let series2 = WorkbenchPlotSeries(label: "S2", x: H, y: y2, sourceRef: "/tmp/b.csv", sampleID: "s2")
        let ingestion = AHEIngestionResult(
            defaultAxisMapping: WorkbenchAxisMapping(xField: AHEAxisDetector.displayXField, yField: AHEAxisDetector.displayYField),
            series: [series1, series2], sourceFiles: ["/tmp/a.csv", "/tmp/b.csv"], warnings: []
        )

        let correctedSeries = AHEBackgroundCorrectionUseCase().correctedSeries(ingestion.series)
        let (_, rAHEUnstacked) = ExtractAHEMetricsUseCase.extractSingleSeriesMetrics(correctedSeries[0])

        let stackedPayloads = BuildAHEPlotPayloadUseCase().executePayloads(
            ingestion: ingestion, title: "T", stackOffsetMultiplier: 5.0, minGapFraction: 0.15
        )
        // Stacking must actually shift the display series (sanity check the fixture forces it),
        // yet extraction still reads the unstacked corrected series.
        #expect(stackedPayloads.displayPayload.series.first?.y != correctedSeries[0].y)
        #expect(abs(rAHEUnstacked - 5.0) < 0.5)
    }

    // MARK: - Envelope high-field slope (up/down sweep segments)

    @Test("full hysteresis loop: envelope selects high/low segments by raw meanY and removes common slope")
    func envelopeLoopRemovesCommonBackgroundSlope() {
        // Full loop, scan order preserved: +1 -> -1 (down-sweep) -> +1 (up-sweep).
        let down = stride(from: 1.0, through: -1.0, by: -0.1).map { $0 }
        let up = stride(from: -1.0, through: 1.0, by: 0.1).map { $0 }
        let H = down + up
        let y = H.map { h -> Double in (h >= 0 ? 5.0 : -5.0) + 20.0 * h }
        let series = WorkbenchPlotSeries(label: "loop", x: H, y: y, sourceRef: "/tmp/a.csv", sampleID: "s1")

        let (corrected, diagnostics) = AHEBackgroundCorrectionUseCase().correctedSeriesWithDiagnostics([series])
        let diag = diagnostics[0]

        #expect(!diag.fallback)
        #expect(diag.selectedHighSegment == "posDown" || diag.selectedHighSegment == "posUp")
        #expect(diag.selectedLowSegment == "negDown" || diag.selectedLowSegment == "negUp")
        #expect(abs(diag.backgroundSlope - 20.0) < 0.5)
        #expect(diag.slopeDisagreement < 0.1)

        let highField = zip(H, corrected[0].y).filter { abs($0.0) > 0.8 }
        let residual = highField.map { abs($0.1 - ($0.0 >= 0 ? 5.0 : -5.0)) }.max() ?? .infinity
        #expect(residual < 0.5)
    }

    @Test("envelope falls back to branch-sign method when fewer than two segments qualify")
    func envelopeFallsBackWithSparseHighField() {
        // Only 5 points total, all monotonic (single sweep direction), so only 2 of the
        // 4 candidate segments can ever be populated — but with a strict minSegmentPoints
        // requirement and a tiny high-field region, neither reaches the minimum.
        let H = [-1.0, -0.5, 0.0, 0.5, 1.0]
        let y = H.map { $0 >= 0 ? 5.0 + 20.0 * $0 : -5.0 + 20.0 * $0 }
        let series = WorkbenchPlotSeries(label: "sparse", x: H, y: y, sourceRef: "/tmp/a.csv", sampleID: "s1")

        let (_, diagnostics) = AHEBackgroundCorrectionUseCase(minSegmentPoints: 3)
            .correctedSeriesWithDiagnostics([series])

        #expect(diagnostics[0].fallback)
    }

    // MARK: - Fixtures

    private func makeIngestion(xTesla: [Double], y: [Double]) -> AHEIngestionResult {
        let series = WorkbenchPlotSeries(
            label: "300 K", x: xTesla, y: y,
            sourceRef: "/tmp/ahe.csv", sampleID: "sample-ahe"
        )
        return AHEIngestionResult(
            defaultAxisMapping: WorkbenchAxisMapping(xField: AHEAxisDetector.displayXField, yField: AHEAxisDetector.displayYField),
            series: [series],
            sourceFiles: ["/tmp/ahe.csv"],
            warnings: []
        )
    }
}
