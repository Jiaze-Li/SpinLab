import Foundation
import Testing
@testable import SpinLabApp

@Suite("AFM Plane Level")
struct AFMPlaneLevelTests {

    private let xs: [Double] = [0, 1, 2, 3, 4]
    private let ys: [Double] = [0, 1, 2, 3]

    private func plane(a: Double, b: Double, c: Double) -> [[Double]] {
        ys.map { y in xs.map { x in a * x + b * y + c } }
    }

    @Test("z = 2x - 3y + 5 leveling residual is ~0")
    func planeLevelRemovesExactPlane() {
        let matrix = plane(a: 2, b: -3, c: 5)
        let result = AFMPlaneLevelProcessor.apply(to: matrix, xCoordinates: xs, yCoordinates: ys)
        #expect(result.warnings.isEmpty)
        for row in result.values {
            for v in row {
                #expect(abs(v) < 1e-9)
            }
        }
    }

    @Test("plane + localized feature: fitted background removed without mutating coordinates or count")
    func planeLevelRemovesBackgroundWithFeature() {
        var matrix = plane(a: 2, b: -3, c: 5)
        // Localized bump at one pixel — least squares should still largely remove the
        // background plane elsewhere; it must not crash and must preserve shape.
        matrix[1][2] += 50
        let originalXs = xs
        let originalYs = ys

        let result = AFMPlaneLevelProcessor.apply(to: matrix, xCoordinates: xs, yCoordinates: ys)

        #expect(xs == originalXs, "Plane Level must never mutate X coordinates")
        #expect(ys == originalYs, "Plane Level must never mutate Y coordinates")
        #expect(result.values.count == matrix.count)
        #expect(result.values.allSatisfy { $0.count == xs.count })

        // The bump pixel should still stand out from its now-flattened neighbors.
        let neighborAvg = (result.values[1][1] + result.values[1][3]) / 2
        #expect(result.values[1][2] - neighborAvg > 30)
    }

    @Test("non-finite cells are ignored in the fit and left untouched")
    func ignoresNonFiniteCellsInFit() {
        var matrix = plane(a: 1, b: 1, c: 0)
        matrix[0][0] = .nan
        let result = AFMPlaneLevelProcessor.apply(to: matrix, xCoordinates: xs, yCoordinates: ys)
        #expect(result.values[0][0].isNaN)
        #expect(abs(result.values[2][2]) < 1e-9)
    }

    @Test("warns and skips leveling when fewer than 3 finite pixels remain")
    func warnsWhenInsufficientFinitePoints() {
        var matrix = plane(a: 1, b: 1, c: 1)
        for y in 0..<matrix.count {
            for x in 0..<matrix[y].count {
                if !(y == 0 && x <= 1) { matrix[y][x] = .nan }
            }
        }
        let result = AFMPlaneLevelProcessor.apply(to: matrix, xCoordinates: xs, yCoordinates: ys)
        #expect(!result.warnings.isEmpty)
        #expect(result.values[0][0] == matrix[0][0])
        #expect(result.values[0][1] == matrix[0][1])
    }

    @Test("warns and skips leveling for a degenerate (collinear) fit")
    func warnsOnDegenerateFit() {
        // All finite points share the same X — the plane fit is underdetermined for `a`.
        var matrix = [[Double]](repeating: [Double](repeating: .nan, count: xs.count), count: ys.count)
        for y in 0..<ys.count { matrix[y][0] = Double(y) }
        let result = AFMPlaneLevelProcessor.apply(to: matrix, xCoordinates: xs, yCoordinates: ys)
        #expect(!result.warnings.isEmpty)
    }
}
