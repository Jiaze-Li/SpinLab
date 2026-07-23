import Foundation

struct PowerLawFitPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

struct PowerLawFitInput: Codable, Hashable, Sendable {
    var points: [PowerLawFitPoint]

    init(points: [PowerLawFitPoint]) {
        self.points = points
    }
}

