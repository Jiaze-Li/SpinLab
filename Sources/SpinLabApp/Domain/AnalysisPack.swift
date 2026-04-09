import Foundation

/// A saved snapshot of workbench analysis — config + results, workflow-agnostic envelope.
/// The `config` and `result` blobs are workflow-specific JSON (e.g. ThreeOmegaPackConfig / ThreeOmegaPackResult).
struct AnalysisPack: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    var label: String
    let workflowID: String
    let createdAt: Date
    var filePaths: [String]
    var sampleKeys: [String]
    /// Identity fingerprint derived from sorted input file paths + RT file path.
    /// Two packs with the same fingerprint are considered the "same analysis source".
    var sourceFingerprint: String
    /// Workflow-specific configuration JSON (e.g. ThreeOmegaPackConfig).
    var config: Data
    /// Workflow-specific result JSON (e.g. ThreeOmegaPackResult).
    var result: Data

    /// Builds a fingerprint from input files and optional RT file path.
    static func makeFingerprint(inputFiles: [String], rtFilePath: String?) -> String {
        var parts = inputFiles.sorted()
        if let rt = rtFilePath { parts.append("RT:" + rt) }
        return parts.joined(separator: "\n")
    }

    /// Convenience init that encodes typed config/result into JSON Data.
    init<C: Encodable, R: Encodable>(
        id: UUID = UUID(),
        label: String,
        workflowID: String,
        createdAt: Date = Date(),
        filePaths: [String],
        sampleKeys: [String],
        sourceFingerprint: String = "",
        config: C,
        result: R
    ) throws {
        self.id = id
        self.label = label
        self.workflowID = workflowID
        self.createdAt = createdAt
        self.filePaths = filePaths
        self.sampleKeys = sampleKeys
        self.sourceFingerprint = sourceFingerprint
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        self.config = try encoder.encode(config)
        self.result = try encoder.encode(result)
    }

    /// Raw init with pre-encoded Data blobs.
    init(
        id: UUID = UUID(),
        label: String,
        workflowID: String,
        createdAt: Date = Date(),
        filePaths: [String],
        sampleKeys: [String],
        sourceFingerprint: String = "",
        config: Data,
        result: Data
    ) {
        self.id = id
        self.label = label
        self.workflowID = workflowID
        self.createdAt = createdAt
        self.filePaths = filePaths
        self.sampleKeys = sampleKeys
        self.sourceFingerprint = sourceFingerprint
        self.config = config
        self.result = result
    }

    /// Decode the config blob into a typed struct.
    func decodeConfig<C: Decodable>(_ type: C.Type) throws -> C {
        try JSONDecoder().decode(type, from: config)
    }

    /// Decode the result blob into a typed struct.
    func decodeResult<R: Decodable>(_ type: R.Type) throws -> R {
        try JSONDecoder().decode(type, from: result)
    }
}
