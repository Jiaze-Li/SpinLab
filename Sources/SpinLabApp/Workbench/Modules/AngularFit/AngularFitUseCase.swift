import Foundation

/// Pure harmonic regression: y(Ψ) = c0 + a·cos(mΨ) + b·sin(mΨ), free intercept.
///
/// The use case is workflow-agnostic and PlotSystem-agnostic. It accepts raw
/// angle/value points (angle in degrees) and returns diagnostics plus line
/// geometry. It never assigns labels, units, or workflow meaning.
struct AngularFitUseCase {

    func execute(input: AngularFitInput, configuration: AngularFitConfiguration) -> AngularFitResult {
        guard configuration.mode != .none else {
            return AngularFitResult(
                status: .disabled,
                mode: configuration.mode,
                fold: configuration.fold,
                sampleCount: 0,
                c0: nil, a: nil, b: nil, amplitude: nil, phase: nil,
                rSquared: nil,
                fitLine: nil,
                diagnostics: [
                    AngularFitDiagnostic(code: "disabled", message: "Angular fit mode is disabled.", severity: .info)
                ]
            )
        }

        let finitePoints = input.points.filter { $0.angleDeg.isFinite && $0.value.isFinite }
        guard finitePoints.count >= configuration.minimumPointCount else {
            return failure(
                fold: configuration.fold,
                sampleCount: finitePoints.count,
                code: "insufficient-data",
                message: "Need at least \(configuration.minimumPointCount) finite points.",
                severity: .warning,
                status: .insufficientData
            )
        }

        let m = Double(configuration.fold)
        let radians = finitePoints.map { $0.angleDeg * .pi / 180.0 }
        let cosValues = radians.map { cos(m * $0) }
        let sinValues = radians.map { sin(m * $0) }
        let yValues = finitePoints.map(\.value)

        guard let coefficients = solveNormalEquations(cos: cosValues, sin: sinValues, y: yValues) else {
            return failure(
                fold: configuration.fold,
                sampleCount: finitePoints.count,
                code: "regression-failed",
                message: "Harmonic regression failed to solve.",
                severity: .error,
                status: .invalidInput
            )
        }

        let (c0, a, b) = coefficients
        let amplitude = (a * a + b * b).squareRoot()
        let phase = atan2(b, a)

        let predicted = zip(cosValues, sinValues).map { c0 + a * $0 + b * $1 }
        let rSquared = computeRSquared(observed: yValues, predicted: predicted)

        let fitLine = fitLineGeometry(
            angleDeg: finitePoints.map(\.angleDeg),
            fold: m,
            c0: c0, a: a, b: b,
            sampleCount: configuration.fitLineSampleCount
        )
        guard let fitLine else {
            return failure(
                fold: configuration.fold,
                sampleCount: finitePoints.count,
                code: "invalid-input",
                message: "Fit-line geometry is not finite.",
                severity: .error,
                status: .invalidInput
            )
        }

        return AngularFitResult(
            status: .fitted,
            mode: configuration.mode,
            fold: configuration.fold,
            sampleCount: finitePoints.count,
            c0: c0, a: a, b: b, amplitude: amplitude, phase: phase,
            rSquared: rSquared,
            fitLine: fitLine,
            diagnostics: [
                AngularFitDiagnostic(code: "fitted", message: "Fit completed with \(finitePoints.count) point(s).", severity: .info)
            ]
        )
    }

    private func failure(
        fold: Int,
        sampleCount: Int,
        code: String,
        message: String,
        severity: AngularFitDiagnosticSeverity,
        status: AngularFitStatus
    ) -> AngularFitResult {
        AngularFitResult(
            status: status,
            mode: .harmonic,
            fold: fold,
            sampleCount: sampleCount,
            c0: nil, a: nil, b: nil, amplitude: nil, phase: nil,
            rSquared: nil,
            fitLine: nil,
            diagnostics: [AngularFitDiagnostic(code: code, message: message, severity: severity)]
        )
    }

