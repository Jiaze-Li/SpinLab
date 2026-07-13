import Foundation

struct PowerLawFitConfiguration: Codable, Hashable, Sendable {
    var mode: PowerLawFitMode = .none
    var subtractIntercept: Bool = false
    var minimumPointCount: Int = 2
    var fitLineSampleCount: Int = 64

    init(
        mode: PowerLawFitMode = .none,
        subtractIntercept: Bool = false,
        minimumPointCount: Int = 2,
        fitLineSampleCount: Int = 64
    ) {
        self.mode = mode
        self.subtractIntercept = subtractIntercept
        self.minimumPointCount = max(2, minimumPointCount)
        self.fitLineSampleCount = max(2, fitLineSampleCount)
    }
}

