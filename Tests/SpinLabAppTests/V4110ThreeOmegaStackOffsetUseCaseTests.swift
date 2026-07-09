import Testing
@testable import SpinLabApp

@Suite("ThreeOmegaStackOffsetUseCase – adaptive adjacent spacing (v4.1.10)")
struct V4110ThreeOmegaStackOffsetUseCaseTests {

    private let sut = ThreeOmegaStackOffsetUseCase()

    // MARK: - Edge cases

    @Test func emptyInput_returnsEmpty() {
        let result = sut.execute(yValues: [])
        #expect(result.isEmpty)
    }

    @Test func singleCurve_returnsZeroOffset() {
        let result = sut.execute(yValues: [[1, 2, 3]])
        #expect(result == [0.0])
    }

    // MARK: - Two small-amplitude curves

    @Test func twoSmallAmplitude_smallSpacing() {
        // pp = [0.1, 0.2]
        // offset[1] = (0.1/2 + 0.2/2) * 1.2 = 0.15 * 1.2 = 0.18
        let result = sut.execute(yValues: [[10.0, 10.1], [20.0, 20.2]])
        #expect(result[0] == 0.0)
        #expect(abs(result[1] - 0.18) < 1e-10)
    }

    // MARK: - Mixed large and small amplitude

    @Test func mixedAmplitude_adaptiveSpacing() {
        // Curve 0: pp = 10  (large)
        // Curve 1: pp = 0.2 (small)
        // Curve 2: pp = 0.1 (small)
        // maxPP = 10, minGap = 10 * 0.15 = 1.5
        // offset[1] = max(1.5, (10/2 + 0.2/2) * 1.2) = max(1.5, 6.12) = 6.12
        // offset[2] = 6.12 + max(1.5, (0.2/2 + 0.1/2) * 1.2) = 6.12 + max(1.5, 0.18) = 7.62
        let result = sut.execute(yValues: [
            [0.0, 10.0],   // large
            [50.0, 50.2],  // small
            [80.0, 80.1],  // small
        ])
        #expect(result[0] == 0.0)
        #expect(abs(result[1] - 6.12) < 1e-10)
        #expect(abs(result[2] - 7.62) < 1e-10)
    }

    @Test func mixedAmplitude_noMinGap() {
        // Same data but minGapFraction = 0 → pure adaptive, no floor
        let result = sut.execute(yValues: [
            [0.0, 10.0],
            [50.0, 50.2],
            [80.0, 80.1],
        ], minGapFraction: 0)
        #expect(result[0] == 0.0)
        #expect(abs(result[1] - 6.12) < 1e-10)
        #expect(abs(result[2] - 6.30) < 1e-10)
    }

    // MARK: - Multiplier = 0 (no stacking)

    @Test func multiplierZero_allOffsetsZero() {
        let result = sut.execute(yValues: [[0, 10], [0, 5], [0, 20]], multiplier: 0)
        #expect(result == [0.0, 0.0, 0.0])
    }

    // MARK: - Multiplier = 1.0 (curves just touch)

    @Test func multiplierOne_curvesJustTouch() {
        // pp = [4, 6]
        // offset[1] = (4/2 + 6/2) * 1.0 = 5.0
        let result = sut.execute(yValues: [[0, 4], [0, 6]], multiplier: 1.0)
        #expect(result[0] == 0.0)
        #expect(abs(result[1] - 5.0) < 1e-10)
    }

    // MARK: - Default multiplier = 1.2

    @Test func defaultMultiplier_is1point2() {
        // pp = [4, 6]
        // offset[1] = (4/2 + 6/2) * 1.2 = 6.0
        let result = sut.execute(yValues: [[0, 4], [0, 6]])
        #expect(abs(result[1] - 6.0) < 1e-10)
    }

    // MARK: - Flat / empty curves treated as pp=0

    @Test func flatCurve_treatedAsZeroPP() {
        // Curve 0: pp = 0 (flat)
        // Curve 1: pp = 10
        // offset[1] = (0/2 + 10/2) * 1.2 = 6.0
        let result = sut.execute(yValues: [[5, 5, 5], [0, 10]])
        #expect(result[0] == 0.0)
        #expect(abs(result[1] - 6.0) < 1e-10)
    }

    @Test func emptyCurve_treatedAsZeroPP() {
        // Curve 0: pp = 0 (empty)
        // Curve 1: pp = 10
        // offset[1] = (0/2 + 10/2) * 1.2 = 6.0
        let result = sut.execute(yValues: [[], [0, 10]])
        #expect(result[0] == 0.0)
        #expect(abs(result[1] - 6.0) < 1e-10)
    }

    // MARK: - minGapFraction

    @Test func minGapFraction_preventsCollapse() {
        // Two tiny curves: pp = [0.01, 0.01], maxPP = 0.01
        // Without minGap: gap = (0.005 + 0.005) * 1.2 = 0.012
        // With minGap (0.15): minGap = 0.01 * 0.15 = 0.0015 → adaptive 0.012 > 0.0015, no effect
        // With minGap (0.5): minGap = 0.01 * 0.5 = 0.005 → adaptive 0.012 > 0.005, no effect
        // With minGap (2.0): minGap = 0.01 * 2.0 = 0.02 → max(0.02, 0.012) = 0.02
        let result = sut.execute(yValues: [[0, 0.01], [0, 0.01]], minGapFraction: 2.0)
        #expect(result[0] == 0.0)
        #expect(abs(result[1] - 0.02) < 1e-10)
    }

    @Test func minGapFraction_zero_noFloor() {
        // pp = [10, 0.01], maxPP = 10, minGap = 0
        // gap = max(0, (5 + 0.005) * 1.2) = 6.006
        let result = sut.execute(yValues: [[0, 10], [0, 0.01]], minGapFraction: 0)
        #expect(abs(result[1] - 6.006) < 1e-10)
    }

    @Test func minGapFraction_allFlat_allOffsetsZero() {
        // All pp = 0, maxPP = 0, minGap = 0
        let result = sut.execute(yValues: [[5, 5], [5, 5], [5, 5]])
        #expect(result == [0.0, 0.0, 0.0])
    }

    // MARK: - Index alignment preserved

    @Test func offsetCount_matchesInputCount() {
        let input: [[Double]] = [[1], [2], [3], [4], [5]]
        let result = sut.execute(yValues: input)
        #expect(result.count == input.count)
    }

    @Test func orderEnforcingBottomToTop_preservesInputOrderForConflictingMeans() {
        let input: [[Double]] = [
            [9.0, 10.0, 11.0],
            [-1.0, 0.0, 1.0],
            [4.0, 5.0, 6.0]
        ]
        let offsets = sut.execute(
            yValues: input,
            multiplier: 1.2,
            minGapFraction: 0.15,
            placementMode: .orderEnforcingBottomToTop
        )
        let shiftedMeans = zip(input, offsets).map { yValues, offset in
            let shifted = yValues.map { $0 + offset }
            return shifted.reduce(0.0, +) / Double(shifted.count)
        }
        #expect(shiftedMeans[0] < shiftedMeans[1])
        #expect(shiftedMeans[1] < shiftedMeans[2])
    }
}
