import Foundation

/// Display interpolation mode for heatmap rendering. Display-only — never applied to
/// stored scientific data (e.g. CanonicalRSMDataset, raw detector values).
enum HeatmapInterpolationMode: String, Hashable, Sendable {
    case nearest
    /// Smooths in log10(z + 1) space (rather than raw intensity) before upsampling, so a
    /// few extremely high Bragg-peak pixels no longer dominate the smoothing kernel and
    /// produce abrupt yellow-red boundaries. Colors are then mapped linearly over the
    /// already-log-transformed values; the colorbar displays the original intensity as
    /// power-of-ten tick labels. The preferred publication-style smoothing path.
    case logSpaceGaussian2x
}

extension HeatmapInterpolationMode: Codable {
    /// Legacy packs may contain the retired "gaussianUpsample2x", "bilinear", or
    /// "gaussianLight" raw values (all superseded by logSpaceGaussian2x, which smooths in
    /// log-intensity space instead of raw intensity — more suitable for sharp RSM
    /// diffraction peaks). All three map forward to logSpaceGaussian2x; any other
    /// unrecognized or missing value falls back to nearest rather than throwing, so old
    /// packs never fail to decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try? container.decode(String.self)
        switch raw {
        case HeatmapInterpolationMode.nearest.rawValue:
            self = .nearest
        case HeatmapInterpolationMode.logSpaceGaussian2x.rawValue, "gaussianUpsample2x", "bilinear", "gaussianLight":
            self = .logSpaceGaussian2x
        default:
            self = .nearest
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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

    /// Returns a display-only copy of `grid` with `zMatrix` replaced by `log10(z + 1)`.
    /// Non-finite cells stay non-finite. Does not mutate `grid`; does not touch xValues/yValues.
    static func logTransform(_ grid: HeatmapGrid) -> HeatmapGrid {
        let logMatrix = grid.zMatrix.map { row in
            row.map { z -> Double in
                guard z.isFinite else { return Double.nan }
                return Darwin.log10(z + 1)
            }
        }
        return HeatmapGrid(xValues: grid.xValues, yValues: grid.yValues, zMatrix: logMatrix)
    }

    /// Returns a display-only copy of `grid` with `zMatrix` smoothed by a separable 1D
    /// Gaussian (X pass, then Y pass). Grid dimensions and xValues/yValues are unchanged.
    /// NaN / non-finite samples are excluded from the weighted average; a cell with no
    /// finite neighbor within the kernel radius stays NaN. Does not mutate `grid`.
    static func gaussianSmooth(_ grid: HeatmapGrid, sigma: Double) -> HeatmapGrid {
        guard sigma > 0, grid.isValid else { return grid }

        let radius = Int(ceil(3 * sigma))
        guard radius > 0 else { return grid }

        var kernel = [Double](repeating: 0, count: 2 * radius + 1)
        for i in 0...(2 * radius) {
            let d = Double(i - radius)
            kernel[i] = exp(-(d * d) / (2 * sigma * sigma))
        }

        let nY = grid.nY
        let nX = grid.nX

        // Pass 1: convolve along X.
        var passX = grid.zMatrix
        for row in 0..<nY {
            let source = grid.zMatrix[row]
            for col in 0..<nX {
                var weightedSum = 0.0
                var weightTotal = 0.0
                for k in -radius...radius {
                    let c = col + k
                    guard c >= 0, c < nX else { continue }
                    let value = source[c]
                    guard value.isFinite else { continue }
                    let weight = kernel[k + radius]
                    weightedSum += value * weight
                    weightTotal += weight
                }
                passX[row][col] = weightTotal > 0 ? weightedSum / weightTotal : Double.nan
            }
        }

        // Pass 2: convolve along Y.
        var passY = passX
        for col in 0..<nX {
            for row in 0..<nY {
                var weightedSum = 0.0
                var weightTotal = 0.0
                for k in -radius...radius {
                    let r = row + k
                    guard r >= 0, r < nY else { continue }
                    let value = passX[r][col]
                    guard value.isFinite else { continue }
                    let weight = kernel[k + radius]
                    weightedSum += value * weight
                    weightTotal += weight
                }
                passY[row][col] = weightTotal > 0 ? weightedSum / weightTotal : Double.nan
            }
        }

        return HeatmapGrid(xValues: grid.xValues, yValues: grid.yValues, zMatrix: passY)
    }
}
