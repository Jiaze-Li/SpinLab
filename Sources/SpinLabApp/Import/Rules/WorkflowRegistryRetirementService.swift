import Foundation

struct WorkflowRegistryRetirementService {
    private let paths: RulesConfigPaths
    private let fileManager: FileManager

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()

    private let decoder = JSONDecoder()

    init(paths: RulesConfigPaths = RulesConfigPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    var outerRegistryURL: URL {
        paths.configDirectoryURL
            .deletingLastPathComponent()
            .appendingPathComponent("workflow_registry.json")
    }

    func runIfNeeded() {
        guard fileManager.fileExists(atPath: outerRegistryURL.path) else { return }
        do {
            try retire()
        } catch {
            AppLogger.shared.error(.import, "WorkflowRegistry retirement failed — outer registry left in place", metadata: [
                "reason": error.localizedDescription
            ])
        }
    }

    private func retire() throws {
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")

        let registryData = try Data(contentsOf: outerRegistryURL)
        let registryEntries: [WorkflowDefinition]
        do {
            registryEntries = try decoder.decode([WorkflowDefinition].self, from: registryData)
        } catch {
            // Backup and skip merge — outer registry is unreadable
            let backupURL = outerRegistryURL.deletingLastPathComponent()
                .appendingPathComponent("workflow_registry.json.backup-\(ts)")
            try fileManager.moveItem(at: outerRegistryURL, to: backupURL)
            AppLogger.shared.error(.import, "WorkflowRegistry retirement: outer registry undecodable; backed up without merge", metadata: [
                "reason": error.localizedDescription
            ])
            return
        }

        guard fileManager.fileExists(atPath: paths.workflowURL.path),
              let workflowData = try? Data(contentsOf: paths.workflowURL),
              var draft = try? decoder.decode(WorkflowFileDraft.self, from: workflowData) else {
            // No workflow.json — retire the outer registry without merging
            let backupURL = outerRegistryURL.deletingLastPathComponent()
                .appendingPathComponent("workflow_registry.json.backup-\(ts)")
            try fileManager.moveItem(at: outerRegistryURL, to: backupURL)
            AppLogger.shared.info(.import, "WorkflowRegistry retired (no workflow.json to merge into)", metadata: [:])
            return
        }

        for entry in registryEntries {
            let entryConditionFieldIDs = entry.conditionFields.map(\.definitionID)
            if let idx = draft.workflows.firstIndex(where: {
                $0.id.caseInsensitiveCompare(entry.id) == .orderedSame
            }) {
                // Same ID: update displayName + conditionFieldIDs, preserve matchRules
                draft.workflows[idx].displayName = entry.displayName
                draft.workflows[idx].conditionFieldIDs = entryConditionFieldIDs
            } else {
                // Registry-only ID: append with empty matchRules to avoid routing side effects
                draft.workflows.append(WorkflowFileDraft.WorkflowEntry(
                    id: entry.id,
                    displayName: entry.displayName,
                    matchRules: [],
                    conditionFieldIDs: entryConditionFieldIDs
                ))
            }
        }

        let mergedData = try encoder.encode(draft)

        // Backup workflow.json before overwriting
        let workflowBackupURL = paths.workflowURL
            .appendingPathExtension("backup-\(ts)")
        try fileManager.copyItem(at: paths.workflowURL, to: workflowBackupURL)

        // Atomic write merged workflow.json
        try mergedData.write(to: paths.workflowURL, options: .atomic)

        // Retire outer registry
        let registryBackupURL = outerRegistryURL.deletingLastPathComponent()
            .appendingPathComponent("workflow_registry.json.backup-\(ts)")
        try fileManager.moveItem(at: outerRegistryURL, to: registryBackupURL)

        AppLogger.shared.info(.import, "WorkflowRegistry retired: merged \(registryEntries.count) entries into workflow.json", metadata: [
            "backup": registryBackupURL.lastPathComponent
        ])
    }
}
