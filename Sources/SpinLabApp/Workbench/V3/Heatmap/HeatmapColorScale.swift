import CoreGraphics

/// Maps Z values to CGColor using a configurable scale and colormap (Plot System-owned).
/// Parallel to the XY series color logic; must not be placed in RSM workflow files.
struct HeatmapColorScale: Sendable {
    var zMin: Double
    var zMax: Double
    var transform: PlotScaleTransform
    /// V1 persists this key as a reserved hook for future colormap variants.
    /// V1 currently supports only viridis; unknown or non-viridis keys intentionally fall back to viridis.
    var colormapKey: String

    // MARK: - Public

    /// Maps z to a CGColor using the configured scale and colormap.
    /// V1 always renders viridis, regardless of colormapKey.
    func color(for z: Double) -> CGColor {
        let t = normalizedValue(for: z)
        return viridisColor(t: t)
    }

    init(
        zMin: Double,
        zMax: Double,
        transform: PlotScaleTransform,
        colormapKey: String
    ) {
        self.zMin = zMin
        self.zMax = zMax
        self.transform = transform
        self.colormapKey = colormapKey
    }

    init(
        zMin: Double,
        zMax: Double,
        mode: PlotScaleTransform,
        colormapKey: String
    ) {
        self.init(zMin: zMin, zMax: zMax, transform: mode, colormapKey: colormapKey)
    }

    /// Normalizes z to [0, 1]. Clamped — never returns NaN.
    ///
    /// Edge-case behavior (both modes):
    /// - NaN  → 0.0 (minimum color)
    /// - +Inf → 1.0 (maximum color); −Inf → 0.0 (minimum color)
    func normalizedValue(for z: Double) -> Double {
        transform.normalizedValue(for: z, lowerBound: zMin, upperBound: zMax)
    }

    /// Maps a pre-normalized value t ∈ [0, 1] directly to a CGColor, bypassing domain normalization.
    /// V1 always renders viridis here as well so colorbar strips match the supported colormap.
    func color(forNormalized t: Double) -> CGColor {
        viridisColor(t: t)
    }

    var mode: PlotScaleTransform {
        transform
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
