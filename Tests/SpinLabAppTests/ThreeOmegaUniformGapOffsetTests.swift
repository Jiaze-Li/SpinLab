import Foundation
import Testing
@testable import SpinLabApp

/// Direct contract for the production offset use case, independent of SeriesVisualPlanner.
@Suite("3ω uniform Gap — offset use case")
struct ThreeOmegaUniformGapOffsetTests {
    private func offsets(_ curves: [[Double]], gap: Double) -> [Double] {
        ThreeOmegaStackOffsetUseCase().execute(yValues: curves, minGapFraction: gap)
    }

    @Test("Empty and single-curve inputs produce no stacking")
    func emptyAndSingle() {
        #expect(offsets([], gap: 0.25).isEmpty)
        #expect(offsets([[1, 3]], gap: 0.25) == [0])
        #expect(offsets([[]], gap: 0.25) == [0])
    }

    @Test("Zero, negative, non-finite and overflowing Gap produce all-zero offsets")
    func invalidAndOverflowingGap() {
        let curves: [[Double]] = [[0, 2], [0, 3], [2, 5]]
        for gap in [0.0, -0.1, Double.nan, Double.infinity, -Double.infinity] {
            #expect(offsets(curves, gap: gap) == [0, 0, 0])
        }
        let overflow: [[Double]] = [[0, Double.greatestFiniteMagnitude], [0, 1]]
        #expect(offsets(overflow, gap: 2) == [0, 0])
    }

    @Test("Every adjacent envelope gets exactly max peak-to-peak times Gap, in input order")
    func exactEnvelopeGaps() {
        let curves: [[Double]] = [[10, 20], [50, 55], [1, 4]]
        let shifted = offsets(curves, gap: 0.125)
        #expect(shifted == [0, -28.75, 26.5])
        for index in 0..<(curves.count - 1) {
            let lowerMax = curves[index].max()! + shifted[index]
            let upperMin = curves[index + 1].min()! + shifted[index + 1]
            #expect(abs((upperMin - lowerMax) - 1.25) < 1e-12)
        }
        #expect(shifted[1] < 0, "Offsets may be negative when input sweeps are far apart")
    }

    @Test("Flat or empty curves do not crash and still use the common envelope rule")
    func flatAndEmptyCurves() {
        #expect(offsets([[2, 2], [8, 8]], gap: 0.2) == [0, 0])
        #expect(offsets([[2, 2], [0, 10]], gap: 0.2) == [0, 4])
        #expect(offsets([[], [1, 3]], gap: 0.25) == [0, -0.5])
    }
}
