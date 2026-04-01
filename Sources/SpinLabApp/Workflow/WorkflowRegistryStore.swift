import Foundation

final class WorkflowRegistryStore {
    private let fileManager: FileManager
    private let registryFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private(set) var definitions: [WorkflowDefinition] = []

    init(
        fileManager: FileManager = .default,
        registryFileURL: URL = WorkflowRegistryStore.defaultRegistryFileURL(fileManager: .default)
    ) {
        self.fileManager = fileManager
        self.registryFileURL = registryFileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    @discardableResult
    func load() -> [WorkflowDefinition] {
        do {
            if fileManager.fileExists(atPath: registryFileURL.path) {
                let data = try Data(contentsOf: registryFileURL)
                let decoded = try decoder.decode([WorkflowDefinition].self, from: data)
                definitions = normalize(decoded)
            }

            if definitions.isEmpty {
                definitions = Self.seededDefaults()
                try save()
            }
        } catch {
            definitions = Self.seededDefaults()
            try? save()
        }

        return definitions
    }

    func save() throws {
        let parentURL = registryFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentURL.path) {
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        }

        let normalized = normalize(definitions)
        let data = try encoder.encode(normalized)
        try data.write(to: registryFileURL, options: .atomic)
        definitions = normalized
    }

    func add(_ definition: WorkflowDefinition) {
        definitions.removeAll { $0.id.caseInsensitiveCompare(definition.id) == .orderedSame }
        definitions.append(definition)
        definitions = normalize(definitions)
        try? save()
    }

    func remove(id: String) {
        definitions.removeAll { $0.id.caseInsensitiveCompare(id) == .orderedSame }
        definitions = normalize(definitions)
        try? save()
    }

    func update(_ definition: WorkflowDefinition) {
        guard let index = definitions.firstIndex(where: { $0.id.caseInsensitiveCompare(definition.id) == .orderedSame }) else {
            add(definition)
            return
        }
        definitions[index] = definition
        definitions = normalize(definitions)
        try? save()
    }

    func definition(for id: String) -> WorkflowDefinition? {
        definitions.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
    }

    static func defaultRegistryFileURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("SpinLab", isDirectory: true)
            .appendingPathComponent("workflow_registry.json")
    }

    static func seededDefaults() -> [WorkflowDefinition] {
        [
            WorkflowDefinition(
                id: "XY",
                displayName: "XY Rotation",
                parentID: nil,
                conditionFields: [
                    WorkflowConditionField(definitionID: ConditionFieldCatalog.temperatureID),
                    WorkflowConditionField(definitionID: ConditionFieldCatalog.fieldID)
                ]
            ),
            WorkflowDefinition(
                id: "RT",
                displayName: "RT",
                parentID: nil,
                conditionFields: [
                    WorkflowConditionField(definitionID: ConditionFieldCatalog.currentID)
                ]
            )
        ]
    }

    private func normalize(_ definitions: [WorkflowDefinition]) -> [WorkflowDefinition] {
        definitions
            .map { definition in
                WorkflowDefinition(
                    id: definition.id.trimmingCharacters(in: .whitespacesAndNewlines),
                    displayName: definition.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                    parentID: normalizeOptional(definition.parentID),
                    aliases: normalizeAliases(
                        definition.aliases,
                        id: definition.id,
                        displayName: definition.displayName
                    ),
                    conditionFields: definition.conditionFields.map {
                        WorkflowConditionField(
                            definitionID: $0.definitionID.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                )
            }
            .filter { !$0.id.isEmpty }
            .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    private func normalizeOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizeAliases(_ aliases: [String], id: String, displayName: String) -> [String] {
        let canonicalID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let canonicalDisplay = displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var seen: Set<String> = []
        var normalized: [String] = []
        for alias in aliases {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard key != canonicalID, key != canonicalDisplay else { continue }
            guard seen.insert(key).inserted else { continue }
            normalized.append(trimmed)
        }
        return normalized
    }
}
