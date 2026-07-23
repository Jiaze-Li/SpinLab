import XCTest
@testable import SpinLabApp

final class AngularFitModuleTests: XCTestCase {

    private func makePoints(_ values: [(Double, Double)]) -> [AngularFitPoint] {
        values.map { AngularFitPoint(angleDeg: $0.0, value: $0.1) }
    }

    func testModeNoneReturnsDisabledResult() {
        let result = AngularFitUseCase().execute(
            input: AngularFitInput(points: makePoints([(0, 1), (90, 2), (180, 3)])),
            configuration: AngularFitConfiguration(mode: .none)
        )

        XCTAssertEqual(result.status, .disabled)
        XCTAssertEqual(result.mode, .none)
        XCTAssertNil(result.c0)
        XCTAssertNil(result.a)
        XCTAssertNil(result.b)
        XCTAssertNil(result.fitLine)
        XCTAssertEqual(result.diagnostics.map(\.code), ["disabled"])
    }

    func testFoldOneRecoversKnownCoefficients() {
        // y(Ψ) = 2 + 3cos(Ψ) - 1sin(Ψ), sampled exactly at four angles (no noise).
        let c0 = 2.0, a = 3.0, b = -1.0
        let angles: [Double] = [0, 90, 180, 270]
        let points = angles.map { angle -> (Double, Double) in
            let psi = angle * .pi / 180.0
            return (angle, c0 + a * cos(psi) + b * sin(psi))
        }
        let result = AngularFitUseCase().execute(
            input: AngularFitInput(points: makePoints(points)),
            configuration: AngularFitConfiguration(mode: .harmonic, fold: 1, fitLineSampleCount: 5)
        )

        XCTAssertEqual(result.status, .fitted)
        XCTAssertEqual(result.fold, 1)
        XCTAssertEqual(result.c0 ?? .nan, c0, accuracy: 1e-9)
        XCTAssertEqual(result.a ?? .nan, a, accuracy: 1e-9)
        XCTAssertEqual(result.b ?? .nan, b, accuracy: 1e-9)
        XCTAssertEqual(result.amplitude ?? .nan, (a * a + b * b).squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(result.phase ?? .nan, atan2(b, a), accuracy: 1e-9)
        XCTAssertEqual(result.rSquared ?? .nan, 1.0, accuracy: 1e-9)
        XCTAssertNotNil(result.fitLine)
        XCTAssertEqual(result.fitLine?.angleDeg.count, 5)
        XCTAssertEqual(result.diagnostics.map(\.code), ["fitted"])
    }

    func testFoldTwoRecoversKnownCoefficients() {
        // y(Ψ) = 1 + 2cos(2Ψ) + 4sin(2Ψ), sampled at six angles spanning a period of m=2.
        let c0 = 1.0, a = 2.0, b = 4.0
        let angles: [Double] = [0, 30, 60, 90, 120, 150]
        let points = angles.map { angle -> (Double, Double) in
            let psi = angle * .pi / 180.0
            return (angle, c0 + a * cos(2 * psi) + b * sin(2 * psi))
        }
        let result = AngularFitUseCase().execute(
            input: AngularFitInput(points: makePoints(points)),
            configuration: AngularFitConfiguration(mode: .harmonic, fold: 2)
        )

        XCTAssertEqual(result.status, .fitted)
        XCTAssertEqual(result.fold, 2)
        XCTAssertEqual(result.c0 ?? .nan, c0, accuracy: 1e-6)
        XCTAssertEqual(result.a ?? .nan, a, accuracy: 1e-6)
        XCTAssertEqual(result.b ?? .nan, b, accuracy: 1e-6)
        XCTAssertEqual(result.rSquared ?? .nan, 1.0, accuracy: 1e-6)
    }

    func testFoldClampsToOneThroughFour() {
        XCTAssertEqual(AngularFitConfiguration(mode: .harmonic, fold: 0).fold, 1)
        XCTAssertEqual(AngularFitConfiguration(mode: .harmonic, fold: 7).fold, 4)
        XCTAssertEqual(AngularFitConfiguration(mode: .harmonic, fold: 3).fold, 3)
    }

    func testInsufficientDataFailsSafely() {
        let result = AngularFitUseCase().execute(
            input: AngularFitInput(points: makePoints([(0, 1), (90, 2)])),
            configuration: AngularFitConfiguration(mode: .harmonic, minimumPointCount: 3)
        )

        XCTAssertEqual(result.status, .insufficientData)
        XCTAssertNil(result.c0)
        XCTAssertNil(result.fitLine)
        XCTAssertEqual(result.diagnostics.map(\.code), ["insufficient-data"])
    }

    func testFitLineGeometrySampledOverInputAngleRange() {
        let angles: [Double] = [10, 40, 70, 100]
        let points = angles.map { angle -> (Double, Double) in
            let psi = angle * .pi / 180.0
            return (angle, 1 + cos(psi))
        }
        let result = AngularFitUseCase().execute(
            input: AngularFitInput(points: makePoints(points)),
            configuration: AngularFitConfiguration(mode: .harmonic, fold: 1, fitLineSampleCount: 20)
        )

        XCTAssertEqual(result.status, .fitted)
        let fitLine = try! XCTUnwrap(result.fitLine)
        XCTAssertEqual(fitLine.angleDeg.count, 20)
        XCTAssertEqual(fitLine.value.count, 20)
        XCTAssertEqual(fitLine.angleDeg.min() ?? .nan, 10, accuracy: 1e-9)
        XCTAssertEqual(fitLine.angleDeg.max() ?? .nan, 100, accuracy: 1e-9)
    }
}
