import Foundation

/// Removes the ordinary-Hall linear-in-H background from raw AHE Hall-resistance series,
/// isolating the anomalous Hall signal R_AHE(H).
///
/// Background slope comes from `EnvelopeBackgroundSlope`: the two high-field segments
/// (out of {+H up-sweep, +H down-sweep, -H up-sweep, -H down-sweep}) with the largest and
/// smallest raw mean(y) are each fit independently, and their slopes averaged into one
/// common `backgroundSlope` — not a plain positive/negative branch-sign split. Falls back
/// to the previous branch-sign-only method (`LinearBackgroundCorrection`) when fewer than
/// two candidate segments have enough points.
///
/// Must run before any display-only transform (stacking/gap offset, unit conversion) so that
/// downstream extraction (`ExtractAHEMetricsUseCase`) and the plotted series both read the
/// same corrected signal — never a stacked/display-offset one.
struct AHEBackgroundCorrectionUseCase {
    var highFrac: Double = 0.80
    var minSegmentPoints: Int = 3
    var fallbackHighFrac: Double = 0.70
    var fallbackMinHighFieldPoints: Int = 3

    func correctedSeries(_ series: [WorkbenchPlotSeries]) -> [WorkbenchPlotSeries] {
        correctedSeriesWithDiagnostics(series).series
    }

    func correctedSeriesWithDiagnostics(
        _ series: [WorkbenchPlotSeries]
    ) -> (series: [WorkbenchPlotSeries], diagnostics: [EnvelopeBackgroundSlope.Diagnostics]) {
        var diagnostics: [EnvelopeBackgroundSlope.Diagnostics] = []
        let corrected = series.map { s -> WorkbenchPlotSeries in
            let result = EnvelopeBackgroundSlope.apply(
                H: s.x,
                R: s.y,
                seriesLabel: s.label,
                highFrac: highFrac,
                minSegmentPoints: minSegmentPoints,
                fallbackHighFrac: fallbackHighFrac,
                fallbackMinHighFieldPoints: fallbackMinHighFieldPoints
            )
            diagnostics.append(result.diagnostics)
            var corrected = s
            corrected.y = result.correctedY
            return corrected
        }
        return (corrected, diagnostics)
    }
}
