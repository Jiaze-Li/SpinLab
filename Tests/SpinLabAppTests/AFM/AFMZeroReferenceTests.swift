import Foundation
import Testing
@testable import SpinLabApp

@Suite("AFM Zero Reference")
struct AFMZeroReferenceTests {

    @Test("Mean produces mean ~= 0")
    func meanProducesZeroMean() {
        let matrix: [[Double]] = [[1, 2, 3], [4, 5, 6]]
        let result = AFMZeroReferenceProcessor.apply(to: matrix, reference: .mean)
        let mean = result.flatMap { $0 }.reduce(0, +) / 6
        #expect(abs(mean) < 1e-9)
    }

    @Test("Minimum produces min ~= 0")
    func minimumProducesZeroMinimum() {
        let matrix: [[Double]] = [[1, 2, 3], [4, 5, 6]]
        let result = AFMZeroReferenceProcessor.apply(to: matrix, reference: .minimum)
        let minimum = result.flatMap { $0 }.min()!
        #expect(abs(minimum) < 1e-9)
    }

    @Test("None is identity, including after prior stages")
    func noneIsIdentity() {
        let matrix: [[Double]] = [[1, 2], [3, 4]]
        let result = AFMZeroReferenceProcessor.apply(to: matrix, reference: .none)
        #expect(result == matrix)
    }

    @Test("non-finite cells are excluded from mean/minimum and left untouched")
    func nonFiniteCellsExcludedAndUntouched() {
        let matrix: [[Double]] = [[Double.nan, 2, 3], [4, 5, 6]]
        let meanResult = AFMZeroReferenceProcessor.apply(to: matrix, reference: .mean)
        #expect(meanResult[0][0].isNaN)
        let finiteMean = [2.0, 3, 4, 5, 6].reduce(0, +) / 5
        #expect(abs(meanResult[0][1] - (2 - finiteMean)) < 1e-9)

        let minResult = AFMZeroReferenceProcessor.apply(to: matrix, reference: .minimum)
        #expect(minResult[0][0].isNaN)
        #expect(abs(minResult[0][1] - (2 - 2)) < 1e-9)   // finite minimum is 2
    }

    @Test("all-non-finite matrix is left unchanged rather than crashing")
    func allNonFiniteMatrixUnchanged() {
        let matrix: [[Double]] = [[Double.nan, Double.nan]]
        let result = AFMZeroReferenceProcessor.apply(to: matrix, reference: .mean)
        #expect(result[0][0].isNaN)
        #expect(result[0][1].isNaN)
    }
}
