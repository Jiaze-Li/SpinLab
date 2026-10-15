import Foundation

/// Line Flatten: fits and subtracts a polynomial (order 0/1/2) independently for each fast-scan
/// row, versus the row's actual canonical X coordinates (not pixel index). Rows with fewer than
/// `degree + 1` finite points are left unchanged; that is coalesced into a single warning rather
/// than one per row.
enum AFMLineFlattenProcessor {
    struct Result {
        let values: [[Double]]
        let warnings: [String]
    }

    static func apply(to matrix: [[Double]], xCoordinates: [Double], degree: Int) -> Result {
        var result = matrix
        var skippedRowCount = 0
        let minimumPoints = degree + 1

        for (yi, row) in matrix.enumerated() {
            var xs: [Double] = []
            var zs: [Double] = []
            for (xi, z) in row.enumerated() where z.isFinite {
                xs.append(xCoordinates[xi])
                zs.append(z)
            }
            guard !xs.isEmpty else { continue }   // nothing finite in this row — nothing to flatten, not a warning
            guard xs.count >= minimumPoints, let coefficients = polynomialLeastSquares(x: xs, y: zs, degree: degree) else {
                skippedRowCount += 1
                continue
            }
            for (xi, z) in row.enumerated() where z.isFinite {
                result[yi][xi] = z - evaluate(coefficients, at: xCoordinates[xi])
            }
        }

        let warnings = skippedRowCount > 0
            ? ["Line Flatten: \(skippedRowCount) row(s) had too few finite points for order \(degree) and were left unchanged."]
            : []
        return Result(values: result, warnings: warnings)
    }

    private static func evaluate(_ coefficients: [Double], at x: Double) -> Double {
        var result = 0.0
        var power = 1.0
        for c in coefficients {
            result += c * power
            power *= x
        }
        return result
    }

    /// Least-squares polynomial fit of `y = c0 + c1*x + c2*x^2 + ...` up to `degree`, via the
    /// normal equations. Returns nil if the resulting system is degenerate.
    private static func polynomialLeastSquares(x: [Double], y: [Double], degree: Int) -> [Double]? {
        let unknownCount = degree + 1
        var powerSums = [Double](repeating: 0, count: 2 * degree + 1)
        for xv in x {
            var p = 1.0
            for k in 0...(2 * degree) {
                powerSums[k] += p
                p *= xv
            }
        }
        var xPowY = [Double](repeating: 0, count: unknownCount)
        for (xv, yv) in zip(x, y) {
            var p = 1.0
            for k in 0..<unknownCount {
                xPowY[k] += p * yv
                p *= xv
            }
        }
        var A = [[Double]](repeating: [Double](repeating: 0, count: unknownCount), count: unknownCount)
        for i in 0..<unknownCount {
            for j in 0..<unknownCount {
                A[i][j] = powerSums[i + j]
            }
        }
        return LinearSystemSolver.solve(A, xPowY)
    }
}
