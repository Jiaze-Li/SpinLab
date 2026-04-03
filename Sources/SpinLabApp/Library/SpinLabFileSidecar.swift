import Foundation

struct SpinLabFileSidecar: Codable, Hashable, Sendable {
    var version: Int
    /// Workflow identifier (stable, matches WorkflowDefinition.id).
    var workflow: String
    /// Human-readable workflow name from the registry at the time of apply.
    /// Stored so the sidecar is self-describing even if the registry changes later.
    var workflowDisplayName: String
    var conditions: [String: String]
    var channels: [String]
    var sourceFilePath: String
    var appliedAt: Date

    enum CodingKeys: String, CodingKey {
        case version
        case workflow
        case workflowDisplayName
        case conditions
        case channels
        case sourceFilePath
        case appliedAt
    }

    init(
        workflow: String,
        workflowDisplayName: String,
        conditions: [String: String],
        channels: [String],
        sourceFilePath: String,
        appliedAt: Date
    ) {
        self.version = 1
        self.workflow = workflow
        self.workflowDisplayName = workflowDisplayName
        self.conditions = conditions
        self.channels = channels
        self.sourceFilePath = sourceFilePath
        self.appliedAt = appliedAt
    }

    // Custom decoder: old sidecars on disk lack workflowDisplayName — fall back to workflow id.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        workflow = try container.decodeIfPresent(String.self, forKey: .workflow) ?? ""
        workflowDisplayName = try container.decodeIfPresent(String.self, forKey: .workflowDisplayName) ?? ""
        conditions = try container.decodeIfPresent([String: String].self, forKey: .conditions) ?? [:]
        channels = try container.decodeIfPresent([String].self, forKey: .channels) ?? []
        sourceFilePath = try container.decodeIfPresent(String.self, forKey: .sourceFilePath) ?? ""
        appliedAt = try container.decode(Date.self, forKey: .appliedAt)
    }
}
