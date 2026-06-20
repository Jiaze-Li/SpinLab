import CoreGraphics

/// Intensity normalization mode for the heatmap color scale.
enum HeatmapColorScaleMode: Sendable {
    case linear
    /// Log10 normalization. Zero and negative Z values are clamped to a safe floor.
    case log10
}

/// Maps Z values to CGColor using a configurable scale and colormap (Plot System-owned).
/// Parallel to the XY series color logic; must not be placed in RSM workflow files.
struct HeatmapColorScale: Sendable {
    var zMin: Double
    var zMax: Double
    var mode: HeatmapColorScaleMode
    /// Colormap lookup key. Unknown keys fall back to viridis.
    var colormapKey: String

    // MARK: - Public

    /// Maps z to a CGColor using the configured scale and colormap.
    func color(for z: Double) -> CGColor {
        let t = normalizedValue(for: z)
        return viridisColor(t: t)
    }

    /// Normalizes z to [0, 1]. Clamped — never returns NaN.
    ///
    /// Edge-case behavior (both modes):
    /// - NaN  → 0.0 (minimum color)
    /// - +Inf → 1.0 (maximum color); −Inf → 0.0 (minimum color)
    func normalizedValue(for z: Double) -> Double {
        switch mode {
        case .linear:
            guard !z.isNaN else { return 0 }
            let span = zMax - zMin
            guard span > 0 else { return 0 }
            return min(max((z - zMin) / span, 0), 1)

        case .log10:
            // Use a safe positive floor so log10(0) and negative values don't produce -inf or NaN.
            // The floor is chosen relative to zMax so it doesn't visually affect the scale.
            // NaN guard: Swift max(NaN, x) propagates NaN when NaN is the first argument.
            guard !z.isNaN else { return 0 }
            let safeMin: Double
            if zMin > 0 {
                safeMin = zMin
            } else if zMax > 0 {
                safeMin = zMax * 1e-6
            } else {
                return 0
            }
            let lo = Darwin.log10(safeMin)
            let hi = Darwin.log10(max(zMax, safeMin * 10))
            let span = hi - lo
            guard span > 0 else { return 0 }
            let lz = Darwin.log10(max(z, safeMin))
            return min(max((lz - lo) / span, 0), 1)
        }
    }

    // MARK: - Viridis colormap (9 reference stops from matplotlib viridis)

    private static let viridisStops: [(r: Double, g: Double, b: Double)] = [
        (0.267004, 0.004874, 0.329415),  // t = 0.000
        (0.282623, 0.140926, 0.457517),  // t = 0.125
        (0.253935, 0.265254, 0.529983),  // t = 0.250
        (0.206756, 0.371758, 0.553117),  // t = 0.375
        (0.163625, 0.471133, 0.558148),  // t = 0.500
        (0.127568, 0.566949, 0.550556),  // t = 0.625
        (0.278826, 0.679294, 0.473707),  // t = 0.750
        (0.627971, 0.855151, 0.227799),  // t = 0.875
        (0.993248, 0.906157, 0.143936),  // t = 1.000
    ]

    private func viridisColor(t: Double) -> CGColor {
        let stops = Self.viridisStops
        let tClamped = min(max(t, 0), 1)
        let n = stops.count - 1
        let fi = tClamped * Double(n)
        let i0 = min(Int(fi), n - 1)
        let i1 = i0 + 1
        let frac = fi - Double(i0)

        let c0 = stops[i0], c1 = stops[i1]
        return CGColor(
            red:   c0.r + (c1.r - c0.r) * frac,
            green: c0.g + (c1.g - c0.g) * frac,
            blue:  c0.b + (c1.b - c0.b) * frac,
            alpha: 1
        )
    }
}
