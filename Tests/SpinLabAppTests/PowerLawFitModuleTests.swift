import XCTest
@testable import SpinLabApp

final class PowerLawFitModuleTests: XCTestCase {

    private func makePoints(_ values: [(Double, Double)]) -> [PowerLawFitPoint] {
        values.map { PowerLawFitPoint(x: $0.0, y: $0.1) }
    }

    func testModeNoneReturnsDisabledResult() {
        let useCase = PowerLawFitUseCase()
        let result = useCase.execute(
            input: PowerLawFitInput(points: makePoints([(0, 1), (1, 3)])),
            configuration: PowerLawFitConfiguration(mode: .none)
        )

        XCTAssertEqual(result.status, .disabled)
        XCTAssertEqual(result.mode, .none)
        XCTAssertNil(result.slope)
        XCTAssertNil(result.intercept)
        XCTAssertNil(result.rSquared)
        XCTAssertNil(result.fitLine)
        XCTAssertEqual(result.diagnostics.map(\.code), ["disabled"])
    }

    func testModeOneFitsLinearTrend() {
        let useCase = PowerLawFitUseCase()
        let result = useCase.execute(
            input: PowerLawFitInput(points: makePoints([(0, 1), (1, 3), (2, 5)])),
            configuration: PowerLawFitConfiguration(mode: .one, subtractIntercept: false, fitLineSampleCount: 3)
        )

        XCTAssertEqual(result.status, .fitted)
        XCTAssertEqual(result.sampleCount, 3)
        XCTAssertEqual(result.slope ?? .nan, 2.0, accuracy: 1e-9)
        XCTAssertEqual(result.intercept ?? .nan, 1.0, accuracy: 1e-9)
        XCTAssertEqual(result.rSquared ?? .nan, 1.0, accuracy: 1e-9)
        XCTAssertEqual(result.fitLine?.x, [0.0, 1.0, 2.0])
        XCTAssertEqual(result.fitLine?.transformedX, [0.0, 1.0, 2.0])
        XCTAssertEqual(result.fitLine?.y, [1.0, 3.0, 5.0])
        XCTAssertEqual(result.diagnostics.map(\.code), ["fitted"])
    }

    func testModeTwoAndThreeTransformXBeforeRegression() {
        let points = makePoints([(0, 1), (1, 3), (2, 9)])
        let twoResult = PowerLawFitUseCase().execute(
            input: PowerLawFitInput(points: points),
            configuration: PowerLawFitConfiguration(mode: .two, fitLineSampleCount: 3)
        )
        let threeResult = PowerLawFitUseCase().execute(
            input: PowerLawFitInput(points: makePoints([(0, 1), (1, 3), (2, 17)])),
            configuration: PowerLawFitConfiguration(mode: .three, fitLineSampleCount: 3)
        )

        XCTAssertEqual(twoResult.status, .fitted)
        XCTAssertEqual(threeResult.status, .fitted)
        XCTAssertEqual(twoResult.fitLine?.transformedX, [0.0, 1.0, 4.0])
        XCTAssertEqual(twoResult.fitLine?.y, [1.0, 3.0, 9.0])
        XCTAssertEqual(threeResult.fitLine?.transformedX, [0.0, 1.0, 8.0])
        XCTAssertEqual(threeResult.fitLine?.y, [1.0, 3.0, 17.0])
    }

    func testSubtractInterceptKeepsZeroInterceptFitLine() {
        let result = PowerLawFitUseCase().execute(
            input: PowerLawFitInput(points: makePoints([(0, 1), (1, 3), (2, 5)])),
            configuration: PowerLawFitConfiguration(mode: .one, subtractIntercept: true, fitLineSampleCount: 3)
        )

        XCTAssertEqual(result.status, .fitted)
        XCTAssertEqual(result.intercept ?? .nan, 1.0, accuracy: 1e-9)
        XCTAssertEqual(result.fitLine?.y, [0.0, 2.0, 4.0])
        XCTAssertEqual(result.rSquared ?? .nan, 0.625, accuracy: 1e-9)
    }

    func testInsufficientDataFailsSafely() {
        let result = PowerLawFitUseCase().execute(
            input: PowerLawFitInput(points: makePoints([(0, 1)])),
            configuration: PowerLawFitConfiguration(mode: .one, minimumPointCount: 2)
        )

        XCTAssertEqual(result.status, .insufficientData)
        XCTAssertNil(result.slope)
        XCTAssertNil(result.fitLine)
        XCTAssertEqual(result.diagnostics.map(\.code), ["insufficient-data"])
    }

    @MainActor
    func testRuntimeSnapshotRestoreRoundTripsState() {
        let runtime = PowerLawFitRuntime()
        runtime.configuration = PowerLawFitConfiguration(mode: .two, subtractIntercept: true, minimumPointCount: 2, fitLineSampleCount: 5)
        runtime.input = PowerLawFitInput(points: makePoints([(0, 1), (1, 3), (2, 9)]))
        runtime.recompute()

        let snapshot = runtime.snapshot()

        let restored = PowerLawFitRuntime()
        restored.restore(from: snapshot)

        XCTAssertEqual(restored.configuration, runtime.configuration)
        XCTAssertEqual(restored.input, runtime.input)
        XCTAssertEqual(restored.result, runtime.result)
    }
}
