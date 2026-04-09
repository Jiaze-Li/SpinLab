import Testing
@testable import SpinLabApp

@Suite("V4116 ThreeOmegaFieldSweepResult.rahe(harmonic:method:)")
struct V4116ThreeOmegaRAHETests {

    private func makeSweep(
        iRms: Double = 1e-4,
        rahe1: Double? = 0.5,
        rahe1WA: Double? = 0.48,
        v3window: Double = 2e-5,
        v3fit: Double? = 1.8e-5
    ) -> ThreeOmegaFieldSweepResult {
        ThreeOmegaFieldSweepResult(
            temperatureK: 200,
            device: "0deg",
            hField: [-100, 0, 100],
            r1omega: [-1, 0, 1],
            r3omega: [0, 0, 0],
            iRms: iRms,
            rahe1omega: rahe1,
            rahe1omegaWA: rahe1WA,
            hc1omega: nil, hc3omega: nil,
            v3omegaWindow: v3window,
            v3omegaFit: v3fit
        )
    }

    // MARK: - 1ω

    @Test("rahe(1, .highField) returns rahe1omega")
    func rahe1HFE() {
        let s = makeSweep(rahe1: 0.5)
        #expect(s.rahe(harmonic: 1, method: .highField) == 0.5)
    }

    @Test("rahe(1, .window) returns rahe1omegaWA")
    func rahe1WA() {
        let s = makeSweep(rahe1WA: 0.48)
        #expect(s.rahe(harmonic: 1, method: .window) == 0.48)
    }

    // MARK: - 3ω normal

    @Test("rahe(3, .highField) uses v3omegaFit / iRms when fit exists")
    func rahe3HFENormal() {
        let s = makeSweep(iRms: 1e-4, v3window: 2e-5, v3fit: 1.8e-5)
        let expected = 1.8e-5 / 1e-4
        #expect(s.rahe(harmonic: 3, method: .highField) == expected)
    }

    @Test("rahe(3, .window) uses v3omegaWindow / iRms")
    func rahe3WA() {
        let s = makeSweep(iRms: 1e-4, v3window: 2e-5)
        let expected = 2e-5 / 1e-4
        #expect(s.rahe(harmonic: 3, method: .window) == expected)
    }

    // MARK: - 3ω HFE fallback (aligned with Scaling Law)

    @Test("rahe(3, .highField) falls back to v3omegaWindow / iRms when v3omegaFit is nil")
    func rahe3HFEFallback() {
        let s = makeSweep(iRms: 1e-4, v3window: 2e-5, v3fit: nil)
        let expected = 2e-5 / 1e-4
        #expect(s.rahe(harmonic: 3, method: .highField) == expected)
    }

    // MARK: - Edge cases

    @Test("rahe(3, .highField) returns nil when iRms ≈ 0")
    func rahe3ZeroIRms() {
        let s = makeSweep(iRms: 0)
        #expect(s.rahe(harmonic: 3, method: .highField) == nil)
    }

    @Test("rahe(3, .window) returns nil when v3omegaWindow is NaN")
    func rahe3WANaN() {
        let s = makeSweep(v3window: .nan)
        #expect(s.rahe(harmonic: 3, method: .window) == nil)
    }

    @Test("rahe returns nil for invalid harmonic")
    func raheInvalidHarmonic() {
        let s = makeSweep()
        #expect(s.rahe(harmonic: 2, method: .highField) == nil)
    }
}
