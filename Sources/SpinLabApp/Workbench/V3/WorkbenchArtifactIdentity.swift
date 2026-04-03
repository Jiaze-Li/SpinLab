import CryptoKit
import Foundation

private struct CanonicalChartIdentityPayload: Codable {
    var workflowID: String
    var inputFiles: [String]
    var axisMapping: WorkbenchAxisMapping
    var semanticParams: [String: String]
}

private struct CanonicalMetricIdentityPayload: Codable {
    var sampleKey: String
    var workflowID: String
    var metric: String
    var conditions: [String: String]
}

enum WorkbenchChartIdentity {
    static func makeIdentityKey(from payload: WorkbenchPlotPayload) -> String {
        let sourceFiles = payload.series.compactMap(\.sourceRef)
        return makeIdentityKey(
            workflowID: payload.workflowID,
            inputFiles: sourceFiles,
            axisMapping: payload.axisMapping,
            semanticParams: payload.semanticParams
        )
    }

    static func makeIdentityKey(
        workflowID: String,
        inputFiles: [String],
        axisMapping: WorkbenchAxisMapping,
        semanticParams: [String: String]
    ) -> String {
        let canonicalInput = CanonicalChartIdentityPayload(
            workflowID: normalizeToken(workflowID),
            inputFiles: normalizePaths(inputFiles),
            axisMapping: WorkbenchAxisMapping(
                xField: normalizeToken(axisMapping.xField),
                yField: normalizeToken(axisMapping.yField)
            ),
            semanticParams: normalizeDictionary(semanticParams)
        )

        return "chart_\(hashHex(for: canonicalInput))"
    }
}

enum WorkbenchMetricIdentity {
    static func makeIdentityKey(
        sampleKey: String,
        workflowID: String,
        metric: String,
        conditions: [String: String]
    ) -> String {
        let canonicalInput = CanonicalMetricIdentityPayload(
            sampleKey: normalizeToken(sampleKey),
            workflowID: normalizeToken(workflowID),
            metric: normalizeToken(metric),
            conditions: normalizeDictionary(conditions)
        )
        return "metric_\(hashHex(for: canonicalInput))"
    }
}

private func normalizeToken(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func normalizeDictionary(_ value: [String: String]) -> [String: String] {
    value.reduce(into: [:]) { partial, entry in
        partial[normalizeToken(entry.key)] = normalizeToken(entry.value)
    }
}

private func normalizePaths(_ paths: [String]) -> [String] {
    let normalized = paths
        .map { normalizePath($0) }
        .filter { !$0.isEmpty }
    return Array(Set(normalized)).sorted()
}

private func normalizePath(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "/")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

private func hashHex<T: Encodable>(for value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = (try? encoder.encode(value)) ?? Data()
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}
