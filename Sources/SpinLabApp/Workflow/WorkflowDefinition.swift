import Foundation

struct WorkflowDefinition: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String
    var conditionFields: [WorkflowConditionField]
}

struct WorkflowConditionField: Codable, Hashable, Sendable {
    var definitionID: String

    init(definitionID: String) {
        self.definitionID = definitionID
    }

    private enum CodingKeys: String, CodingKey {
        case definitionID
        case key
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Backward compatibility: old schema used `key`, new schema uses `definitionID`.
        let normalizedDefinitionID = (
            try container.decodeIfPresent(String.self, forKey: .definitionID)
            ?? container.decodeIfPresent(String.self, forKey: .key)
            ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        self.definitionID = normalizedDefinitionID
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(definitionID, forKey: .definitionID)
    }
}
