import Foundation

// MARK: - IVAngleDependence Contracts
//
// IV-owned module (see IV_ANGLE_DEPENDENCE.md). Pure data types only — no units,
// no labels, no Plot System knowledge. The IV workflow resolves per-sweep angle
// (from its own sample-metadata convention) and current/voltage arrays (from its
// own channel/component/basis selection), then hands them to this module.

/// One sweep's raw inputs for angle-dependence slope extraction.
struct IVAngleDependenceSweepInput: Hashable, Sendable {
    /// Resolved sweep angle in degrees, or nil if it could not be determined.
    var angleDeg: Double?
    /// Current already scaled to the selected basis, in mA (not raised to any power).
    var currentMA: [Double]
    /// Selected-channel/component voltage in mV (not intercept-shifted).
    var voltageMV: [Double]
    /// Stable label for diagnostics/point tooltips (e.g. sweep stem).
    var label: String
}

/// One resolved point on the a_n(Ψ) plot.
struct IVAngleDependencePoint: Hashable, Sendable {
    var angleDeg: Double
    /// Free-intercept PowerLawFit slope for this sweep: a_n = V^{nω}/(I^ω)^n.
    var slope: Double
    var label: String
}

struct IVAngleDependenceResult: Hashable, Sendable {
    /// Points sorted by angle ascending. Duplicate angles are not merged —
    /// each valid sweep contributes its own point.
    var points: [IVAngleDependencePoint]
    /// Count of distinct angle values among points (not sweep count).
    var distinctAngleCount: Int
    /// True when distinctAngleCount >= 2 (module-level sufficiency signal).
    var isSufficient: Bool
    var warnings: [String]
}
