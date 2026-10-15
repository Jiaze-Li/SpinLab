import Foundation

/// Small dense linear system solver (Gaussian elimination with partial pivoting), shared by
/// AFM Plane Level (3 unknowns: a, b, c) and Line Flatten (1–3 unknowns, polynomial order 0–2
/// normal equations). Not AFM-specific by itself, but currently only used here.
enum LinearSystemSolver {
    /// Solves `A x = b`. Returns nil if `A` is singular (or numerically indistinguishable from
    /// singular) within tolerance — callers must treat that as "insufficient/degenerate data",
    /// not crash.
    static func solve(_ A: [[Double]], _ b: [Double]) -> [Double]? {
        let n = A.count
        guard n > 0, A.allSatisfy({ $0.count == n }), b.count == n else { return nil }

        var m = A
        var rhs = b

        for col in 0..<n {
            var pivotRow = col
            var maxMagnitude = abs(m[col][col])
            for row in (col + 1)..<n where abs(m[row][col]) > maxMagnitude {
                maxMagnitude = abs(m[row][col])
                pivotRow = row
            }
            guard maxMagnitude > 1e-12 else { return nil }
            if pivotRow != col {
                m.swapAt(col, pivotRow)
                rhs.swapAt(col, pivotRow)
            }

            let pivot = m[col][col]
            for row in (col + 1)..<n {
                let factor = m[row][col] / pivot
                guard factor != 0 else { continue }
                for c in col..<n {
                    m[row][c] -= factor * m[col][c]
                }
                rhs[row] -= factor * rhs[col]
            }
        }

        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = rhs[row]
            for c in (row + 1)..<n {
                sum -= m[row][c] * x[c]
            }
            x[row] = sum / m[row][row]
        }
        return x
    }
}
