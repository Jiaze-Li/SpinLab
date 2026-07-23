import Foundation

// MARK: - IVAngleDependenceUseCase
//
// Pure computation: groups sweeps by resolved angle, runs the shared
// PowerLawFitUseCase per sweep (free intercept — this module never subtracts
// the intercept, since a_n is the raw slope), sorts by angle, and reports
// duplicate-angle/insufficient-angle diagnostics. Reuses PowerLawFitUseCase;
// does not reimplement regression.

struct IVAngleDependenceUseCase {

    static let minimumDistinctAngles = 2

    /// Cheap gating helper — counts distinct valid angles without running any fits.
    /// Used by the IV workflow to decide whether Angular Plot can be enabled at all.
    static func countDistinctValidAngles(_ angles: [Double?]) -> Int {
        Set(angles.compactMap { $0 }).count
    }

    func execute(
        sweeps: [IVAngleDependenceSweepInput],
        fitMode: PowerLawFitMode
    ) -> IVAngleDependenceResult {
        guard fitMode != .none else {
            return IVAngleDependenceResult(
                points: [],
                distinctAngleCount: 0,
                isSufficient: false,
                warnings: ["Angular plot requires an active Fit mode (1ω/2ω/3ω)."]
            )
        }

        var warnings: [String] = []
        let withAngle = sweeps.filter { $0.angleDeg != nil }
        if withAngle.count < sweeps.count {
            let missing = sweeps.count - withAngle.count
            warnings.append("\(missing) sweep(s) had no resolvable angle and were excluded.")
        }

        var angleCounts: [Double: Int] = [:]
        for s in withAngle {
            angleCounts[s.angleDeg!, default: 0] += 1
        }
        let duplicated = angleCounts.filter { $0.value > 1 }
        if !duplicated.isEmpty {
            let describe = duplicated.keys.sorted().map { "\($0)°×\(angleCounts[$0]!)" }.joined(separator: ", ")
            warnings.append("Multiple sweeps share the same angle (\(describe)); all points are plotted, none merged.")
        }

        var points: [IVAngleDependencePoint] = []
        for sweep in withAngle {
            let fitPoints = zip(sweep.currentMA, sweep.voltageMV).map { PowerLawFitPoint(x: $0, y: $1) }
            let result = PowerLawFitUseCase().execute(
                input: PowerLawFitInput(points: fitPoints),
                configuration: PowerLawFitConfiguration(mode: fitMode, subtractIntercept: false)
            )
            guard result.isSuccessful, let slope = result.slope else {
                warnings.append("Fit failed for \(sweep.label) at \(sweep.angleDeg!)°; point excluded.")
                continue
            }
            points.append(IVAngleDependencePoint(angleDeg: sweep.angleDeg!, slope: slope, label: sweep.label))
        }

        points.sort { $0.angleDeg < $1.angleDeg }
        let distinctAngleCount = Self.countDistinctValidAngles(withAngle.map(\.angleDeg))
        let isSufficient = distinctAngleCount >= Self.minimumDistinctAngles
        if !isSufficient {
            warnings.append("Angular plot needs at least \(Self.minimumDistinctAngles) distinct angles; found \(distinctAngleCount).")
        }

        return IVAngleDependenceResult(
            points: points,
            distinctAngleCount: distinctAngleCount,
            isSufficient: isSufficient,
            warnings: warnings
        )
    }
}
