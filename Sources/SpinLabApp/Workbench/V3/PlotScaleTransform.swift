import Foundation

/// Shared plot scale transform for value normalization across render paths.
///
/// Heatmap is the first consumer, but this type is intentionally general so
/// future Cartesian axis scaling can reuse the same normalization contract.
enum PlotScaleTransform: String, Codable, Sendable {
    case linear
    case log10

    /// Normalizes `value` into the closed interval [0, 1] for the supplied domain.
    /// The result is always finite and clamped.
    func normalizedValue(for value: Double, lowerBound: Double, upperBound: Double) -> Double {
        switch self {
        case .linear:
            return Self.normalizedLinearValue(for: value, lowerBound: lowerBound, upperBound: upperBound)
        case .log10:
            return Self.normalizedLog10Value(for: value, lowerBound: lowerBound, upperBound: upperBound)
        }
    }

    /// Returns the positive domain used for log10 normalization.
    /// The floor is chosen relative to the upper bound so log scaling remains
    /// visually stable when data includes zero or negative values.
    static func log10Domain(lowerBound: Double, upperBound: Double) -> (min: Double, max: Double)? {
        guard lowerBound.isFinite, upperBound.isFinite else { return nil }
        guard upperBound > 0 else { return nil }

        let safeMin = lowerBound > 0 ? lowerBound : upperBound * 1e-6
        guard safeMin.isFinite, safeMin > 0 else { return nil }

        let safeMax = max(upperBound, safeMin * 10)
        guard safeMax.isFinite, safeMax > safeMin else { return nil }
        return (safeMin, safeMax)
    }

    private static func normalizedLinearValue(for value: Double, lowerBound: Double, upperBound: Double) -> Double {
        guard lowerBound.isFinite, upperBound.isFinite else { return 0 }

        let span = upperBound - lowerBound
        guard span > 0, span.isFinite else { return 0 }

        if value.isNaN { return 0 }
        if value == .infinity { return 1 }
        if value == -.infinity { return 0 }

        let normalized = (value - lowerBound) / span
        guard normalized.isFinite else { return value > upperBound ? 1 : 0 }
        return min(max(normalized, 0), 1)
    }

    private static func normalizedLog10Value(for value: Double, lowerBound: Double, upperBound: Double) -> Double {
        guard let domain = log10Domain(lowerBound: lowerBound, upperBound: upperBound) else { return 0 }
        if value.isNaN { return 0 }
        if value == .infinity { return 1 }
        if value == -.infinity { return 0 }

        let lo = Darwin.log10(domain.min)
        let hi = Darwin.log10(domain.max)
        let span = hi - lo
        guard span > 0, span.isFinite else { return 0 }

        let safeValue = max(value, domain.min)
        let lz = Darwin.log10(safeValue)
        guard lz.isFinite else { return 0 }

        let normalized = (lz - lo) / span
        guard normalized.isFinite else { return value > domain.max ? 1 : 0 }
        return min(max(normalized, 0), 1)
    }
}

/// Compatibility alias retained for persisted heatmap display state and older call sites.
typealias HeatmapColorScaleMode = PlotScaleTransform
