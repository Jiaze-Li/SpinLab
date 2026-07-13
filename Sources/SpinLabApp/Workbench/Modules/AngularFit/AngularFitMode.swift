import Foundation

/// Fit-model selection for the generic angular harmonic fit module.
///
/// `none` disables fitting. `harmonic` fits y(Ψ) = c0 + a·cos(mΨ) + b·sin(mΨ)
/// against the fold `m` carried separately in `AngularFitConfiguration`.
enum AngularFitMode: Int, Codable, Hashable, Sendable, CaseIterable {
    case none = 0
    case harmonic = 1
}
