import Foundation
import Testing
@testable import SpinLabApp

/// `EnvelopeBackgroundSlope` — shared envelope high-field background-slope algorithm.
///
/// This algorithm is workflow-agnostic (H/y arrays in, backgroundSlope + diagnostics out; no
/// AHE/3ω/plot/tab/renderer awareness) and is the single implementation used by both the
/// standalone AHE workflow (`AHEBackgroundCorrectionUseCase`) and 3ω's hysteresis preprocessing
/// (`ThreeOmegaFitUseCase`). These tests lock in the algorithm's own contract, independent of
/// either caller, plus a structural guard against the two callers re-diverging into duplicate
/// implementations.
@Suite("EnvelopeBackgroundSlope shared algorithm")
struct EnvelopeBackgroundSlopeTests {

    // MARK: - 1. Selects highest/lowest raw-mean segments correctly

    @Test("selects the segment with the largest raw meanY as high, smallest as low")
    func selectsHighestAndLowestMeanSegments() {
        // Full loop: down-sweep then up-sweep, so all four segments are populated.
        // Deliberately asymmetric per-segment offsets so meanY ranks segments unambiguously.
        // The up-sweep starts just short of -1.0 (rather than exactly at the down-sweep's last
        // value) so the turning point has a genuine nonzero backward difference — a repeated
        // field value at the reversal would give a zero diff, which the direction detector
        // resolves by inheriting the prior sweep's direction, misclassifying that one point.
        let down = stride(from: 1.0, through: -1.0, by: -0.05).map { $0 }
        let up = stride(from: -0.99, through: 1.0, by: 0.05).map { $0 }
        let H = down + up
        let y = H.enumerated().map { (i, h) -> Double in
            let isDown = i < down.count
            if h >= 0 { return (isDown ? 3.0 : 1.0) + 10.0 * h }   // posDown > posUp
            return (isDown ? -1.0 : -3.0) + 10.0 * h               // negUp < negDown
        }

        let result = EnvelopeBackgroundSlope.apply(H: H, R: y, seriesLabel: "t")

        #expect(result.diagnostics.selectedHighSegment == "posDown")
        #expect(result.diagnostics.selectedLowSegment == "negUp")
    }

    // MARK: - 2. threshold = 0.8 * max(abs(H))

    @Test("high-field threshold is 0.8 times max(abs(H)) by default")
    func thresholdIsEightyPercentOfHmaxAbs() {
        let H = stride(from: -3.0, through: 5.0, by: 0.5).map { $0 }
        let y = H.map { 2.0 * $0 }
        let result = EnvelopeBackgroundSlope.apply(H: H, R: y, seriesLabel: "t")

        #expect(result.diagnostics.hMaxAbs == 5.0)
        #expect(abs(result.diagnostics.highFieldThreshold - 0.8 * 5.0) < 1e-12)
    }

    @Test("high-field threshold honors a custom highFrac")
    func thresholdHonorsCustomHighFrac() {
        let H = stride(from: -2.0, through: 2.0, by: 0.2).map { $0 }
        let y = H.map { 2.0 * $0 }
        let result = EnvelopeBackgroundSlope.apply(H: H, R: y, seriesLabel: "t", highFrac: 0.5)

        #expect(abs(result.diagnostics.highFieldThreshold - 1.0) < 1e-12)
    }

    // MARK: - 3. Only the two selected segments are fitted

    @Test("only the selected high/low segments feed the fit; other segments' shape doesn't affect the slope")
    func onlySelectedSegmentsAreFitted() {
        let down = stride(from: 1.0, through: -1.0, by: -0.05).map { $0 }
        let up = stride(from: -0.99, through: 1.0, by: 0.05).map { $0 }
        let H = down + up

        // Zero-sum deltas (independent of exact segment length): destroys any linear shape the
        // unselected segment had, without moving its meanY — so if it were mistakenly fitted,
        // its slope would come out very different, but selection itself is untouched.
        func zeroSum(_ count: Int, magnitude: Double) -> [Double] {
            guard count > 0 else { return [] }
            let raw = (0..<count).map { $0 % 2 == 0 ? magnitude : -magnitude }
            let mean = raw.reduce(0, +) / Double(count)
            return raw.map { $0 - mean }
        }

        func makeY(posUpDelta: Double, negDownDelta: Double) -> [Double] {
            let posUpCount = up.filter { $0 >= 0.8 }.count
            let negDownCount = down.filter { $0 <= -0.8 }.count
            let posUpDeltas = zeroSum(posUpCount, magnitude: posUpDelta)
            let negDownDeltas = zeroSum(negDownCount, magnitude: negDownDelta)
            var posUpSeen = 0
            var negDownSeen = 0
            return H.enumerated().map { (i, h) -> Double in
                let isDown = i < down.count
                if h >= 0.8 {
                    if isDown { return 5.0 + 10.0 * h }          // posDown: highest meanY
                    let d = posUpDeltas[posUpSeen]; posUpSeen += 1
                    return 1.0 + 10.0 * h + d                    // posUp: unselected
                }
                if h <= -0.8 {
                    if !isDown {
                        return -5.0 + 10.0 * h                   // negUp: lowest meanY
                    }
                    let d = negDownDeltas[negDownSeen]; negDownSeen += 1
                    return -1.0 + 10.0 * h + d                   // negDown: unselected
                }
                return 10.0 * h
            }
        }

        let base = EnvelopeBackgroundSlope.apply(H: H, R: makeY(posUpDelta: 0, negDownDelta: 0), seriesLabel: "t")
        #expect(base.diagnostics.selectedHighSegment == "posDown")
        #expect(base.diagnostics.selectedLowSegment == "negUp")

        let perturbed = EnvelopeBackgroundSlope.apply(
            H: H, R: makeY(posUpDelta: 2_000_000.0, negDownDelta: 2_000_000.0), seriesLabel: "t"
        )

        #expect(perturbed.diagnostics.selectedHighSegment == "posDown")
        #expect(perturbed.diagnostics.selectedLowSegment == "negUp")
        #expect(abs(perturbed.diagnostics.backgroundSlope - base.diagnostics.backgroundSlope) < 1e-9)
    }

