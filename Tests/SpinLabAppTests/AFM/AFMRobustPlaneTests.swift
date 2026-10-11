import Foundation
import Testing
@testable import SpinLabApp

@Suite("AFM Robust Plane (Huber IRLS)")
struct AFMRobustPlaneTests {

    // Real physical coordinates: offset origin, unequal pixel pitch (µm).
    private static let n = 64
    private static let xs = (0..<n).map { 3.0 + 0.08 * Double($0) }
    private static let ys = (0..<n).map { -2.0 + 0.10 * Double($0) }
    private static let a = 0.5, b = -0.3, c = 2.0   // nm per µm, nm per µm, nm

    private static func truePlane(_ x: Double, _ y: Double) -> Double { a * x + b * y + c }

    /// Deterministic ±0.05 nm noise.
    private static func noise(_ i: Int, _ j: Int) -> Double { 0.05 * sin(Double(i * 131 + j * 17) * 1.7) }

    private static func particleMask() -> [[Bool]] {
        var mask = [[Bool]](repeating: [Bool](repeating: false, count: n), count: n)
        // Six 6×6 blocks ≈ 5.3% of pixels, plus a 12×12 block → ~14% in total.
        let origins = [(5, 7), (12, 40), (30, 10), (44, 50), (50, 20), (22, 28)]
        for (r, c) in origins { for i in r..<min(r + 6, n) { for j in c..<min(c + 6, n) { mask[i][j] = true } } }
        for i in 36..<48 { for j in 30..<42 { mask[i][j] = true } }
        return mask
    }

    private static func synthetic(particleHeight: Double = 20) -> (values: [[Double]], mask: [[Bool]]) {
        let mask = particleMask()
        let values = (0..<n).map { i in
            (0..<n).map { j in truePlane(xs[j], ys[i]) + noise(i, j) + (mask[i][j] ? particleHeight : 0) }
        }
        return (values, mask)
    }

    private func backgroundResiduals(_ leveled: [[Double]], mask: [[Bool]]) -> [Double] {
        var out: [Double] = []
        for i in 0..<leveled.count { for j in 0..<leveled[i].count where !mask[i][j] { out.append(leveled[i][j]) } }
        return out
    }

    @Test("exact plane: residual ~0 and no warnings")
    func exactPlane() {
        let m = (0..<Self.n).map { i in (0..<Self.n).map { j in Self.truePlane(Self.xs[j], Self.ys[i]) } }
        let r = AFMRobustPlaneProcessor.apply(to: m, xCoordinates: Self.xs, yCoordinates: Self.ys)
        #expect(r.warnings.isEmpty)
        #expect(r.values.allSatisfy { $0.allSatisfy { abs($0) < 1e-9 } })
    }

    @Test("known background + ~14% 20 nm particles: robust recovers the background, ordinary Plane is biased")
    func recoversBackgroundBetterThanPlane() {
        let (m, mask) = Self.synthetic()
        let robust = AFMRobustPlaneProcessor.apply(to: m, xCoordinates: Self.xs, yCoordinates: Self.ys)
        let plain = AFMPlaneLevelProcessor.apply(to: m, xCoordinates: Self.xs, yCoordinates: Self.ys)
        #expect(robust.warnings.isEmpty)

        let rb = backgroundResiduals(robust.values, mask: mask)
        let pb = backgroundResiduals(plain.values, mask: mask)
        let robustBias = abs(rb.reduce(0, +) / Double(rb.count))
        let plainBias = abs(pb.reduce(0, +) / Double(pb.count))
        let robustMaxErr = rb.map(abs).max()!
        // Background residual stays within the injected noise (±0.05) plus a small Huber leak.
        #expect(robustBias < 0.02, "robust background bias \(robustBias)")
        #expect(robustMaxErr < 0.15, "robust worst background error \(robustMaxErr)")
        #expect(plainBias > 1.0, "ordinary plane should be pulled up by particles (\(plainBias))")
        #expect(robustBias < plainBias / 50)
        // Particles stay clearly above the background after robust leveling.
        let particleMean = zip(robust.values.joined(), mask.joined()).filter { $0.1 }.map(\.0).reduce(0, +) / Double(mask.joined().filter { $0 }.count)
        #expect(particleMean > 19 && particleMean < 21)
    }

    @Test("recovered plane parameters match the true physical slopes")
    func recoversPhysicalSlopes() {
        let (m, _) = Self.synthetic()
        let r = AFMRobustPlaneProcessor.apply(to: m, xCoordinates: Self.xs, yCoordinates: Self.ys)
        // Leveled = measured − fitted; so fitted = measured − leveled. Compare to the true plane
        // at two far-apart background pixels (outside every particle block).
        func fitted(_ i: Int, _ j: Int) -> Double { m[i][j] - r.values[i][j] }
        let (i1, j1, i2, j2) = (0, 0, 60, 60)
        let slopeX = (fitted(i1, j2) - fitted(i1, j1)) / (Self.xs[j2] - Self.xs[j1])
        let slopeY = (fitted(i2, j1) - fitted(i1, j1)) / (Self.ys[i2] - Self.ys[i1])
        #expect(abs(slopeX - Self.a) < 0.01, "x slope \(slopeX)")
        #expect(abs(slopeY - Self.b) < 0.01, "y slope \(slopeY)")
    }

