import Foundation

/// Single switch gating diagnostic `print` output for `EnvelopeBackgroundSlope`.
/// Defaults to off so normal runs stay quiet; flip to `true` locally when auditing
/// segment selection for a specific loop.
enum EnvelopeBackgroundSlopeDiagnosticsLogging {
    static let isEnabled = false
}

/// Envelope-based high-field background slope for ordinary-Hall (linear-in-H) background
/// removal. Shared by the standalone AHE workflow (`AHEBackgroundCorrectionUseCase`) and
/// 3ω's hysteresis preprocessing (`ThreeOmegaFitUseCase`).
///
/// Unlike a plain positive/negative-branch split, this selects the two high-field
/// segments (out of {+H up-sweep, +H down-sweep, -H up-sweep, -H down-sweep}) with the
/// largest and smallest raw mean(y), fits each independently, and averages their slopes
/// into one common `backgroundSlope`. This is robust to a loop whose two branches at the
/// same field sign have already separated (train-track artifact) — the y-extremes, not
/// the field sign, decide which segments anchor the background.
enum EnvelopeBackgroundSlope {
    static let epsilon: Double = 1e-12

    struct Diagnostics: Sendable {
        var seriesLabel: String
        var hMaxAbs: Double
        var highFieldThreshold: Double
        var segmentPointCounts: [String: Int]
        var segmentMeanY: [String: Double]
        var selectedHighSegment: String?
        var selectedLowSegment: String?
        var slopeHigh: Double?
        var slopeLow: Double?
        var backgroundSlope: Double
        var slopeDisagreement: Double
        var fallback: Bool

        func log() {
            guard EnvelopeBackgroundSlopeDiagnosticsLogging.isEnabled else { return }
            let slopeHighText = slopeHigh.map { String($0) } ?? "nil"
            let slopeLowText = slopeLow.map { String($0) } ?? "nil"
            var line = "[envelope background] series=\(seriesLabel) "
            line += "HmaxAbs=\(hMaxAbs) threshold=\(highFieldThreshold) "
            line += "counts=\(segmentPointCounts) meanY=\(segmentMeanY) "
            line += "high=\(selectedHighSegment ?? "nil") low=\(selectedLowSegment ?? "nil") "
            line += "slopeHigh=\(slopeHighText) slopeLow=\(slopeLowText) "
            line += "backgroundSlope=\(backgroundSlope) disagreement=\(slopeDisagreement) fallback=\(fallback)"
            print(line)
        }
    }

    struct Result {
        var correctedY: [Double]
        var diagnostics: Diagnostics
    }

    // Fixed iteration order so segment selection among mean-Y ties is deterministic.
    private static let segmentOrder = ["posUp", "posDown", "negUp", "negDown"]

