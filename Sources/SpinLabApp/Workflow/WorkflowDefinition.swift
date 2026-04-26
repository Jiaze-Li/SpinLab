import Foundation

struct WorkflowDefinition: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String
    var conditionFields: [WorkflowConditionField]

    init(
        id: String,
        displayName: String,
        conditionFields: [WorkflowConditionField]
    ) {
        self.id = id
        self.displayName = displayName
        self.conditionFields = conditionFields
    }

    // migration-only: temporary compatibility for remaining call sites.
    init(
        id: String,
        displayName: String,
        parentID _: String?,
        conditionFields: [WorkflowConditionField]
    ) {
        self.init(id: id, displayName: displayName, conditionFields: conditionFields)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case parentID
        case conditionFields
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        _ = try container.decodeIfPresent(String.self, forKey: .parentID) // migration-only: drop after s6
        conditionFields = try container.decode([WorkflowConditionField].self, forKey: .conditionFields)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(conditionFields, forKey: .conditionFields)
    }

    // migration-only: temporary compatibility for remaining call sites.
    var parentID: String? {
        get { nil }
        set { _ = newValue }
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
