import Foundation
import Testing
@testable import SpinLabApp

// MARK: - v4.1.12 — ThreeOmegaScalingUseCase V3 method selection regression tests
//
// Coverage:
//   - .highField uses v3omegaFit when present
//   - .highField falls back to v3omegaWindow when v3omegaFit is nil
//   - .window always uses v3omegaWindow regardless of v3omegaFit
//   - Cross-check warning emitted when fit and window diverge > 20%
//   - No warning when divergence ≤ 20%

// MARK: - Helpers

/// Builds a sweep with explicit control over v3omegaFit and v3omegaWindow.
private func makeSweepWithFit(
    t: Double,
    v3window: Double,
    v3fit: Double?,
    rxx: Double
) -> ThreeOmegaFieldSweepResult {
    ThreeOmegaFieldSweepResult(
        temperatureK: t,
        device: "0deg",
        hField: [-100, 0, 100],
        r1omega: [-rxx, 0, rxx],
        r3omega: [0, 0, 0],
        // Must match the iRms=1 assumption in `expectedScalingY` / `geo` doc below —
        // ThreeOmegaScalingUseCase derives E_xx from this per-sweep value.
        iRms: 1.0,
        rahe1omega: nil, rahe1omegaWA: nil,
        hc1omega: nil, hc3omega: nil,
        v3omegaWindow: v3window,
        v3omegaFit: v3fit
    )
}

/// Minimal geometry: lxx=1μm, lxy=1μm, d=1nm.
/// With iRms=1A and Rxx known, derivations are:
///   ρ_xx   = Rxx × 1e-9
///   σ_xx   = 1e9 / Rxx
///   E_xx   = Rxx × 1e6
///   E_xx³  = Rxx³ × 1e18
///   scalingY = (v3ahe / 1e-6) / (Rxx³ × 1e18 × 1e9 / Rxx)
///            = v3ahe / (Rxx² × 1e15)
private let geo = ThreeOmegaGeometry(lxx: 1, lxy: 1, dNm: 1)

/// Compute expected scalingY for a given v3ahe and Rxx with unit geometry + iRms=1.
private func expectedScalingY(v3ahe: Double, rxx: Double) -> Double {
    // E3w_AHE = v3ahe / lxy_m = v3ahe / 1e-6 = v3ahe × 1e6
    // E_xx    = iRms × rxx / lxx_m = 1 × rxx / 1e-6 = rxx × 1e6
    // E_xx³   = rxx³ × 1e18
    // σ_xx    = 1 / (rxx × d_m × lxy_m / lxx_m) = 1 / (rxx × 1e-9) = 1e9 / rxx
    // scalingY = E3w_AHE / (E_xx³ × σ_xx)
    //          = (v3ahe × 1e6) / (rxx³ × 1e18 × 1e9 / rxx)
    //          = (v3ahe × 1e6) / (rxx² × 1e27)
    //          = v3ahe / (rxx² × 1e21)
    v3ahe / (rxx * rxx * 1e21)
}

@Suite("V4112 ThreeOmegaScalingUseCase — V3 method selection")
struct V4112ThreeOmegaV3MethodTests {

    let uc = ThreeOmegaScalingUseCase()

    // Two temperatures so OLS can fit.
    let temps: [Double] = [100, 200]
    let rxxValues: [Double] = [1.0, 2.0]  // Rxx = T/100

    // Distinct v3 values so we can tell which was used.
    let v3window: [Double] = [1.0e-6, 2.0e-6]
    let v3fit:    [Double] = [1.5e-6, 3.0e-6]

    private func rt() -> ThreeOmegaRTResult {
        ThreeOmegaRTResult(device: "0deg", temperatureK: temps, rxx: rxxValues)
    }

    private func iRms() -> [Double: Double] {
        Dictionary(uniqueKeysWithValues: temps.map { ($0, 1.0) })
    }

    // MARK: - .highField uses v3omegaFit when present

