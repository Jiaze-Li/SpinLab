import Foundation

struct AngularFitPoint: Codable, Hashable, Sendable {
    var angleDeg: Double
    var value: Double

    init(angleDeg: Double, value: Double) {
        self.angleDeg = angleDeg
        self.value = value
    }
}

struct AngularFitInput: Codable, Hashable, Sendable {
    var points: [AngularFitPoint]

    init(points: [AngularFitPoint]) {
        self.points = points
    }
}
