import Foundation
import Testing
@testable import SpinLabApp

// MARK: - v5.3.8 — ThreeOmegaScalingUseCase uses each sweep's own I_rms
//
// Regression guard for the temperature-keyed `iRmsValues` collision bug:
// when two devices (angles) share a temperature, the legacy
// `iRmsValues: [temperatureK: iRms]` map could only hold one current for that
// temperature, so every same-temperature sweep was forced to reuse it. Because
// Y ∝ 1 / E_xx³ and E_xx ∝ I_rms, a wrong current directly corrupts α and β.
//
// ThreeOmegaScalingUseCase now derives E_xx from `ThreeOmegaFieldSweepResult.iRms`
// (carried through ingestion from the LVM file) and ignores the map entirely.

@Suite("V538 ThreeOmegaScalingUseCase — per-sweep I_rms")
struct V538ThreeOmegaScalingPerSweepIRmsTests {

    // Unit geometry: lxx = lxy = 1 μm, d = 1 nm.
    //   d_m = 1e-9, lxx_m = lxy_m = 1e-6
    //   ρ_xx     = Rxx × (d_m × lxy_m / lxx_m) = Rxx × 1e-9
    //   σ_xx     = 1 / ρ_xx = 1e9 / Rxx
    //   E_xx     = iRms × Rxx / lxx_m = iRms × Rxx × 1e6
    //   E3ω_AHE  = v3ω / lxy_m = v3ω × 1e6
    //   scalingY = E3ω_AHE / (E_xx³ × σ_xx) = v3ω / (iRms³ × Rxx² × 1e21)
    private let geo = ThreeOmegaGeometry(lxx: 1, lxy: 1, dNm: 1)

    private func expectedScalingY(v3w: Double, iRms: Double, rxx: Double) -> Double {
        v3w / (iRms * iRms * iRms * rxx * rxx * 1e21)
    }

    private func makeSweep(device: String, t: Double, rxx: Double, iRms: Double, v3w: Double)
        -> ThreeOmegaFieldSweepResult
    {
        ThreeOmegaFieldSweepResult(
            temperatureK: t,
            device: device,
            hField: [-100, 0, 100],
            r1omega: [-rxx, 0, rxx],
            r3omega: [0, 0, 0],
            iRms: iRms,
            rahe1omega: nil, rahe1omegaWA: nil,
            hc1omega: nil, hc3omega: nil,
            v3omegaWindow: v3w,
            v3omegaFit: nil
        )
    }

    @Test("Two devices at the same temperature each use their own I_rms, not the legacy map")
    func sameTemperatureDistinctIRms() {
        let uc = ThreeOmegaScalingUseCase()

        let t = 50.0
        let rxx = 0.5                 // Rxx(50 K)
        let v3w = 1.0e-9             // identical extraction for both devices
        let iRmsA = 1.0e-3          // device_0deg
        let iRmsB = 2.0e-3          // device_30deg  (A ≠ B)

        let sweeps = [
            makeSweep(device: "device_0deg",  t: t, rxx: rxx, iRms: iRmsA, v3w: v3w),
            makeSweep(device: "device_30deg", t: t, rxx: rxx, iRms: iRmsB, v3w: v3w),
        ]
        let rt = ThreeOmegaRTResult(device: "sample", temperatureK: [50.0, 60.0], rxx: [0.5, 0.6])

        // Deliberately hostile legacy map: a single wrong current for T = 50 K that
        // matches neither sweep. The old implementation would apply this to both points.
        let poisonedMap: [Double: Double] = [50.0: 5.0e-3]

        let result = uc.executeWithIRms(
            fieldSweeps: sweeps,
            rtResult: rt,
            geometry: geo,
            iRmsValues: poisonedMap
        )

        #expect(result.points.count == 2)

        let expectedA = expectedScalingY(v3w: v3w, iRms: iRmsA, rxx: rxx)   // 4e-21
        let expectedB = expectedScalingY(v3w: v3w, iRms: iRmsB, rxx: rxx)   // 5e-22
        let poisoned  = expectedScalingY(v3w: v3w, iRms: 5.0e-3, rxx: rxx)  // old impl → both points

        let ys = result.points.map(\.scalingY).sorted()

        // New behaviour: two distinct Y values, each from its own sweep's current.
        #expect(Set(result.points.map(\.scalingY)).count == 2)
        #expect(abs(ys[0] - min(expectedA, expectedB)) / min(expectedA, expectedB) < 1e-6)
        #expect(abs(ys[1] - max(expectedA, expectedB)) / max(expectedA, expectedB) < 1e-6)
        #expect(abs(expectedA / expectedB - 8.0) < 1e-9)   // ratio (iRmsB/iRmsA)³ = 8

        // Old (buggy) behaviour would have produced the poisoned value for both points.
        for y in result.points.map(\.scalingY) {
            #expect(abs(y - poisoned) / poisoned > 1e-3)
        }
    }

    @Test("Single-device sweeps are unaffected — Y matches the sweep's own I_rms")
    func singleDeviceUnchanged() {
        let uc = ThreeOmegaScalingUseCase()

        let temps: [Double] = [100, 200]
        let rxxByT: [Double: Double] = [100: 1.0, 200: 2.0]
        let iRms = 1.5e-3
        let v3w: [Double: Double] = [100: 1.0e-9, 200: 2.0e-9]

        let sweeps = temps.map { t in
            makeSweep(device: "0deg", t: t, rxx: rxxByT[t]!, iRms: iRms, v3w: v3w[t]!)
        }
        let rt = ThreeOmegaRTResult(device: "0deg", temperatureK: temps, rxx: [1.0, 2.0])

        let result = uc.executeWithIRms(fieldSweeps: sweeps, rtResult: rt, geometry: geo)

        #expect(result.points.count == 2)
        for point in result.points {
            let expected = expectedScalingY(v3w: v3w[point.temperatureK]!, iRms: iRms,
                                            rxx: rxxByT[point.temperatureK]!)
            #expect(abs(point.scalingY - expected) / abs(expected) < 1e-6)
        }
        #expect(result.warnings.isEmpty)
    }
}