    @Test("highField method uses v3omegaFit over v3omegaWindow")
    func highFieldUsesFit() {
        let sweeps = zip(temps, zip(rxxValues, zip(v3window, v3fit))).map { (t, pair) in
            let (rxx, (w, f)) = pair
            return makeSweepWithFit(t: t, v3window: w, v3fit: f, rxx: rxx)
        }

        let result = uc.executeWithIRms(
            fieldSweeps: sweeps,
            rtResult: rt(),
            geometry: geo,
            iRmsValues: iRms(),
            v3Method: .highField
        )

        #expect(result.points.count == 2)
        for (i, pt) in result.points.enumerated() {
            let expected = expectedScalingY(v3ahe: v3fit[i], rxx: rxxValues[i])
            #expect(abs(pt.scalingY - expected) / abs(expected) < 1e-9,
                    "Point \(i): scalingY should use v3omegaFit")
        }
    }

    // MARK: - .highField falls back when v3omegaFit is nil

    @Test("highField method falls back to v3omegaWindow when fit is nil")
    func highFieldFallsBackToWindow() {
        let sweeps = zip(temps, zip(rxxValues, v3window)).map { (t, pair) in
            let (rxx, w) = pair
            return makeSweepWithFit(t: t, v3window: w, v3fit: nil, rxx: rxx)
        }

        let result = uc.executeWithIRms(
            fieldSweeps: sweeps,
            rtResult: rt(),
            geometry: geo,
            iRmsValues: iRms(),
            v3Method: .highField
        )

        #expect(result.points.count == 2)
        for (i, pt) in result.points.enumerated() {
            let expected = expectedScalingY(v3ahe: v3window[i], rxx: rxxValues[i])
            #expect(abs(pt.scalingY - expected) / abs(expected) < 1e-9,
                    "Point \(i): scalingY should fall back to v3omegaWindow")
        }
    }

    // MARK: - .window ignores v3omegaFit

    @Test("window method uses v3omegaWindow even when fit is available")
    func windowIgnoresFit() {
        let sweeps = zip(temps, zip(rxxValues, zip(v3window, v3fit))).map { (t, pair) in
            let (rxx, (w, f)) = pair
            return makeSweepWithFit(t: t, v3window: w, v3fit: f, rxx: rxx)
        }

        let result = uc.executeWithIRms(
            fieldSweeps: sweeps,
            rtResult: rt(),
            geometry: geo,
            iRmsValues: iRms(),
            v3Method: .window
        )

        #expect(result.points.count == 2)
        for (i, pt) in result.points.enumerated() {
            let expected = expectedScalingY(v3ahe: v3window[i], rxx: rxxValues[i])
            #expect(abs(pt.scalingY - expected) / abs(expected) < 1e-9,
                    "Point \(i): scalingY should use v3omegaWindow, not fit")
        }
    }

    // MARK: - Divergence warning

    @Test("Warning emitted when fit and window diverge by more than 20%")
    func divergenceWarning() {
        // v3fit = 2.0e-6, v3window = 1.0e-6 → 100% divergence
        let sweeps = [
            makeSweepWithFit(t: 100, v3window: 1.0e-6, v3fit: 2.0e-6, rxx: 1.0),
            makeSweepWithFit(t: 200, v3window: 2.0e-6, v3fit: 4.0e-6, rxx: 2.0),
        ]

        let result = uc.executeWithIRms(
            fieldSweeps: sweeps,
            rtResult: rt(),
            geometry: geo,
            iRmsValues: iRms(),
            v3Method: .highField
        )

        #expect(result.warnings.contains { $0.contains("diverge") },
                "Should warn about >20% divergence between fit and window methods")
    }

    @Test("No warning when fit and window are within 20%")
    func noDivergenceWarningWithinThreshold() {
        // v3fit = 1.1e-6, v3window = 1.0e-6 → 9% divergence
        let sweeps = [
            makeSweepWithFit(t: 100, v3window: 1.0e-6, v3fit: 1.1e-6, rxx: 1.0),
            makeSweepWithFit(t: 200, v3window: 2.0e-6, v3fit: 2.1e-6, rxx: 2.0),
        ]

        let result = uc.executeWithIRms(
            fieldSweeps: sweeps,
            rtResult: rt(),
            geometry: geo,
            iRmsValues: iRms(),
            v3Method: .highField
        )

        #expect(!result.warnings.contains { $0.contains("diverge") },
                "Should not warn when divergence is ≤ 20%")
    }
}
