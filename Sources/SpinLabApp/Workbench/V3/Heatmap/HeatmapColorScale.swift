import CoreGraphics

/// Maps Z values to CGColor using a configurable scale and colormap (Plot System-owned).
/// Parallel to the XY series color logic; must not be placed in RSM workflow files.
struct HeatmapColorScale: Sendable {

    /// Supported colormap variants. Unknown/unrecognized colormapKey strings fall back to `.viridis`.
    enum Colormap: String, Sendable {
        case viridis
        /// Blue → red RSM colormap for publication-style reciprocal space map rendering.
        case rsmTurbo
    }

    var zMin: Double
    var zMax: Double
    var transform: PlotScaleTransform
    /// Selects the colormap. Unknown or unrecognized keys fall back to viridis.
    var colormapKey: String

    /// Resolves `colormapKey` to a supported `Colormap`, defaulting to `.viridis`.
    var colormap: Colormap {
        Colormap(rawValue: colormapKey) ?? .viridis
    }

    // MARK: - Public

    /// Maps z to a CGColor using the configured scale and colormap.
    func color(for z: Double) -> CGColor {
        let t = normalizedValue(for: z)
        return color(forNormalized: t)
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
    /// Uses the same resolved colormap as `color(for:)` so the heatmap and colorbar always match.
    func color(forNormalized t: Double) -> CGColor {
        switch colormap {
        case .viridis:  return viridisColor(t: t)
        case .rsmTurbo: return rsmTurboColor(t: t)
        }
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

    // MARK: - RSM turbo colormap (dark blue → blue → cyan → green → yellow → orange → red → dark red)

    /// Denser than viridisStops near the high-intensity end so the yellow/orange/red/dark-red
    /// transition doesn't saturate into a large flat block for typical RSM Bragg-peak data.
    private static let rsmTurboStops: [(r: Double, g: Double, b: Double)] = [
        (0.00, 0.00, 0.35),  // t = 0.0   dark blue (low intensity)
        (0.00, 0.00, 0.85),  // t = 0.1   blue
        (0.00, 0.40, 0.95),  // t = 0.2   blue-cyan
        (0.00, 0.85, 0.90),  // t = 0.3   cyan
        (0.00, 0.80, 0.40),  // t = 0.4   cyan-green
        (0.00, 0.70, 0.00),  // t = 0.5   green
        (0.55, 0.80, 0.00),  // t = 0.6   yellow-green
        (1.00, 1.00, 0.00),  // t = 0.7   yellow
        (1.00, 0.60, 0.00),  // t = 0.8   orange
        (0.90, 0.15, 0.00),  // t = 0.9   red
        (0.60, 0.00, 0.00),  // t = 1.0   dark red (high intensity)
    ]

    /// Mild visual-only gamma applied to rsmTurbo so equal steps of z near the high-intensity
    /// end produce more visibly distinct colors (counters the flat-red-saturation look).
    /// Does not touch normalizedValue/zMin/zMax — the underlying intensity range is unchanged.
    private static let rsmTurboVisualGamma: Double = 1.15

    private func rsmTurboColor(t: Double) -> CGColor {
        let stops = Self.rsmTurboStops
        let tClamped = min(max(t, 0), 1)
        let visualT = pow(tClamped, Self.rsmTurboVisualGamma)
        let n = stops.count - 1
        let fi = visualT * Double(n)
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
