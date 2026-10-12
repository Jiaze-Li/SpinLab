import Foundation
import Testing
@testable import SpinLabApp

/// Characterization (not a product change): how far Plane and Robust Plane land from a known
/// background plane as raised islands cover more of the field. 20 nm islands on a 64×64 grid.
@Suite("AFM Robust Plane vs Plane: island coverage characterization")
struct AFMRobustPlaneIslandCoverageTests {

    // 8×8-pixel blocks out of 64: 6 → 9.4%, 19 → 29.7%, 32 → 50%, 45 → 70.3%.
    private static let levels: [(label: String, blocks: Int)] = [("10%", 6), ("30%", 19), ("50%", 32), ("70%", 45)]

    private func row(_ label: String, _ s: AFMLevelingCharacterization.Synthetic) -> (plane: AFMLevelingCharacterization.PlaneError, robust: AFMLevelingCharacterization.PlaneError) {
        let p = AFMLevelingCharacterization.planeError(AFMLevelingCharacterization.plane, on: s)
        let r = AFMLevelingCharacterization.planeError(AFMLevelingCharacterization.robust, on: s)
        func f(_ v: Double) -> String { String(format: "%9.4f", v) }
        print("[island-coverage] \(label) (actual \(String(format: "%.1f", s.coverage * 100))%)  Plane: rms \(f(p.rms)) max \(f(p.maxAbs)) bgBias \(f(p.backgroundBias))  |  Robust: rms \(f(r.rms)) max \(f(r.maxAbs)) bgBias \(f(r.backgroundBias))  nm")
        return (p, r)
    }

    @Test("coverage ≈10%: Robust error <= Plane error")
    func coverage10() {
        let s = AFMLevelingCharacterization.synthetic(islandBlocks: Self.levels[0].blocks)
        let (p, r) = row(Self.levels[0].label, s)
        #expect(r.rms <= p.rms, "robust \(r.rms) vs plane \(p.rms)")
    }

    @Test("coverage ≈30%: Robust error <= Plane error")
    func coverage30() {
        let s = AFMLevelingCharacterization.synthetic(islandBlocks: Self.levels[1].blocks)
        let (p, r) = row(Self.levels[1].label, s)
        #expect(r.rms <= p.rms, "robust \(r.rms) vs plane \(p.rms)")
    }

    @Test("coverage ≈50%: errors reported, no pass/fail assertion on ordering")
    func coverage50() {
        let s = AFMLevelingCharacterization.synthetic(islandBlocks: Self.levels[2].blocks)
        let (p, r) = row(Self.levels[2].label, s)
        #expect(p.rms.isFinite && r.rms.isFinite)
    }

    @Test("coverage ≈70%: errors reported, no pass/fail assertion on ordering")
    func coverage70() {
        let s = AFMLevelingCharacterization.synthetic(islandBlocks: Self.levels[3].blocks)
        let (p, r) = row(Self.levels[3].label, s)
        #expect(p.rms.isFinite && r.rms.isFinite)
    }

    @Test("synthetic generator is deterministic and hits the requested coverage")
    func generatorDeterministic() {
        for (_, blocks) in Self.levels {
            let a = AFMLevelingCharacterization.synthetic(islandBlocks: blocks)
            let b = AFMLevelingCharacterization.synthetic(islandBlocks: blocks)
            #expect(a.values == b.values)
            #expect(abs(a.coverage - Double(blocks) / 64) < 1e-12)
        }
    }
}
