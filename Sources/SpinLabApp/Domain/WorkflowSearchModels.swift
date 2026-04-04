import Foundation

struct WorkflowSearchQuery: Codable, Hashable, Sendable {
    var rawText: String

    init(rawText: String) {
        self.rawText = rawText
    }
}

struct WorkflowMeasurementSearchHit: Identifiable, Codable, Hashable, Sendable {
    var sidecarPath: String
    var measurementFilePath: String
    var sourceFilePath: String
    var workflowID: String
    var workflowDisplayName: String
    var workflowCanonicalID: String
    var batchID: String
    var sampleKey: String
    var sampleSubstrate: String
    var conditions: [String: String]
    var channels: [String]
    var appliedAt: Date

    var id: String { sidecarPath }

    var sampleBatchAndSubstrate: String {
        if let descriptor = SampleSemanticDescriptor.fromSampleKey(sampleKey),
           let batch = descriptor.batch {
            let treatment = descriptor.processingTokens.sorted().joined(separator: "+")
            let material = descriptor.material ?? ""
            let orientation = descriptor.orientation ?? ""
            let substrate = "\(material)\(orientation)"
            return [batch, treatment, substrate]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }

        if sampleSubstrate.isEmpty {
            return batchID
        }
        return "\(batchID) \(sampleSubstrate)"
    }

    var conditionSummary: String {
        guard !conditions.isEmpty else {
            return "-"
        }
        return conditions
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }
}