    /// Solves the 3x3 normal equations for the design matrix [1, cos(mΨ), sin(mΨ)] via Cramer's rule.
    private func solveNormalEquations(cos: [Double], sin: [Double], y: [Double]) -> (c0: Double, a: Double, b: Double)? {
        guard cos.count == sin.count, cos.count == y.count, cos.count >= 3 else { return nil }
        let n = Double(cos.count)

        let sumCos = cos.reduce(0, +)
        let sumSin = sin.reduce(0, +)
        let sumCosCos = zip(cos, cos).map(*).reduce(0, +)
        let sumCosSin = zip(cos, sin).map(*).reduce(0, +)
        let sumSinSin = zip(sin, sin).map(*).reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumYCos = zip(y, cos).map(*).reduce(0, +)
        let sumYSin = zip(y, sin).map(*).reduce(0, +)

        // | n        sumCos    sumSin    |   |c0|   |sumY   |
        // | sumCos   sumCosCos sumCosSin | * |a | = |sumYCos|
        // | sumSin   sumCosSin sumSinSin |   |b |   |sumYSin|
        let m00 = n, m01 = sumCos, m02 = sumSin
        let m10 = sumCos, m11 = sumCosCos, m12 = sumCosSin
        let m20 = sumSin, m21 = sumCosSin, m22 = sumSinSin
        let t0 = sumY, t1 = sumYCos, t2 = sumYSin

        let det = determinant3(m00, m01, m02, m10, m11, m12, m20, m21, m22)
        guard det != 0, det.isFinite else { return nil }

        let detC0 = determinant3(t0, m01, m02, t1, m11, m12, t2, m21, m22)
        let detA = determinant3(m00, t0, m02, m10, t1, m12, m20, t2, m22)
        let detB = determinant3(m00, m01, t0, m10, m11, t1, m20, m21, t2)

        let c0 = detC0 / det
        let a = detA / det
        let b = detB / det
        guard c0.isFinite, a.isFinite, b.isFinite else { return nil }
        return (c0, a, b)
    }

    private func determinant3(
        _ a00: Double, _ a01: Double, _ a02: Double,
        _ a10: Double, _ a11: Double, _ a12: Double,
        _ a20: Double, _ a21: Double, _ a22: Double
    ) -> Double {
        a00 * (a11 * a22 - a12 * a21)
            - a01 * (a10 * a22 - a12 * a20)
            + a02 * (a10 * a21 - a11 * a20)
    }

    private func computeRSquared(observed: [Double], predicted: [Double]) -> Double? {
        guard observed.count == predicted.count, !observed.isEmpty else { return nil }
        let mean = observed.reduce(0, +) / Double(observed.count)
        let ssTot = observed.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
        let ssRes = zip(observed, predicted).map { (o, p) in
            let r = o - p
            return r * r
        }.reduce(0.0, +)
        guard ssTot > 0 else { return nil }
        let r2 = 1 - ssRes / ssTot
        return r2.isFinite ? r2 : nil
    }

    private func fitLineGeometry(
        angleDeg: [Double],
        fold: Double,
        c0: Double, a: Double, b: Double,
        sampleCount: Int
    ) -> AngularFitLineGeometry? {
        let finite = angleDeg.filter { $0.isFinite }
        guard let minAngle = finite.min(), let maxAngle = finite.max(), minAngle.isFinite, maxAngle.isFinite else { return nil }
        let lo = min(minAngle, maxAngle)
        let hi = max(minAngle, maxAngle)

        let count = max(2, sampleCount)
        let step = hi > lo ? (hi - lo) / Double(count - 1) : 0
        let angles = (0..<count).map { lo + Double($0) * step }
        let values = angles.map { angle -> Double in
            let psi = angle * .pi / 180.0
            return c0 + a * cos(fold * psi) + b * sin(fold * psi)
        }
        guard angles.allSatisfy(\.isFinite), values.allSatisfy(\.isFinite) else { return nil }
        return AngularFitLineGeometry(angleDeg: angles, value: values)
    }
}
