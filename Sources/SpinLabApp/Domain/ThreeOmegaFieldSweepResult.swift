import Foundation

/// One temperature's worth of processed field-sweep data.
struct ThreeOmegaFieldSweepResult: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(device)_\(String(format: "%.1f", temperatureK))K" }

    var temperatureK: Double
    var device: String

    /// Sample metadata carried from search hit for legend resolution (v5.3.4).
    /// Optional so legacy packs without this field decode safely.
    var sampleMetadata: [String: String]?

    /// Stable series identity injected from WorkflowMeasurementSearchHit.sampleKey (v5.3.6).
    /// nil in packs created before 5.3.6; used for drag-reorder and label remapping.
    var sampleID: String? = nil

    /// Measurement file path carried through ingestion so manifest sourceRef stays aligned
    /// after field sweeps are sorted by temperature.
    var sourceFilePath: String? = nil

    // Formula: R¹ω(H) = V¹ω_X(H) / I_rms   (Col[1] / I_rms)
    // Then centered: R¹ω_c(H) = R¹ω(H) - (max(R¹ω) + min(R¹ω)) / 2
    var hField: [Double]    // Oe
    var r1omega: [Double]   // Ω, centered
    var r3omega: [Double]   // Ω, centered

    // I_rms — carried from LVM file for RAHE(3ω) derivation.
    var iRms: Double

    // Formula: R¹ω_AHE = (b⁺ - b⁻) / 2  (HFE on col9)
    //   b⁺ = linear fit intercept at H=0 for H > 0.7×Hmax
    //   b⁻ = linear fit intercept at H=0 for H < -0.7×Hmax
    var rahe1omega: Double?     // Ω, HFE on col9
    var rahe1omegaWA: Double?   // Ω, WA on col9

    // Formula: R_mid = (max(R) + min(R)) / 2
    // Hc = average of |crossing field| on positive and negative branches
    var hc1omega: Double?    // Oe
    var hc3omega: Double?    // Oe

    // V^(3ω)_AHE — primary: window average of (ascending − descending) near H=0.
    // Formula: V3w_AHE = mean(col5 | ascending, |H|<Hwin) − mean(col5 | descending, |H|<Hwin)
    var v3omegaWindow: Double       // V  (primary result)

    // V^(3ω)_AHE — cross-check: high-field linear extrapolation (b⁺ − b⁻) / 2.
    // nil when high-field point count is insufficient for a stable fit.
    var v3omegaFit: Double?         // V  (cross-check; nil = fit failed)

    /// Unified RAHE accessor — hides 1ω/3ω data-source asymmetry.
    /// 1ω: directly from col9 (instrument R). 3ω: derived from V_AHE / iRms.
    /// HFE fallback for 3ω: v3omegaFit ?? v3omegaWindow (aligned with Scaling Law).
    func rahe(harmonic: Int, method: ThreeOmegaV3Method) -> Double? {
        switch (harmonic, method) {
        case (1, .highField): return rahe1omega
        case (1, .window):    return rahe1omegaWA
        case (3, .highField):
            guard abs(iRms) > 1e-30 else { return nil }
            let v = v3omegaFit ?? (v3omegaWindow.isNaN ? nil : v3omegaWindow)
            return v.map { $0 / iRms }
        case (3, .window):
            guard abs(iRms) > 1e-30, !v3omegaWindow.isNaN else { return nil }
            return v3omegaWindow / iRms
        default: return nil
        }
    }
}
