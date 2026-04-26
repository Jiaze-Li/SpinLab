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
            if (try? save()) == nil {
                fputs("[WorkflowRegistryStore] Failed to seed defaults: \(registryFileURL.path)\n", stderr)
            }
        }

        return definitions
    }

    func save() throws {
        try persist(normalize(definitions))
    }

    func add(_ definition: WorkflowDefinition) throws {
        var next = definitions
        next.removeAll { $0.id.caseInsensitiveCompare(definition.id) == .orderedSame }
        next.append(definition)
        try persist(normalize(next))
    }

    func remove(id: String) throws {
        var next = definitions
        next.removeAll { $0.id.caseInsensitiveCompare(id) == .orderedSame }
        try persist(normalize(next))
    }

    func update(_ definition: WorkflowDefinition) throws {
        guard let index = definitions.firstIndex(where: { $0.id.caseInsensitiveCompare(definition.id) == .orderedSame }) else {
            try add(definition)
            return
        }
        var next = definitions
        next[index] = definition
        try persist(normalize(next))
    }

    /// Encodes `next`, writes atomically to disk, then — and only then — updates `definitions`.
    /// On throw, `definitions` is unchanged; memory and disk remain consistent.
    private func persist(_ next: [WorkflowDefinition]) throws {
        let parentURL = registryFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentURL.path) {
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        }
        let data = try encoder.encode(next)
        try data.write(to: registryFileURL, options: .atomic)
        definitions = next
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
                conditionFields: [
                    WorkflowConditionField(definitionID: ConditionFieldCatalog.temperatureID),
                    WorkflowConditionField(definitionID: ConditionFieldCatalog.fieldID)
                ]
            ),
            WorkflowDefinition(
                id: "RT",
                displayName: "RT",
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
}
