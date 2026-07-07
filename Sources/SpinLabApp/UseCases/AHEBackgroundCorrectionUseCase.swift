import Foundation

/// Removes the ordinary-Hall linear-in-H background from raw AHE Hall-resistance series,
/// isolating the anomalous Hall signal R_AHE(H). Same formula 3ω already applies to its
/// 1ω/3ω channels (`ThreeOmegaFitUseCase`), via the shared `LinearBackgroundCorrection`.
///
/// Must run before any display-only transform (stacking/gap offset, unit conversion) so that
/// downstream extraction (`ExtractAHEMetricsUseCase`) and the plotted series both read the
/// same corrected signal — never a stacked/display-offset one.
struct AHEBackgroundCorrectionUseCase {
    var highFrac: Double = 0.70
    var minHighFieldPoints: Int = 3

    func correctedSeries(_ series: [WorkbenchPlotSeries]) -> [WorkbenchPlotSeries] {
        series.map { s in
            var corrected = s
            corrected.y = LinearBackgroundCorrection.subtractLinearBackground(
                H: s.x, R: s.y, highFrac: highFrac, minHighFieldPoints: minHighFieldPoints
            )
            return corrected
        }
    }
}
