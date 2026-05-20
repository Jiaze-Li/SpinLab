import Foundation

/// Extracts AHE Hc and R_AHE metrics from sweep series with label-derived metadata.
struct ExtractAHEMetricsUseCase {

    static func extractAHEMetricsPerSeries(
        from series: [WorkbenchPlotSeries]
    ) -> Result<[String: AHEExtractedMetric], AHEMetricExtractionError> {
        var result: [String: AHEExtractedMetric] = [:]
        var failedLabels: [String] = []
        for s in series {
            guard let key = s.sampleID else {
                failedLabels.append(s.label.isEmpty ? "<empty>" : s.label)
                continue
            }
            guard result[key] == nil else { continue }
            let (hc, rAHE) = extractSingleSeriesMetrics(s)
            result[key] = AHEExtractedMetric(sampleKey: key, hc: hc, rAHE: rAHE)
        }
        guard failedLabels.isEmpty else {
            return .failure(.unparseableLabels(failedLabels))
        }
        return .success(result)
    }

    static func parseSampleKey(from label: String) -> String? {
        let segment = label.components(separatedBy: " | ").first?.trimmingCharacters(in: .whitespaces)
        guard let key = segment, !key.isEmpty else { return nil }
        return key
    }

    static func extractSingleSeriesMetrics(
        _ series: WorkbenchPlotSeries
    ) -> (hc: Double, rAHE: Double) {
        guard series.x.count > 1 else { return (0.0, 0.0) }
        let xs = series.x
        let rawYs = series.y

        let yMin = rawYs.min()!
        let yMax = rawYs.max()!
        let threshold = (yMin + yMax) / 2.0
        let ys = rawYs.map { $0 - threshold }

        var crossings: [Double] = []
        for i in 0..<xs.count - 1 {
            let y0 = ys[i], y1 = ys[i + 1]
            if y0 * y1 <= 0, y0 != y1 {
                let t = y0 / (y0 - y1)
                crossings.append(xs[i] + t * (xs[i + 1] - xs[i]))
            }
        }

        let hc: Double
        if crossings.isEmpty {
            var minAbs = Double.infinity
            var result = 0.0
            for i in 0..<xs.count {
                let a = abs(ys[i])
                if a < minAbs { minAbs = a; result = xs[i] }
            }
            hc = abs(result)
        } else {
            let posCrossings = crossings.filter { $0 > 0 }
            let negCrossings = crossings.filter { $0 < 0 }
            if !posCrossings.isEmpty && !negCrossings.isEmpty {
                hc = (posCrossings.max()! + abs(negCrossings.min()!)) / 2.0
            } else {
                hc = crossings.map { abs($0) }.reduce(0, +) / Double(crossings.count)
            }
        }

        let hMax = xs.map { abs($0) }.max() ?? 0.0
        let rAHE: Double
        if hMax > 0 {
            let satThreshold = 0.8 * hMax
            let topPlateau = zip(xs, ys).compactMap { $0.0 > satThreshold ? $0.1 : nil }
            let bottomPlateau = zip(xs, ys).compactMap { $0.0 < -satThreshold ? $0.1 : nil }
            if !topPlateau.isEmpty && !bottomPlateau.isEmpty {
                rAHE = (ExtractAHEMetricsUseCase.median(topPlateau) - ExtractAHEMetricsUseCase.median(bottomPlateau)) / 2.0
            } else {
                rAHE = (yMax - yMin) / 2.0
            }
        } else {
            rAHE = (yMax - yMin) / 2.0
        }

        return (hc, rAHE)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let n = sorted.count
        return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    }
}
