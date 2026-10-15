import Foundation

/// Robust Plane Level: fits `z(x,y) = a*x + b*y + c` with Huber iteratively reweighted least
/// squares so tall features (particles, debris) pull the background plane far less than in the
/// ordinary least-squares `AFMPlaneLevelProcessor`.
///
/// Each pass: residuals `r` from the current plane, robust scale `s = 1.4826 * MAD(r)`, Huber
/// threshold `k = 1.345 * s`; weight `1` for `|r| <= k`, else `k / |r|`; then a weighted
/// least-squares re-fit. Uses the real canonical X/Y coordinates (centered internally for
/// conditioning — the fitted plane itself is coordinate-origin independent). Subtracts the final
/// plane from every finite cell; never touches coordinates or non-finite cells. No feature
/// detection or segmentation is performed.
enum AFMRobustPlaneProcessor {
    static let maxIterations = 50
    static let huberTuning = 1.345
    static let convergenceTolerance = 1e-10

    static func apply(to matrix: [[Double]], xCoordinates: [Double], yCoordinates: [Double]) -> AFMPlaneLevelProcessor.Result {
        var samples: [(x: Double, y: Double, z: Double)] = []
        for (yi, row) in matrix.enumerated() {
            for (xi, z) in row.enumerated() where z.isFinite {
                samples.append((xCoordinates[xi], yCoordinates[yi], z))
            }
        }
        guard samples.count >= 3 else {
            return .init(values: matrix, warnings: ["Robust Plane: fewer than 3 finite pixels; leveling skipped."])
        }

        let meanX = samples.reduce(0) { $0 + $1.x } / Double(samples.count)
        let meanY = samples.reduce(0) { $0 + $1.y } / Double(samples.count)

        func fit(weights: [Double]) -> (a: Double, b: Double, c: Double)? {
            var sxx = 0.0, sxy = 0.0, sx = 0.0, syy = 0.0, sy = 0.0, sw = 0.0
            var sxz = 0.0, syz = 0.0, sz = 0.0
            for (i, s) in samples.enumerated() {
                let w = weights[i]
                let x = s.x - meanX, y = s.y - meanY
                sxx += w * x * x; sxy += w * x * y; sx += w * x
                syy += w * y * y; sy += w * y; sw += w
                sxz += w * x * s.z; syz += w * y * s.z; sz += w * s.z
            }
            guard let sol = LinearSystemSolver.solve([[sxx, sxy, sx], [sxy, syy, sy], [sx, sy, sw]], [sxz, syz, sz]),
                  sol.allSatisfy({ $0.isFinite }) else { return nil }
            return (sol[0], sol[1], sol[2])
        }

        var weights = [Double](repeating: 1, count: samples.count)
        guard var plane = fit(weights: weights) else {
            return .init(values: matrix, warnings: ["Robust Plane: fit is degenerate (e.g. collinear finite pixels); leveling skipped."])
        }

        var converged = false
        for _ in 0..<maxIterations {
            let residuals = samples.map { $0.z - (plane.a * ($0.x - meanX) + plane.b * ($0.y - meanY) + plane.c) }
            let center = median(residuals)
            let scale = 1.4826 * median(residuals.map { abs($0 - center) })
            // Most pixels already lie exactly on the plane: it is the robust fit.
            guard scale > 1e-12 else { converged = true; break }
            let k = huberTuning * scale
            weights = residuals.map { abs($0) <= k ? 1 : k / abs($0) }
            guard let next = fit(weights: weights) else {
                return .init(values: matrix, warnings: ["Robust Plane: weighted fit became degenerate; leveling skipped."])
            }
            let change = max(abs(next.a - plane.a), abs(next.b - plane.b), abs(next.c - plane.c))
            let magnitude = max(abs(next.a), abs(next.b), abs(next.c), 1e-30)
            plane = next
            if change <= convergenceTolerance * magnitude { converged = true; break }
        }

        var warnings: [String] = []
        if !converged {
            warnings.append("Robust Plane: did not fully converge in \(maxIterations) iterations; using the last estimate.")
        }

        var result = matrix
        for yi in 0..<matrix.count {
            let y = yCoordinates[yi] - meanY
            for xi in 0..<matrix[yi].count where matrix[yi][xi].isFinite {
                result[yi][xi] -= plane.a * (xCoordinates[xi] - meanX) + plane.b * y + plane.c
            }
        }
        return .init(values: result, warnings: warnings)
    }

    private static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        let n = s.count
        guard n > 0 else { return 0 }
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}