    // MARK: - 4. Returns one common slope

    @Test("backgroundSlope is a single value applied uniformly to every point")
    func returnsOneCommonSlope() {
        let down = stride(from: 1.0, through: -1.0, by: -0.1).map { $0 }
        let up = stride(from: -1.0, through: 1.0, by: 0.1).map { $0 }
        let H = down + up
        let y = H.map { 7.5 * $0 }

        let result = EnvelopeBackgroundSlope.apply(H: H, R: y, seriesLabel: "t")

        #expect(abs(result.diagnostics.backgroundSlope - 0.5 * ((result.diagnostics.slopeHigh ?? 0) + (result.diagnostics.slopeLow ?? 0))) < 1e-9)

        // Same single slope subtracted at every point: yCorrected(h) = y(h) - backgroundSlope*h.
        for (h, yc) in zip(H, result.correctedY) {
            let expected = (7.5 * h) - result.diagnostics.backgroundSlope * h
            #expect(abs(yc - expected) < 1e-6)
        }
    }

    // MARK: - 5. Fallback triggers with fewer than two valid segments

    @Test("falls back to the branch-sign-only method when fewer than two candidate segments qualify")
    func fallsBackWithInsufficientSegments() {
        // Single monotonic sweep with too few high-field points per direction/sign combo to
        // reach the default minSegmentPoints (3): only 1 point at each extreme.
        let H = [-1.0, -0.5, 0.0, 0.5, 1.0]
        let y = H.map { 4.0 * $0 }

        let result = EnvelopeBackgroundSlope.apply(H: H, R: y, seriesLabel: "t", minSegmentPoints: 3)

        #expect(result.diagnostics.fallback)
        #expect(result.diagnostics.selectedHighSegment == nil)
        #expect(result.diagnostics.selectedLowSegment == nil)

        let expectedFallback = LinearBackgroundCorrection.subtractLinearBackground(
            H: H, R: y, highFrac: 0.70, minHighFieldPoints: 3
        )
        #expect(result.correctedY == expectedFallback)
    }

    @Test("fallback also triggers on mismatched or empty input arrays")
    func fallsBackOnDegenerateInput() {
        let result = EnvelopeBackgroundSlope.apply(H: [], R: [], seriesLabel: "t")
        #expect(result.diagnostics.fallback)
        #expect(result.correctedY.isEmpty)
    }

    // MARK: - 6. Both AHE and 3ω callers use this same shared utility, not duplicated code

    @Test("AHEBackgroundCorrectionUseCase and ThreeOmegaFitUseCase both call EnvelopeBackgroundSlope.apply, and no second implementation exists")
    func bothWorkflowsShareOneImplementation() throws {
        let aheSrc = try Self.source(at: "Sources/SpinLabApp/UseCases/AHEBackgroundCorrectionUseCase.swift")
        let threeOmegaSrc = try Self.source(at: "Sources/SpinLabApp/UseCases/ThreeOmegaFitUseCase.swift")

        #expect(aheSrc.contains("EnvelopeBackgroundSlope.apply"), "AHE correction must call the shared envelope algorithm")
        #expect(threeOmegaSrc.contains("EnvelopeBackgroundSlope.apply"), "3ω hysteresis preprocessing must call the shared envelope algorithm")

        // Neither caller may re-implement segment selection locally.
        for src in [aheSrc, threeOmegaSrc] {
            #expect(!src.contains("posUp"), "Segment-direction logic must live only in EnvelopeBackgroundSlope, not be duplicated in a caller")
            #expect(!src.contains("segmentOrder"), "Segment ordering must live only in EnvelopeBackgroundSlope, not be duplicated in a caller")
        }

        // Exactly one type declaration of the algorithm exists in the codebase.
        let useCasesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SpinLabApp/UseCases")
        let swiftFiles = try FileManager.default.contentsOfDirectory(at: useCasesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        var declarationCount = 0
        for file in swiftFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            if contents.contains("enum EnvelopeBackgroundSlope {") {
                declarationCount += 1
            }
        }
        #expect(declarationCount == 1, "EnvelopeBackgroundSlope must be declared exactly once")
    }

    // MARK: - Source-inspection helper

    private static func source(at relativePath: String) throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SpinLabAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let url = base.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
