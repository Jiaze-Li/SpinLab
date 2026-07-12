import Foundation

// MARK: - ThreeOmegaDisplayScaleSpec
//
// Single source of truth binding a 3ω plot quantity's axis label (via
// WorkbenchPlotDisplayVocabulary) to the numeric display-scale factor applied to its
// SI/canonical value before plotting or persisting as a metric. Prevents the label and the
// scale factor from drifting apart when one is edited without the other — previously the
// renderer (ThreeOmegaPlotRenderer) and the store (ThreeOmegaWorkspaceStore+Plotting) each
// hardcoded their own copy of the same scale factor.
//
// Scope: display-only scaling for known 3ω scaling-law / temperature-dependence quantities.
// Not a general unit-converter — new quantities should get their own named spec, not a
// generic conversion path.

struct ThreeOmegaDisplayScaleSpec {
    /// The physical quantity this spec describes, used to look up the axis label from
    /// WorkbenchPlotDisplayVocabulary.
    let quantity: WorkbenchPhysicalQuantity
    /// Multiplier applied to the canonical SI value to get the displayed numeric value.
    let scaleFactor: Double
    /// Human-readable description of the unit convention (SI → displayed), for auditability.
    let note: String

    /// Axis label for the rendered chart — always math-formatted (`.plotAxis`). This spec
    /// only ever feeds chart-facing axis constants, never manifest/log text.
    func plotLabel() -> String {
        WorkbenchPlotDisplayVocabulary.plotLabel(for: quantity)
    }
}

enum ThreeOmegaDisplayScale {
    /// Scaling-law x-axis: σ²xx, (S/m)² → ×10⁷ S²/cm².
    static let scalingLawX = ThreeOmegaDisplayScaleSpec(
        quantity: .scalingLawX,
        scaleFactor: 1e-11,
        note: "(S/m)² → ×10⁷ S²/cm²"
    )

    /// Scaling-law y-axis: E_AHE^(3ω) / (E_xx³·σxx), Ω·m³/V² → ×10² Ω·μm³·V⁻².
    static let scalingLawY = ThreeOmegaDisplayScaleSpec(
        quantity: .scalingLawY,
        scaleFactor: 1e20,
        note: "Ω·m³/V² → ×10² Ω·μm³·V⁻²"
    )

    /// Scaling-law fit slope (α) display scale. Numerically equal to
    /// scalingLawY.scaleFactor / scalingLawX.scaleFactor (1e20 / 1e-11 = 1e31); kept as its
    /// own literal (rather than computed) to preserve the exact prior floating-point rounding.
    static let scalingLawFitSlope = ThreeOmegaDisplayScaleSpec(
        quantity: .scalingLawY,
        scaleFactor: 1e31,
        note: "α display slope: Ω·μm³·cm²·V⁻²·S⁻²"
    )

    /// Temperature Dependence left axis: E_AHE^(3ω) / E_xx³, m²/V² → ×10² μm²/V²
    /// (m²→μm² is ×1e12, plus the displayed ×10² is ×1e2).
    static let temperatureDependenceLeftY = ThreeOmegaDisplayScaleSpec(
        quantity: .temperatureDependenceERatio,
        scaleFactor: 1e14,
        note: "m²/V² → ×10² μm²/V² (m²→μm² ×1e12, plus displayed ×10² ×1e2)"
    )

    /// Temperature Dependence right axis: σxx, S/m → ×10³ S/cm
    /// (S/m→S/cm is ×1e-2, divided by the displayed ×10³).
    static let temperatureDependenceRightY = ThreeOmegaDisplayScaleSpec(
        quantity: .sigmaXX,
        scaleFactor: 1e-5,
        note: "S/m → ×10³ S/cm (S/m→S/cm ×1e-2, divided by displayed ×10³)"
    )
}
