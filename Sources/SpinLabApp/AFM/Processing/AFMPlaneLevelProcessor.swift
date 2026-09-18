import Foundation

/// V1 Plane Level: fits `z(x,y) = a*x + b*y + c` by least squares over every finite pixel
/// (using actual canonical X/Y coordinates, not pixel index) and subtracts the fitted plane from
/// every finite cell. Never touches X/Y coordinates or non-finite cells.
enum AFMPlaneLevelProcessor {
    struct Result {
        let values: [[Double]]
        let warnings: [String]
    }

    static func apply(to matrix: [[Double]], xCoordinates: [Double], yCoordinates: [Double]) -> Result {
        var sumX = 0.0, sumY = 0.0, sumXX = 0.0, sumYY = 0.0, sumXY = 0.0
        var sumXZ = 0.0, sumYZ = 0.0, sumZ = 0.0
        var count = 0

        for (yi, row) in matrix.enumerated() {
            let y = yCoordinates[yi]
            for (xi, z) in row.enumerated() where z.isFinite {
                let x = xCoordinates[xi]
                sumX += x; sumY += y; sumXX += x * x; sumYY += y * y; sumXY += x * y
                sumXZ += x * z; sumYZ += y * z; sumZ += z
                count += 1
            }
        }

        guard count >= 3 else {
            return Result(values: matrix, warnings: ["Plane Level: fewer than 3 finite pixels; leveling skipped."])
        }

        let A: [[Double]] = [
            [sumXX, sumXY, sumX],
            [sumXY, sumYY, sumY],
            [sumX, sumY, Double(count)],
        ]
        guard let solution = LinearSystemSolver.solve(A, [sumXZ, sumYZ, sumZ]) else {
            return Result(values: matrix, warnings: ["Plane Level: fit is degenerate (e.g. collinear finite pixels); leveling skipped."])
        }
        let (a, b, c) = (solution[0], solution[1], solution[2])

        var result = matrix
        for yi in 0..<matrix.count {
            let y = yCoordinates[yi]
            for xi in 0..<matrix[yi].count where matrix[yi][xi].isFinite {
                let x = xCoordinates[xi]
                result[yi][xi] -= (a * x + b * y + c)
            }
        }
        return Result(values: result, warnings: [])
    }
}