    /// - Parameters:
    ///   - highFrac: high-field region is |H| >= highFrac * HmaxAbs (spec default 0.8).
    ///   - minSegmentPoints: a candidate segment must have at least this many points to be valid.
    ///   - fallbackHighFrac/fallbackMinHighFieldPoints: parameters for the previous
    ///     branch-sign-only linear background method, used when fewer than two valid
    ///     candidate segments exist.
    static func apply(
        H: [Double],
        R: [Double],
        seriesLabel: String,
        highFrac: Double = 0.8,
        minSegmentPoints: Int = 3,
        fallbackHighFrac: Double = 0.70,
        fallbackMinHighFieldPoints: Int = 3
    ) -> Result {
        func fallback(hMaxAbs: Double, threshold: Double, counts: [String: Int], means: [String: Double]) -> Result {
            let fallbackY = LinearBackgroundCorrection.subtractLinearBackground(
                H: H, R: R, highFrac: fallbackHighFrac, minHighFieldPoints: fallbackMinHighFieldPoints
            )
            let diagnostics = Diagnostics(
                seriesLabel: seriesLabel,
                hMaxAbs: hMaxAbs,
                highFieldThreshold: threshold,
                segmentPointCounts: counts,
                segmentMeanY: means,
                selectedHighSegment: nil,
                selectedLowSegment: nil,
                slopeHigh: nil,
                slopeLow: nil,
                backgroundSlope: 0,
                slopeDisagreement: 0,
                fallback: true
            )
            diagnostics.log()
            return Result(correctedY: fallbackY, diagnostics: diagnostics)
        }

        guard H.count == R.count, !H.isEmpty else {
            return fallback(hMaxAbs: 0, threshold: 0, counts: [:], means: [:])
        }

        let hMaxAbs = H.map { abs($0) }.max() ?? 0
        let threshold = highFrac * hMaxAbs

        // Per-point sweep direction from the backward difference (scan order, not sorted).
        // The first point takes the second point's direction; flat/duplicate steps inherit
        // the previous nonzero direction so every point gets a definite up/down label.
        var direction = [Int](repeating: 0, count: H.count)
        if H.count > 1 {
            for i in 1..<H.count {
                let d = H[i] - H[i - 1]
                direction[i] = d > 0 ? 1 : (d < 0 ? -1 : 0)
            }
            direction[0] = direction[1]
        } else {
            direction[0] = 1
        }
        var lastNonZero = direction.first(where: { $0 != 0 }) ?? 1
        for i in direction.indices {
            if direction[i] == 0 {
                direction[i] = lastNonZero
            } else {
                lastNonZero = direction[i]
            }
        }

        var segH: [String: [Double]] = ["posUp": [], "posDown": [], "negUp": [], "negDown": []]
        var segR: [String: [Double]] = ["posUp": [], "posDown": [], "negUp": [], "negDown": []]

        for i in 0..<H.count {
            let h = H[i]
            guard h >= threshold || h <= -threshold else { continue }
            let key: String
            if h >= threshold {
                key = direction[i] > 0 ? "posUp" : "posDown"
            } else {
                key = direction[i] > 0 ? "negUp" : "negDown"
            }
            segH[key]?.append(h)
            segR[key]?.append(R[i])
        }

        var pointCounts: [String: Int] = [:]
        var meanYs: [String: Double] = [:]
        for key in segmentOrder {
            let values = segR[key] ?? []
            pointCounts[key] = values.count
            if !values.isEmpty {
                meanYs[key] = values.reduce(0, +) / Double(values.count)
            }
        }

        let validKeys = segmentOrder.filter { (pointCounts[$0] ?? 0) >= minSegmentPoints }
        guard validKeys.count >= 2 else {
            return fallback(hMaxAbs: hMaxAbs, threshold: threshold, counts: pointCounts, means: meanYs)
        }

        let highKey = validKeys.max { meanYs[$0]! < meanYs[$1]! }!
        let lowKey = validKeys.min { meanYs[$0]! < meanYs[$1]! }!

        guard let (aHigh, _) = LinearBackgroundCorrection.linearSlopeAndIntercept(x: segH[highKey]!, y: segR[highKey]!),
              let (aLow, _) = LinearBackgroundCorrection.linearSlopeAndIntercept(x: segH[lowKey]!, y: segR[lowKey]!) else {
            return fallback(hMaxAbs: hMaxAbs, threshold: threshold, counts: pointCounts, means: meanYs)
        }

        let backgroundSlope = 0.5 * (aHigh + aLow)
        let disagreement = abs(aHigh - aLow) / max(abs(backgroundSlope), epsilon)
        let correctedY = zip(R, H).map { $0.0 - backgroundSlope * $0.1 }

        let diagnostics = Diagnostics(
            seriesLabel: seriesLabel,
            hMaxAbs: hMaxAbs,
            highFieldThreshold: threshold,
            segmentPointCounts: pointCounts,
            segmentMeanY: meanYs,
            selectedHighSegment: highKey,
            selectedLowSegment: lowKey,
            slopeHigh: aHigh,
            slopeLow: aLow,
            backgroundSlope: backgroundSlope,
            slopeDisagreement: disagreement,
            fallback: false
        )
        diagnostics.log()
        return Result(correctedY: correctedY, diagnostics: diagnostics)
    }
}
