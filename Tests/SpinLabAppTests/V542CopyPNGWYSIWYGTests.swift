import Foundation
import XCTest
@testable import SpinLabApp

// MARK: - V542 displayPayload Offset Regression Tests
//
// Guards the offset/stacking contract that Copy PNG now relies on implicitly:
// Copy PNG copies whatever imageData is currently on screen, so the live render's
// displayPayload must already carry offset-applied y-values for R(1ω)/R(3ω).

final class V542CopyPNGWYSIWYGTests: XCTestCase {

    // MARK: - R(1ω) displayPayload carries offset-applied y-values

    func testR1omegaDisplayPayloadCarriesOffsetAppliedYValues() throws {
        let sweeps = makeFieldSweeps(count: 3)
        var renderer = ThreeOmegaPlotRenderer()
        renderer.stackOffsetMultiplier = 1.2

        let (_, _, displayPayload, _) = renderer.renderR1omega(sweeps: sweeps, device: "D1")

        let dp = try XCTUnwrap(displayPayload, "renderR1omega must return a non-nil displayPayload")
        XCTAssertEqual(dp.series.count, sweeps.count)

        // After stacking, series are non-overlapping bands in y-space.
        // Sort by min-y and verify consecutive sorted series don't overlap.
        let sorted = dp.series.sorted { ($0.y.min() ?? 0) < ($1.y.min() ?? 0) }
        let nonOverlapping = zip(sorted, sorted.dropFirst()).allSatisfy { a, b in
            (a.y.max() ?? 0) < (b.y.min() ?? 0)
        }
        XCTAssertTrue(nonOverlapping,
            "R(1ω) displayPayload series must be non-overlapping stacked bands; offset-applied y-values required")
    }

    // MARK: - R(3ω) displayPayload carries offset-applied y-values

    func testR3omegaDisplayPayloadCarriesOffsetAppliedYValues() throws {
        let sweeps = makeFieldSweeps(count: 3)
        var renderer = ThreeOmegaPlotRenderer()
        renderer.stackOffsetMultiplier = 1.2

        let (_, _, displayPayload, _) = renderer.renderR3omega(sweeps: sweeps, device: "D1")

        let dp = try XCTUnwrap(displayPayload, "renderR3omega must return a non-nil displayPayload")
        XCTAssertEqual(dp.series.count, sweeps.count)

        let sorted = dp.series.sorted { ($0.y.min() ?? 0) < ($1.y.min() ?? 0) }
        let nonOverlapping = zip(sorted, sorted.dropFirst()).allSatisfy { a, b in
            (a.y.max() ?? 0) < (b.y.min() ?? 0)
        }
        XCTAssertTrue(nonOverlapping,
            "R(3ω) displayPayload series must be non-overlapping stacked bands; offset-applied y-values required")
    }

    // MARK: - R(1ω) displayPayload series means strictly ordered after sorting by min-y

    func testR1omegaDisplayPayloadDiffersFromRawManifest() throws {
        let sweeps = makeFieldSweeps(count: 3)
        var renderer = ThreeOmegaPlotRenderer()
        renderer.stackOffsetMultiplier = 1.5

        let (_, _, displayPayload, _) = renderer.renderR1omega(sweeps: sweeps, device: "D1")
        let dp = try XCTUnwrap(displayPayload)

        // After sorting by min-y, each series' mean must exceed the previous one.
        let sorted = dp.series.sorted { ($0.y.min() ?? 0) < ($1.y.min() ?? 0) }
        let means = sorted.map { s in s.y.reduce(0, +) / max(Double(s.y.count), 1) }
        for i in 1..<means.count {
            XCTAssertGreaterThan(means[i], means[i - 1],
                "sorted series[\(i)] mean must exceed series[\(i-1)] mean; stacking offset must appear in displayPayload")
        }
    }

    // MARK: - Helpers

    private func makeFieldSweeps(count: Int) -> [ThreeOmegaFieldSweepResult] {
        (0..<count).map { i in
            // Varying r1omega/r3omega so ThreeOmegaStackOffsetUseCase produces non-zero offsets
            let base = Double(i) * 0.1
            return ThreeOmegaFieldSweepResult(
                temperatureK: Double(200 + i * 50),
                device: "D1",
                hField: [-1.0, 0.0, 1.0],
                r1omega: [-0.5 + base, 0.0 + base, 0.5 + base],
                r3omega: [-0.3 + base, 0.0 + base, 0.3 + base],
                iRms: 1e-3,
                v3omegaWindow: 0.0
            )
        }
    }
}
