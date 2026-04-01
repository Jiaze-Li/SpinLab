import Foundation

struct WorkflowDefinition: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String
    var parentID: String?
    var aliases: [String]
    var conditionFields: [WorkflowConditionField]

    init(
        id: String,
        displayName: String,
        parentID: String?,
        aliases: [String] = [],
        conditionFields: [WorkflowConditionField]
    ) {
        self.id = id
        self.displayName = displayName
        self.parentID = parentID
        self.aliases = aliases
        self.conditionFields = conditionFields
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case parentID
        case aliases
        case conditionFields
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        parentID = try container.decodeIfPresent(String.self, forKey: .parentID)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        conditionFields = try container.decode([WorkflowConditionField].self, forKey: .conditionFields)
    }
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
