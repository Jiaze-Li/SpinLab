import Foundation
import Testing
@testable import SpinLabApp

// MARK: - v4.1.2.16 — ThreeOmegaScalingUseCase multi-segment tests
//
// Coverage:
//   - Single segment (full range): result equivalent to legacy single-fit behaviour
//   - Multi-segment: two non-overlapping ranges produce independent fits
//   - Normalisation: reversed bounds are swapped before fitting
//   - Overlap detection: warning emitted when ranges share a closed-interval boundary
//   - Empty segment: fewer-than-2-points warning, segment skipped
//   - isSingleFullRange: returns true iff 1 segment covers all points

private func makeRT(temps: [Double], rxx: [Double]) -> ThreeOmegaRTResult {
    ThreeOmegaRTResult(angleLabel: "0deg", temperatureK: temps, rxx: rxx)
}

private func makeSweep(t: Double, v3w: Double, rxx: Double, iRms: Double) -> ThreeOmegaFieldSweepResult {
    ThreeOmegaFieldSweepResult(
        temperatureK: t,
        angleLabel: "0deg",
        hField: [-100, 0, 100],
        r1omega: [-rxx, 0, rxx],
        r3omega: [0, 0, 0],
        rahe1omega: nil, rahe3omega: nil,
        hc1omega: nil, hc3omega: nil,
        v3omegaWindow: v3w
    )
}

/// Build a set of sweeps that will produce known σ²_xx and scalingY values so we can
/// verify that segment α/β match the expected OLS solution.
///
/// Strategy: choose geometry so that σ_xx = 1/ρ_xx is trivial to compute, then
/// pick v3w to make scalingY land on a straight line.
struct SyntheticScalingRig {
    /// geometry: lxx=1μm, lxy=1μm, d=1nm
    let geo = ThreeOmegaGeometry(lxx: 1, lxy: 1, dNm: 1)

    /// Rxx(T) = T/100 (Ω) — varies with temperature so σ²_xx differs per point.
    ///
    /// Derivation (iRms = 1A):
    ///   ρ_xx   = Rxx × d_m = Rxx × 1e-9
    ///   σ_xx   = 1 / ρ_xx = 1e9 / Rxx
    ///   σ²_xx  = 1e18 / Rxx²
    ///   E_xx   = iRms × Rxx / L_xx_m = Rxx × 1e6
    ///   E_xx³  = Rxx³ × 1e18
    ///   scalingY = (v3w / L_xy_m) / (E_xx³ × σ_xx)
    ///            = v3w / (Rxx² × 1e21)
    ///
    /// To place scalingY = α × σ²_xx + β = α × 1e18/Rxx² + β:
    ///   v3w = (α × 1e18/Rxx² + β) × Rxx² × 1e21
    ///       = (α × 1e18 + β × Rxx²) × 1e21

    func rxxForTemp(_ t: Double) -> Double { t / 100.0 }

    func v3w(alpha: Double, beta: Double, rxx: Double) -> Double {
        (alpha * 1e18 + beta * rxx * rxx) * 1e21
    }

    func iRmsValues(temps: [Double]) -> [Double: Double] {
        Dictionary(uniqueKeysWithValues: temps.map { ($0, 1.0) })
    }

    func rtResult(temps: [Double]) -> ThreeOmegaRTResult {
        makeRT(temps: temps, rxx: temps.map { rxxForTemp($0) })
    }
}

@Suite("V41216 ThreeOmegaScalingUseCase — multi-segment")
struct V41216ScalingUseCaseTests {

    let uc  = ThreeOmegaScalingUseCase()
    let rig = SyntheticScalingRig()

    // MARK: single full-range regression

    @Test("Single default range equals legacy single-fit output")
    func singleFullRangeRegression() {
        let alpha_t = 2.0e-18   // SI units for α
        let beta_t  = 0.5       // scaled up so β is recoverable by OLS at Double precision
        let temps: [Double] = [100, 150, 200, 250, 300]
        let sweeps = temps.map { t in
            let rxx = rig.rxxForTemp(t)
            return makeSweep(t: t, v3w: rig.v3w(alpha: alpha_t, beta: beta_t, rxx: rxx), rxx: rxx, iRms: 1.0)
        }
        let result = uc.executeWithIRms(
            fieldSweeps: sweeps,
            rtResult: rig.rtResult(temps: temps),
            geometry: rig.geo,
            iRmsValues: rig.iRmsValues(temps: temps)
        )
        #expect(result.segments.count == 1)
        #expect(result.isSingleFullRange())
        let seg = result.segments[0]
        #expect(abs(seg.alpha - alpha_t) / abs(alpha_t) < 1e-6)
        #expect(abs(seg.beta  - beta_t)  / abs(beta_t)  < 1e-6)
        #expect(seg.rSquared > 0.9999)
        #expect(seg.pointCount == temps.count)
    }

    // MARK: multi-segment

