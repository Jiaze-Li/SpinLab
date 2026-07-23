import Foundation

enum AngularFitStatus: String, Codable, Hashable, Sendable {
    case disabled
    case insufficientData
    case invalidInput
    case fitted
}

/// Phase convention: the fitted a·cos(mΨ) + b·sin(mΨ) is re-expressed as the single
/// phase-shifted cosine A·cos(mΨ - φ), where A = sqrt(a^2 + b^2) and φ = atan2(b, a).
/// Expanding A·cos(mΨ - φ) = A·cosφ·cos(mΨ) + A·sinφ·sin(mΨ) gives a = A·cosφ, b = A·sinφ,
/// which is exactly what atan2(b, a) inverts. φ is reported in radians.
struct AngularFitResult: Codable, Hashable, Sendable {
    var status: AngularFitStatus
    var mode: AngularFitMode
    var fold: Int
    var sampleCount: Int
    var c0: Double?
    var a: Double?
    var b: Double?
    /// A = sqrt(a^2 + b^2) — see the phase convention note above.
    var amplitude: Double?
    /// φ = atan2(b, a), in radians — see the phase convention note above.
    var phase: Double?
    var rSquared: Double?
    var fitLine: AngularFitLineGeometry?
    var diagnostics: [AngularFitDiagnostic]

    var isSuccessful: Bool {
        status == .fitted && c0 != nil && a != nil && b != nil && fitLine != nil
    }
}