    @Test("input matrix and coordinates are never mutated; non-finite cells stay untouched and are ignored")
    func nonMutatingAndNonFinite() {
        var (m, _) = Self.synthetic()
        m[3][4] = .nan; m[10][10] = .infinity
        let (mCopy, xsCopy, ysCopy) = (m, Self.xs, Self.ys)
        let r = AFMRobustPlaneProcessor.apply(to: m, xCoordinates: Self.xs, yCoordinates: Self.ys)
        #expect(m.flatMap { $0 }.map(\.bitPattern) == mCopy.flatMap { $0 }.map(\.bitPattern))
        #expect(Self.xs == xsCopy && Self.ys == ysCopy)
        #expect(r.values[3][4].isNaN)
        #expect(r.values[10][10] == .infinity)
        #expect(r.values[0][0].isFinite)
    }

    @Test("fit failures are explicit warnings and return the data unchanged")
    func failuresWarn() {
        let few = AFMRobustPlaneProcessor.apply(to: [[1, 2]], xCoordinates: [0, 1], yCoordinates: [0])
        #expect(few.warnings.first?.contains("fewer than 3") == true)
        #expect(few.values == [[1, 2]])
        // One row => all pixels share y: collinear, degenerate plane.
        let collinear = AFMRobustPlaneProcessor.apply(to: [[1, 2, 3, 4]], xCoordinates: [0, 1, 2, 3], yCoordinates: [5])
        #expect(collinear.warnings.first?.contains("degenerate") == true)
        #expect(collinear.values == [[1, 2, 3, 4]])
        let allNaN = AFMRobustPlaneProcessor.apply(to: [[.nan, .nan], [.nan, .nan]], xCoordinates: [0, 1], yCoordinates: [0, 1])
        #expect(allNaN.warnings.isEmpty == false)
    }

    @Test("idempotent: re-leveling an already robust-leveled map changes almost nothing")
    func idempotent() {
        let (m, _) = Self.synthetic()
        let once = AFMRobustPlaneProcessor.apply(to: m, xCoordinates: Self.xs, yCoordinates: Self.ys).values
        let twice = AFMRobustPlaneProcessor.apply(to: once, xCoordinates: Self.xs, yCoordinates: Self.ys).values
        let maxDiff = zip(once.joined(), twice.joined()).map { abs($0 - $1) }.max()!
        #expect(maxDiff < 1e-6)
    }

    // MARK: pipeline / config

    private func channel(_ values: [[Double]]) -> CanonicalAFMChannel {
        CanonicalAFMChannel(id: "c", sourceIndex: 0, sourceLabel: "HeightRetrace", semanticTypeRaw: "Height", displayLabel: "Height",
                            values: values, canonicalUnit: "nm", sourceUnit: "m",
                            provenance: AFMChannelProvenance(planefit: nil, planefitOrder: nil, flattenOrder: nil, planefitOffset: nil, planefitXSlope: nil, planefitYSlope: nil))
    }

    @Test("pipeline: Off / Plane / Robust Plane are distinct, switching never accumulates, source stays original")
    func pipelineSwitching() {
        let (m, _) = Self.synthetic()
        let ch = channel(m)
        func run(_ level: AFMSurfaceLevel) -> [[Double]] {
            var cfg = AFMProcessingConfiguration(activeChannelID: "c"); cfg.surfaceLevel = level
            return AFMProcessingPipeline.process(channel: ch, xCoordinates: Self.xs, yCoordinates: Self.ys, configuration: cfg).values
        }
        let robust = run(.robustPlane), plain = run(.plane)
        #expect(run(.off) == m)
        #expect(robust != plain)
        for level in [AFMSurfaceLevel.plane, .off, .robustPlane, .plane, .robustPlane] { _ = run(level) }
        #expect(run(.robustPlane) == robust)
        #expect(run(.plane) == plain)
        #expect(ch.values == m)
    }

    @Test("pipeline surfaces Robust Plane warnings")
    func pipelineWarnings() {
        let ch = channel([[1, 2, 3, 4]])
        var cfg = AFMProcessingConfiguration(activeChannelID: "c"); cfg.surfaceLevel = .robustPlane
        let out = AFMProcessingPipeline.process(channel: ch, xCoordinates: [0, 1, 2, 3], yCoordinates: [0], configuration: cfg)
        #expect(out.warnings.contains { $0.hasPrefix("Robust Plane") })
        #expect(out.values == [[1, 2, 3, 4]])
    }

    @Test("config: default Off, robustPlane round-trips, legacy bool and old packs still decode")
    func configCompatibility() throws {
        #expect(AFMProcessingConfiguration(activeChannelID: "a").surfaceLevel == .off)
        var cfg = AFMProcessingConfiguration(activeChannelID: "a"); cfg.surfaceLevel = .robustPlane
        let data = try JSONEncoder().encode(cfg)
        #expect(String(decoding: data, as: UTF8.self).contains("\"robustPlane\""))
        #expect(try JSONDecoder().decode(AFMProcessingConfiguration.self, from: data).surfaceLevel == .robustPlane)
        #expect(try JSONDecoder().decode(AFMProcessingConfiguration.self, from: Data(#"{"activeChannelID":"a","planeLevelEnabled":true}"#.utf8)).surfaceLevel == .plane)
        #expect(try JSONDecoder().decode(AFMProcessingConfiguration.self, from: Data(#"{"activeChannelID":"a","surfaceLevel":"plane"}"#.utf8)).surfaceLevel == .plane)
        #expect(try JSONDecoder().decode(AFMProcessingConfiguration.self, from: Data(#"{"activeChannelID":"a"}"#.utf8)).surfaceLevel == .off)
    }
}