    @Test("Two non-overlapping ranges produce independent fits")
    func twoIndependentSegments() {
        // Low range: 100–200K  →  α=2e-18, β=3e-20
        // High range: 300–500K →  α=5e-18, β=1e-20
        let alphaLo = 2.0e-18, betaLo = 0.5
        let alphaHi = 5.0e-18, betaHi = 0.3

        let tempsLo: [Double] = [100, 150, 200]
        let tempsHi: [Double] = [300, 400, 500]
        let allTemps = tempsLo + tempsHi

        let sweeps = tempsLo.map { t -> ThreeOmegaFieldSweepResult in
                        let rxx = rig.rxxForTemp(t)
                        return makeSweep(t: t, v3w: rig.v3w(alpha: alphaLo, beta: betaLo, rxx: rxx), rxx: rxx, iRms: 1.0)
                   }
                   + tempsHi.map { t -> ThreeOmegaFieldSweepResult in
                        let rxx = rig.rxxForTemp(t)
                        return makeSweep(t: t, v3w: rig.v3w(alpha: alphaHi, beta: betaHi, rxx: rxx), rxx: rxx, iRms: 1.0)
                   }

        let ranges: [ThreeOmegaFitRange] = [
            ThreeOmegaFitRange(tLo: 100, tHi: 200),
            ThreeOmegaFitRange(tLo: 300, tHi: 500)
        ]
        let result = uc.executeWithIRms(
            fieldSweeps: sweeps,
            rtResult: rig.rtResult(temps: allTemps),
            geometry: rig.geo,
            iRmsValues: rig.iRmsValues(temps: allTemps),
            fitRanges: ranges
        )
        #expect(result.segments.count == 2)
        #expect(!result.isSingleFullRange())

        let lo = result.segments[0]
        let hi = result.segments[1]
        // Segments should be sorted by tLo ascending
        #expect(lo.tLo < hi.tLo)

        #expect(abs(lo.alpha - alphaLo) / abs(alphaLo) < 1e-6)
        #expect(abs(lo.beta  - betaLo)  / abs(betaLo)  < 1e-6)
        #expect(abs(hi.alpha - alphaHi) / abs(alphaHi) < 1e-6)
        #expect(abs(hi.beta  - betaHi)  / abs(betaHi)  < 1e-6)
    }

    // MARK: normalisation

    @Test("Reversed tLo/tHi is silently swapped before fitting")
    func reversedBoundsSwapped() {
        let temps: [Double] = [100, 200, 300]
        let sweeps = temps.map { t in let rxx = rig.rxxForTemp(t); return makeSweep(t: t, v3w: rig.v3w(alpha: 2e-18, beta: 3e-20, rxx: rxx), rxx: rxx, iRms: 1.0) }

        // Input reversed: tLo=300, tHi=100 — should be treated as 100–300
        let ranges: [ThreeOmegaFitRange] = [ThreeOmegaFitRange(tLo: 300, tHi: 100)]
        let result = uc.executeWithIRms(
            fieldSweeps: sweeps,
            rtResult: rig.rtResult(temps: temps),
            geometry: rig.geo,
            iRmsValues: rig.iRmsValues(temps: temps),
            fitRanges: ranges
        )
        #expect(result.segments.count == 1)
        #expect(result.segments[0].pointCount == 3)
    }

    // MARK: overlap detection

    @Test("Overlapping ranges emit a warning")
    func overlappingRangesWarn() {
        let temps: [Double] = [100, 200, 300, 400]
        let sweeps = temps.map { t in let rxx = rig.rxxForTemp(t); return makeSweep(t: t, v3w: rig.v3w(alpha: 2e-18, beta: 3e-20, rxx: rxx), rxx: rxx, iRms: 1.0) }

        let ranges: [ThreeOmegaFitRange] = [
            ThreeOmegaFitRange(tLo: 100, tHi: 250),
            ThreeOmegaFitRange(tLo: 200, tHi: 400)   // overlaps at 200–250
        ]
        let result = uc.executeWithIRms(
            fieldSweeps: sweeps,
            rtResult: rig.rtResult(temps: temps),
            geometry: rig.geo,
            iRmsValues: rig.iRmsValues(temps: temps),
            fitRanges: ranges
        )
        // Both segments still fit (overlap is allowed, only warned)
        #expect(result.segments.count == 2)
        #expect(result.warnings.contains { $0.contains("overlap") })
    }

    // MARK: empty segment

    @Test("Range with fewer than 2 points emits a warning and is skipped")
    func tooFewPointsSkipped() {
        let temps: [Double] = [100, 200, 300]
        let sweeps = temps.map { t in let rxx = rig.rxxForTemp(t); return makeSweep(t: t, v3w: rig.v3w(alpha: 2e-18, beta: 3e-20, rxx: rxx), rxx: rxx, iRms: 1.0) }

        // Second range covers only one data point
        let ranges: [ThreeOmegaFitRange] = [
            ThreeOmegaFitRange(tLo: 100, tHi: 300),
            ThreeOmegaFitRange(tLo: 200, tHi: 200)   // exactly one point
        ]
        let result = uc.executeWithIRms(
            fieldSweeps: sweeps,
            rtResult: rig.rtResult(temps: temps),
            geometry: rig.geo,
            iRmsValues: rig.iRmsValues(temps: temps),
            fitRanges: ranges
        )
        #expect(result.segments.count == 1)
        #expect(result.warnings.contains { $0.contains("fewer than 2") })
    }

    // MARK: isSingleFullRange

    @Test("isSingleFullRange false when range covers a subset of points")
    func isSingleFullRangeSubset() {
        let temps: [Double] = [100, 200, 300, 400]
        let sweeps = temps.map { t in let rxx = rig.rxxForTemp(t); return makeSweep(t: t, v3w: rig.v3w(alpha: 2e-18, beta: 3e-20, rxx: rxx), rxx: rxx, iRms: 1.0) }

        // Narrow range → fewer points than total
        let ranges: [ThreeOmegaFitRange] = [ThreeOmegaFitRange(tLo: 100, tHi: 200)]
        let result = uc.executeWithIRms(
            fieldSweeps: sweeps,
            rtResult: rig.rtResult(temps: temps),
            geometry: rig.geo,
            iRmsValues: rig.iRmsValues(temps: temps),
            fitRanges: ranges
        )
        #expect(result.segments.count == 1)
        #expect(!result.isSingleFullRange())
    }
}
