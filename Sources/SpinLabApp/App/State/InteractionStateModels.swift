import Foundation

enum AppArea: String, CaseIterable, Identifiable, Codable {
    case inbox = "Inbox"
    case workbench = "Workbench"
    case library = "Library"

    var id: String { rawValue }
}

enum LibrarySelectionSource: String, Codable {
    case browser
    case drawer
}

enum LibraryPendingSelectionChange: Equatable {
    case browser
    case drawer(prefix: String, batchId: String, sampleId: String?)
}

struct PendingImportConfirmationDraft: Equatable {
    static let noProjectOption = "None"

    var batchName: String
    var sampleName: String
    var measurementName: String
    /// ID matching a WorkflowDefinition.id in the WorkflowRegistry.
    var workflowID: String
    /// Condition field values keyed by WorkflowConditionField.definitionID (e.g. "temperature", "device").
    var conditionValues: [String: String]
    var selectedExistingProjectName: String
    var newProjectName: String

    var isValid: Bool {
        !sampleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !measurementName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var resolvedProjectName: String? {
        let newName = Self.normalized(newProjectName)
        if let newName {
            return newName
        }

        guard selectedExistingProjectName != Self.noProjectOption else {
            return nil
        }
        return Self.normalized(selectedExistingProjectName)
    }

    init(
        batchName: String,
        sampleName: String,
        measurementName: String,
        workflowID: String,
        conditionValues: [String: String],
        selectedExistingProjectName: String,
        newProjectName: String
    ) {
        self.batchName = batchName
        self.sampleName = sampleName
        self.measurementName = measurementName
        self.workflowID = workflowID
        self.conditionValues = conditionValues
        self.selectedExistingProjectName = selectedExistingProjectName
        self.newProjectName = newProjectName
    }

    static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension PendingImportConfirmationDraft: Codable {
    private enum CodingKeys: String, CodingKey {
        case batchName, sampleName, measurementName
        case workflowID
        case conditionValues
        case selectedExistingProjectName, newProjectName
        // Legacy keys — read-only migration path from v2.3 and earlier snapshots.
        case workflowTag, deviceName, temperature
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        batchName = try c.decodeIfPresent(String.self, forKey: .batchName) ?? ""
        sampleName = try c.decodeIfPresent(String.self, forKey: .sampleName) ?? ""
        measurementName = try c.decodeIfPresent(String.self, forKey: .measurementName) ?? ""
        selectedExistingProjectName = try c.decodeIfPresent(String.self, forKey: .selectedExistingProjectName) ?? Self.noProjectOption
        newProjectName = try c.decodeIfPresent(String.self, forKey: .newProjectName) ?? ""
        workflowID = try c.decodeIfPresent(String.self, forKey: .workflowID)
            ?? c.decodeIfPresent(String.self, forKey: .workflowTag)
            ?? ""
        if let stored = try c.decodeIfPresent([String: String].self, forKey: .conditionValues) {
            conditionValues = stored
        } else {
            var migrated: [String: String] = [:]
            if let t = try c.decodeIfPresent(String.self, forKey: .temperature), !t.isEmpty { migrated["temperature"] = t }
            if let d = try c.decodeIfPresent(String.self, forKey: .deviceName), !d.isEmpty { migrated["device"] = d }
            conditionValues = migrated
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(batchName, forKey: .batchName)
        try c.encode(sampleName, forKey: .sampleName)
        try c.encode(measurementName, forKey: .measurementName)
        try c.encode(workflowID, forKey: .workflowID)
        try c.encode(conditionValues, forKey: .conditionValues)
        try c.encode(selectedExistingProjectName, forKey: .selectedExistingProjectName)
        try c.encode(newProjectName, forKey: .newProjectName)
    }
}

struct PendingRoutingDraft: Codable, Equatable {
    var defaultSampleKey: String
    var channelSampleKeyOverrides: [String: String]
}

struct InboxPendingWorkspaceState: Codable, Equatable {
    var draft: PendingImportConfirmationDraft
    var editableFileContents: String
    var hasEditableFileContents: Bool
    var routingDraft: PendingRoutingDraft?

    static let maxStoredEditableContentsLength = 200_000
    static let truncatedSuffix = "\n\n[SpinLab] Editable file preview was truncated for interaction-memory snapshot."

    static func snapshotSafe(
        draft: PendingImportConfirmationDraft,
        editableFileContents: String,
        hasEditableFileContents: Bool,
        routingDraft: PendingRoutingDraft? = nil
    ) -> InboxPendingWorkspaceState {
        InboxPendingWorkspaceState(
            draft: draft,
            editableFileContents: sanitizedEditableContents(editableFileContents),
            hasEditableFileContents: hasEditableFileContents,
            routingDraft: routingDraft
        )
    }

    private static func sanitizedEditableContents(_ text: String) -> String {
        guard text.count > maxStoredEditableContentsLength else {
            return text
        }
        let prefixLength = max(0, maxStoredEditableContentsLength - truncatedSuffix.count)
        let prefix = String(text.prefix(prefixLength))
        return prefix + truncatedSuffix
    }
}

struct SidebarInteractionState: Codable, Equatable {
    var isLibraryTreeExpanded: Bool = true
    var expandedPrefixes: Set<String> = []
    var expandedNodeIDs: Set<String> = []

    init(
        isLibraryTreeExpanded: Bool = true,
        expandedPrefixes: Set<String> = [],
        expandedNodeIDs: Set<String> = []
    ) {
        self.isLibraryTreeExpanded = isLibraryTreeExpanded
        self.expandedPrefixes = expandedPrefixes
        self.expandedNodeIDs = expandedNodeIDs
    }

    private enum CodingKeys: String, CodingKey {
        case isLibraryTreeExpanded
        case expandedPrefixes
        case expandedNodeIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isLibraryTreeExpanded = try container.decodeIfPresent(Bool.self, forKey: .isLibraryTreeExpanded) ?? true
        expandedPrefixes = try container.decodeIfPresent(Set<String>.self, forKey: .expandedPrefixes) ?? []
        expandedNodeIDs = try container.decodeIfPresent(Set<String>.self, forKey: .expandedNodeIDs) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isLibraryTreeExpanded, forKey: .isLibraryTreeExpanded)
        try container.encode(expandedPrefixes, forKey: .expandedPrefixes)
        try container.encode(expandedNodeIDs, forKey: .expandedNodeIDs)
    }
}

struct LibraryInteractionState: Codable, Equatable {
    var selectedPrefix: String?
    var selectedBatchId: String?
    var selectedSampleId: String?
    var isLibrarySettingsExpanded: Bool = true
    var isRegistryWorkspaceExpanded: Bool = true
    var isSearchWorkspaceExpanded: Bool = true
    var searchBatchIdText: String = ""
    var searchSubstrateText: String = ""
    var searchKeywordText: String = ""
    var searchThicknessText: String = ""
    var searchOxygenText: String = ""
    var searchTemperatureText: String = ""
    var searchEnergyText: String = ""
    var searchHasExecuted: Bool = false
}

struct InboxInteractionState: Codable, Equatable {
    var isImportSourceExpanded: Bool = true
    var isPendingQueueExpanded: Bool = true
    var isRoutingReviewExpanded: Bool = true
    var isApplyExpanded: Bool = true
}

struct SpinLabInteractionSnapshot: Codable, Equatable {
    var selectedArea: AppArea = .inbox
    var selectedPendingImportID: UUID?
    var selectedArchivedRecordID: UUID?
    var workbenchResultDraft: String = ""
    var lastSeenRoutingRuleFingerprint: String?
    var libraryActiveSelectionSource: LibrarySelectionSource = .browser
    var librarySelectedPrefix: String?
    var librarySelectedBatchId: String?
    var librarySelectedSampleId: String?
    var inboxWorkspaceByPendingID: [String: InboxPendingWorkspaceState] = [:]
    var sidebar: SidebarInteractionState = SidebarInteractionState()
    var libraryView: LibraryInteractionState = LibraryInteractionState()
    var inboxView: InboxInteractionState = InboxInteractionState()
}
