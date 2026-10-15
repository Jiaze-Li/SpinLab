import Foundation
import Testing
@testable import SpinLabApp

@Suite("AFM Line Flatten")
struct AFMLineFlattenTests {

    private let xs: [Double] = [0, 1, 2, 3, 4]

    @Test("order 0 removes each row's constant")
    func order0RemovesRowConstants() {
        let matrix: [[Double]] = [
            [10, 10, 10, 10, 10],
            [3, 3, 3, 3, 3],
        ]
        let result = AFMLineFlattenProcessor.apply(to: matrix, xCoordinates: xs, degree: 0)
        #expect(result.warnings.isEmpty)
        for row in result.values {
            for v in row { #expect(abs(v) < 1e-9) }
        }
    }

    @Test("order 1 removes each row's linear slope")
    func order1RemovesRowSlopes() {
        // row 0: z = 2x + 1 ; row 1: z = -3x + 4
        let matrix: [[Double]] = [
            xs.map { 2 * $0 + 1 },
            xs.map { -3 * $0 + 4 },
        ]
        let result = AFMLineFlattenProcessor.apply(to: matrix, xCoordinates: xs, degree: 1)
        #expect(result.warnings.isEmpty)
        for row in result.values {
            for v in row { #expect(abs(v) < 1e-9) }
        }
    }

    @Test("order 2 removes each row's quadratic background")
    func order2RemovesRowQuadratic() {
        // row: z = x^2 - 2x + 3
        let matrix: [[Double]] = [xs.map { $0 * $0 - 2 * $0 + 3 }]
        let result = AFMLineFlattenProcessor.apply(to: matrix, xCoordinates: xs, degree: 2)
        #expect(result.warnings.isEmpty)
        for v in result.values[0] { #expect(abs(v) < 1e-9) }
    }

    @Test("Off is identity")
    func offLeavesMatrixUnchanged() {
        // `.off` maps to nil polynomialDegree — verified at the pipeline level, but the
        // processor itself is never invoked for `.off`, so this asserts that contract directly.
        #expect(AFMLineFlattenOrder.off.polynomialDegree == nil)
    }

    @Test("rows with too few finite points are left unchanged and produce one coalesced warning")
    func skipsRowsWithTooFewPoints() {
        let matrix: [[Double]] = [
            xs.map { 2 * $0 + 1 },
            [Double.nan, Double.nan, 5, Double.nan, Double.nan],   // only 1 finite point, need 2 for order 1
        ]
        let untouchedRow = matrix[1]
        let result = AFMLineFlattenProcessor.apply(to: matrix, xCoordinates: xs, degree: 1)
        #expect(result.warnings.count == 1)
        #expect(result.values[1][2] == untouchedRow[2])
        #expect(result.values[1].allSatisfy { $0.isNaN || $0 == untouchedRow[2] })
        // Row 0 (well-determined) is still flattened despite row 1 being skipped.
        for v in result.values[0] { #expect(abs(v) < 1e-9) }
    }

    @Test("multiple skipped rows coalesce into a single warning, not one per row")
    func coalescesMultipleSkippedRowWarnings() {
        let matrix: [[Double]] = [
            [Double.nan, Double.nan, 5, Double.nan, Double.nan],
            [Double.nan, Double.nan, 7, Double.nan, Double.nan],
            [Double.nan, Double.nan, 9, Double.nan, Double.nan],
        ]
        let result = AFMLineFlattenProcessor.apply(to: matrix, xCoordinates: xs, degree: 1)
        #expect(result.warnings.count == 1)
    }

    @Test("repeated reprocessing from the same source is non-compounding")
    func repeatedReprocessingIsNonCompounding() {
        let source = [xs.map { 5 * $0 + 2 }]
        let first = AFMLineFlattenProcessor.apply(to: source, xCoordinates: xs, degree: 1)
        let second = AFMLineFlattenProcessor.apply(to: source, xCoordinates: xs, degree: 1)
        #expect(first.values == second.values)
        // Applying flatten to an *already flattened* (near-zero) row must not further change it
        // materially — this simulates what would happen if a caller mistakenly chained output,
        // which the pipeline itself must never do (see AFMProcessingPipeline).
        let reapplied = AFMLineFlattenProcessor.apply(to: first.values, xCoordinates: xs, degree: 1)
        for v in reapplied.values[0] { #expect(abs(v) < 1e-9) }
    }
}
