import Foundation

/// Pure power-law regression against transformed x^n values.
///
/// The use case is workflow-agnostic and PlotSystem-agnostic. It accepts raw
/// numeric points and returns diagnostics plus line geometry. It never assigns
/// labels, units, or workflow meaning.
struct PowerLawFitUseCase {

    func execute(input: PowerLawFitInput, configuration: PowerLawFitConfiguration) -> PowerLawFitResult {
        guard configuration.mode != .none else {
            return PowerLawFitResult(
                status: .disabled,
                mode: configuration.mode,
                subtractIntercept: configuration.subtractIntercept,
                sampleCount: 0,
                slope: nil,
                intercept: nil,
                rSquared: nil,
                fitLine: nil,
                diagnostics: [
                    PowerLawFitDiagnostic(
                        code: "disabled",
                        message: "Power-law fit mode is disabled.",
                        severity: .info
                    )
                ]
            )
        }

        let exponent = configuration.mode.exponent ?? 0
        let finitePoints = input.points.filter { $0.x.isFinite && $0.y.isFinite }
        guard finitePoints.count >= configuration.minimumPointCount else {
            return failure(
                mode: configuration.mode,
                subtractIntercept: configuration.subtractIntercept,
                sampleCount: finitePoints.count,
                code: "insufficient-data",
                message: "Need at least \(configuration.minimumPointCount) finite points.",
                severity: .warning,
                status: .insufficientData
            )
        }

        let transformed = finitePoints.map { PowerLawFitPoint(x: pow($0.x, exponent), y: $0.y) }
        let valid = transformed.filter { $0.x.isFinite && $0.y.isFinite }
        guard valid.count >= configuration.minimumPointCount else {
            return failure(
                mode: configuration.mode,
                subtractIntercept: configuration.subtractIntercept,
                sampleCount: valid.count,
                code: "invalid-input",
                message: "Transformed points are not finite.",
                severity: .error,
                status: .invalidInput
            )
        }

        guard let regression = linearRegression(x: valid.map(\.x), y: valid.map(\.y)) else {
            return failure(
                mode: configuration.mode,
                subtractIntercept: configuration.subtractIntercept,
                sampleCount: valid.count,
                code: "regression-failed",
                message: "Linear regression failed for transformed x^n values.",
                severity: .error,
                status: .invalidInput
            )
        }

        let fitLine = fitLineGeometry(
            points: finitePoints,
            exponent: exponent,
            slope: regression.slope,
            intercept: regression.intercept,
            subtractIntercept: configuration.subtractIntercept,
            sampleCount: configuration.fitLineSampleCount
        )

        let adjustedIntercept = configuration.subtractIntercept ? 0.0 : regression.intercept
        let yFit = valid.map { regression.slope * $0.x + adjustedIntercept }
        let rSquared = computeRSquared(observed: valid.map(\.y), predicted: yFit)

        return PowerLawFitResult(
            status: .fitted,
            mode: configuration.mode,
            subtractIntercept: configuration.subtractIntercept,
            sampleCount: valid.count,
            slope: regression.slope,
            intercept: regression.intercept,
            rSquared: rSquared,
            fitLine: fitLine,
            diagnostics: [
                PowerLawFitDiagnostic(
                    code: "fitted",
                    message: "Fit completed with \(valid.count) point(s).",
                    severity: .info
                )
            ]
        )
    }

    private func failure(
        mode: PowerLawFitMode,
        subtractIntercept: Bool,
        sampleCount: Int,
        code: String,
        message: String,
        severity: PowerLawFitDiagnosticSeverity,
        status: PowerLawFitStatus
    ) -> PowerLawFitResult {
        PowerLawFitResult(
            status: status,
            mode: mode,
            subtractIntercept: subtractIntercept,
            sampleCount: sampleCount,
            slope: nil,
            intercept: nil,
            rSquared: nil,
            fitLine: nil,
            diagnostics: [
                PowerLawFitDiagnostic(code: code, message: message, severity: severity)
            ]
        )
    }

    private func linearRegression(x: [Double], y: [Double]) -> (slope: Double, intercept: Double)? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        let n = Double(x.count)
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXX = zip(x, x).map(*).reduce(0, +)
        let sumXY = zip(x, y).map(*).reduce(0, +)
        let denom = n * sumXX - sumX * sumX
        guard denom != 0, denom.isFinite else { return nil }
        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        guard slope.isFinite, intercept.isFinite else { return nil }
        return (slope, intercept)
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
        points: [PowerLawFitPoint],
        exponent: Double,
        slope: Double,
        intercept: Double,
        subtractIntercept: Bool,
        sampleCount: Int
    ) -> PowerLawFitLineGeometry? {
        let xs = points.map(\.x).filter { $0.isFinite }
        guard let minX = xs.min(), let maxX = xs.max(), minX.isFinite, maxX.isFinite else { return nil }
        let lo = min(minX, maxX)
        let hi = max(minX, maxX)
        guard lo.isFinite, hi.isFinite else { return nil }

        let count = max(2, sampleCount)
        let step = (hi - lo) / Double(count - 1)
        let xValues = (0..<count).map { lo + Double($0) * step }
        let transformedX = xValues.map { pow($0, exponent) }
        let yValues = transformedX.map { slope * $0 + (subtractIntercept ? 0.0 : intercept) }
        guard xValues.allSatisfy(\.isFinite), yValues.allSatisfy(\.isFinite) else { return nil }
        return PowerLawFitLineGeometry(x: xValues, y: yValues, transformedX: transformedX)
    }
}
