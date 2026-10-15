import Foundation
@testable import SpinLabApp

/// Test-only helpers for characterizing Plane vs Robust Plane (measurement, not product behavior).
enum AFMLevelingCharacterization {
    typealias Leveler = (_ matrix: [[Double]], _ xs: [Double], _ ys: [Double]) -> [[Double]]

    static let plane: Leveler = { AFMPlaneLevelProcessor.apply(to: $0, xCoordinates: $1, yCoordinates: $2).values }
    static let robust: Leveler = { AFMRobustPlaneProcessor.apply(to: $0, xCoordinates: $1, yCoordinates: $2).values }

    // MARK: synthetic island surfaces

    struct Synthetic {
        let values: [[Double]]
        let xs: [Double]
        let ys: [Double]
        let coverage: Double
        let truth: (Double, Double) -> Double   // background plane (x, y) -> nm
    }

    static let gridSize = 64
    static let blockSize = 8
    static let planeA = 0.5, planeB = -0.3, planeC = 2.0   // nm/µm, nm/µm, nm
    static let islandHeight = 20.0

    /// Tilted background + `islandBlocks` of the 64 (8×8-pixel) blocks raised by `islandHeight`.
    /// Block choice is a deterministic LCG shuffle, so the layout is asymmetric but reproducible.
    static func synthetic(islandBlocks: Int) -> Synthetic {
        let n = gridSize, bs = blockSize, per = n / bs
        let xs = (0..<n).map { 3.0 + 0.08 * Double($0) }
        let ys = (0..<n).map { -2.0 + 0.10 * Double($0) }
        var order = Array(0..<(per * per))
        var state: UInt64 = 0x9E3779B97F4A7C15
        for i in stride(from: order.count - 1, to: 0, by: -1) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            order.swapAt(i, Int((state >> 33) % UInt64(i + 1)))
        }
        let raised = Set(order.prefix(islandBlocks))
        let truth: (Double, Double) -> Double = { planeA * $0 + planeB * $1 + planeC }
        var covered = 0
        let values: [[Double]] = (0..<n).map { i in
            (0..<n).map { j in
                let isIsland = raised.contains((i / bs) * per + (j / bs))
                if isIsland { covered += 1 }
                let noise = 0.05 * sin(Double(i * 131 + j * 17) * 1.7)
                return truth(xs[j], ys[i]) + noise + (isIsland ? islandHeight : 0)
            }
        }
        return Synthetic(values: values, xs: xs, ys: ys, coverage: Double(covered) / Double(n * n), truth: truth)
    }

    struct PlaneError {
        let rms: Double          // RMS of (fitted plane − true plane) over all pixels, nm
        let maxAbs: Double
        let backgroundBias: Double // mean leveled height on background pixels (ideal ≈ 0), nm
    }

    static func planeError(_ leveler: Leveler, on s: Synthetic) -> PlaneError {
        let leveled = leveler(s.values, s.xs, s.ys)
        var sq = 0.0, maxAbs = 0.0, biasSum = 0.0, biasCount = 0
        for i in 0..<s.values.count {
            for j in 0..<s.values[i].count {
                let fitted = s.values[i][j] - leveled[i][j]
                let e = fitted - s.truth(s.xs[j], s.ys[i])
                sq += e * e; maxAbs = max(maxAbs, abs(e))
                // Background pixel ⇔ measured sits near the truth plane (islands are +20 nm).
                if s.values[i][j] - s.truth(s.xs[j], s.ys[i]) < islandHeight / 2 { biasSum += leveled[i][j]; biasCount += 1 }
            }
        }
        let n = Double(s.values.count * s.values[0].count)
        return PlaneError(rms: (sq / n).squareRoot(), maxAbs: maxAbs, backgroundBias: biasSum / Double(max(biasCount, 1)))
    }

    // MARK: real-data statistics

    struct LevelStats {
        let median: Double
        let max: Double
        let slopeX: Double   // OLS plane slope left in the leveled map, nm/µm
        let slopeY: Double
    }

    static func stats(_ m: [[Double]], xs: [Double], ys: [Double]) -> LevelStats {
        var zs: [Double] = []
        var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0, sxz = 0.0, syz = 0.0, sz = 0.0
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        for (i, row) in m.enumerated() {
            for (j, z) in row.enumerated() where z.isFinite {
                let x = xs[j] - mx, y = ys[i] - my
                zs.append(z); sz += z
                sx += x; sy += y; sxx += x * x; syy += y * y; sxy += x * y; sxz += x * z; syz += y * z
            }
        }
        let n = Double(zs.count)
        // Normal equations for z = a·x + b·y + c (coordinates centered on the grid mean).
        let sol = LinearSystemSolver.solve([[sxx, sxy, sx], [sxy, syy, sy], [sx, sy, n]], [sxz, syz, sz]) ?? [.nan, .nan, .nan]
        let sorted = zs.sorted()
        return LevelStats(median: sorted[sorted.count / 2], max: sorted.last ?? .nan, slopeX: sol[0], slopeY: sol[1])
    }
}
