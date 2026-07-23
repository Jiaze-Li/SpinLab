import Foundation

// MARK: - IVAngularFitAdapter
//
// IV-owned glue between the generic AngularFit module and the Plot System's
// WorkbenchPlotSeriesOverlay contract. Mirrors the role IVPowerLawFitAdapter plays
// for the V-vs-I^n view — AngularFit stays unit- and workflow-agnostic (raw
// angle/value Doubles in, raw Doubles out); Plot System stays physics-free (draws
// whatever series/overlay it is given). All IV domain knowledge — degrees-to-radians
// conversion is inside the module itself, but fold selection, harmonic labeling, and
// overlay construction against the angle-dependence scatter series lives here.
//
// The fit overlay is purely additive: it never mutates the angle-dependence scatter
// series (points, sort order, duplicate-angle handling, legend label) and it does not
// implement fitting inside IVPlotRenderer or modify IVAngleDependenceUseCase.

enum IVAngularFitAdapter {

    /// The angle-dependence payload always carries exactly one series at index 0
    /// (see IVAngleDependenceProjection.makeSeries / IVPlotRenderer.makeAngleDependencePayloads),
    /// so its positional identity key from WorkbenchSeriesOrderKeyResolver is stably "0".
    static let angleSeriesIdentityKey = "0"

    /// Runs the harmonic fit against the angle-dependence result's points and projects
    /// it into a display-anchored overlay. Returns nil when fit mode is `.none` or the
    /// fit does not succeed (insufficient/invalid data) — callers append no overlay in
    /// that case, leaving the scatter-only payload byte-for-byte unchanged.
    static func makeOverlay(
        from result: IVAngleDependenceResult,
        fitMode: AngularFitMode,
        fold: Int
    ) -> WorkbenchPlotSeriesOverlay? {
        guard fitMode != .none else { return nil }

        let points = result.points.map { AngularFitPoint(angleDeg: $0.angleDeg, value: $0.slope) }
        let fitResult = AngularFitUseCase().execute(
            input: AngularFitInput(points: points),
            configuration: AngularFitConfiguration(mode: fitMode, fold: fold)
        )
        guard fitResult.isSuccessful, let fitLine = fitResult.fitLine else { return nil }

        let overlaySeries = WorkbenchPlotSeries(
            label: overlayLabel(fold: fold),
            x: fitLine.angleDeg,
            y: fitLine.value,
            renderMode: .line,
            renderModeLocked: true,
            lineWidth: 2.0
        )
        return WorkbenchPlotSeriesOverlay(
            overlayIdentityKey: "\(angleSeriesIdentityKey)#angularFit",
            parentSeriesIdentityKey: angleSeriesIdentityKey,
            series: overlaySeries
        )
    }

    /// Human-readable picker text for the angular fit mode — IV's own vocabulary.
    static func fitModeDisplayName(_ mode: AngularFitMode) -> String {
        switch mode {
        case .none: return "None"
        case .harmonic: return "Harmonic"
        }
    }

    // MARK: - Private

    private static func overlayLabel(fold: Int) -> String {
        "math:harmonic fit (m=\(fold))"
    }
}
