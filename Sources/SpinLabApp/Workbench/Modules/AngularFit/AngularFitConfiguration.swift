import Foundation

struct AngularFitConfiguration: Codable, Hashable, Sendable {
    var mode: AngularFitMode = .none
    /// Harmonic fold m in y(Ψ) = c0 + a·cos(mΨ) + b·sin(mΨ). Clamped to 1...4.
    var fold: Int = 1
    var minimumPointCount: Int = 3
    var fitLineSampleCount: Int = 64

    init(
        mode: AngularFitMode = .none,
        fold: Int = 1,
        minimumPointCount: Int = 3,
        fitLineSampleCount: Int = 64
    ) {
        self.mode = mode
        self.fold = min(4, max(1, fold))
        self.minimumPointCount = max(3, minimumPointCount)
        self.fitLineSampleCount = max(2, fitLineSampleCount)
    }
}
