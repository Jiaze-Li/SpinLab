import Foundation

/// Display interpolation mode for heatmap rendering. Display-only — never applied to
/// stored scientific data (e.g. CanonicalRSMDataset, raw detector values).
enum HeatmapInterpolationMode: String, Codable, Hashable, Sendable {
    case nearest
    case bilinear
}

/// Produces a denser, display-only `HeatmapGrid` via bilinear interpolation for smoother
/// on-screen rendering (Plot System-owned). Must never be persisted as scientific data or
/// fed back into CanonicalRSMDataset / RSMDataParser.
enum HeatmapGridInterpolator {

    /// Returns a new grid with `(n-1)*scale + 1` samples per axis, bilinearly interpolated
    /// from `grid`. Does not mutate `grid`. `scale <= 1` returns `grid` unchanged.
    static func bilinear(_ grid: HeatmapGrid, scale: Int) -> HeatmapGrid {
        guard scale > 1, grid.isValid else { return grid }

        let nX = grid.nX
        let nY = grid.nY
        guard nX > 1 || nY > 1 else { return grid }

        let newNX = nX > 1 ? (nX - 1) * scale + 1 : 1
        let newNY = nY > 1 ? (nY - 1) * scale + 1 : 1

        let newXValues = interpolatedAxis(grid.xValues, newCount: newNX)
        let newYValues = interpolatedAxis(grid.yValues, newCount: newNY)

        var newZMatrix = Array(repeating: Array(repeating: Double.nan, count: newNX), count: newNY)

        for row in 0..<newNY {
            let fy = nY > 1 ? Double(row) / Double(scale) : 0
            let y0 = min(Int(fy), nY - 1)
            let y1 = min(y0 + 1, nY - 1)
            let fracY = fy - Double(y0)

            for col in 0..<newNX {
                let fx = nX > 1 ? Double(col) / Double(scale) : 0
                let x0 = min(Int(fx), nX - 1)
                let x1 = min(x0 + 1, nX - 1)
                let fracX = fx - Double(x0)

                newZMatrix[row][col] = bilinearValue(
                    grid: grid, x0: x0, x1: x1, y0: y0, y1: y1, fracX: fracX, fracY: fracY
                )
            }
        }

        return HeatmapGrid(xValues: newXValues, yValues: newYValues, zMatrix: newZMatrix)
    }

    // MARK: - Helpers

    private static func interpolatedAxis(_ values: [Double], newCount: Int) -> [Double] {
        guard values.count > 1, newCount > 1 else { return values }
        let n = values.count
        let ratio = Double(newCount - 1) / Double(n - 1)
        return (0..<newCount).map { i in
            let f = Double(i) / ratio
            let i0 = min(Int(f), n - 2)
            let frac = f - Double(i0)
            return values[i0] + (values[i0 + 1] - values[i0]) * frac
        }
    }

    /// Weighted bilinear average over the four surrounding corners, skipping non-finite
    /// values. If all four corners are non-finite, returns NaN.
    private static func bilinearValue(
        grid: HeatmapGrid, x0: Int, x1: Int, y0: Int, y1: Int, fracX: Double, fracY: Double
    ) -> Double {
        let corners = [
            (value: grid.zMatrix[y0][x0], weight: (1 - fracX) * (1 - fracY)),
            (value: grid.zMatrix[y0][x1], weight: fracX * (1 - fracY)),
            (value: grid.zMatrix[y1][x0], weight: (1 - fracX) * fracY),
            (value: grid.zMatrix[y1][x1], weight: fracX * fracY),
        ]

        var weightedSum = 0.0
        var weightTotal = 0.0
        for corner in corners where corner.value.isFinite {
            weightedSum += corner.value * corner.weight
            weightTotal += corner.weight
        }

        guard weightTotal > 0 else {
            return corners.first(where: { $0.value.isFinite })?.value ?? Double.nan
        }
        return weightedSum / weightTotal
    }
}
