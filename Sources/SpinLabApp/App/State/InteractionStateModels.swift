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
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        batchName = try c.decodeIfPresent(String.self, forKey: .batchName) ?? ""
        sampleName = try c.decodeIfPresent(String.self, forKey: .sampleName) ?? ""
        measurementName = try c.decodeIfPresent(String.self, forKey: .measurementName) ?? ""
        selectedExistingProjectName = try c.decodeIfPresent(String.self, forKey: .selectedExistingProjectName) ?? Self.noProjectOption
        newProjectName = try c.decodeIfPresent(String.self, forKey: .newProjectName) ?? ""
        workflowID = try c.decodeIfPresent(String.self, forKey: .workflowID) ?? ""
        conditionValues = try c.decodeIfPresent([String: String].self, forKey: .conditionValues) ?? [:]
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
    var fileSampleKey: String
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
    var isMetadataSectionExpanded: Bool = true
    var searchBatchIdText: String = ""
    var searchSubstrateText: String = ""
    var searchKeywordText: String = ""
    var searchThicknessText: String = ""
    var searchOxygenText: String = ""
    var searchTemperatureText: String = ""
    var searchEnergyText: String = ""
    var searchThicknessToleranceText: String = ""
    var searchOxygenToleranceText: String = ""
    var searchTemperatureToleranceText: String = ""
    var searchEnergyToleranceText: String = ""
    var searchHasExecuted: Bool = false
    var expandedWorkflowIDs: Set<String>?
    var expandedSetIDs: Set<String>?
    var expandedUncategorizedIDs: Set<String>?

    enum CodingKeys: String, CodingKey {
        case selectedPrefix
        case selectedBatchId
        case selectedSampleId
        case isLibrarySettingsExpanded
        case isRegistryWorkspaceExpanded
        case isSearchWorkspaceExpanded
        case isMetadataSectionExpanded
        case searchBatchIdText
        case searchSubstrateText
        case searchKeywordText
        case searchThicknessText
        case searchOxygenText
        case searchTemperatureText
        case searchEnergyText
        case searchThicknessToleranceText
        case searchOxygenToleranceText
        case searchTemperatureToleranceText
        case searchEnergyToleranceText
        case searchHasExecuted
        case expandedWorkflowIDs
        case expandedSetIDs
        case expandedUncategorizedIDs
    }

    init(
        selectedPrefix: String? = nil,
        selectedBatchId: String? = nil,
        selectedSampleId: String? = nil,
        isLibrarySettingsExpanded: Bool = true,
        isRegistryWorkspaceExpanded: Bool = true,
        isSearchWorkspaceExpanded: Bool = true,
        isMetadataSectionExpanded: Bool = true,
        searchBatchIdText: String = "",
        searchSubstrateText: String = "",
        searchKeywordText: String = "",
        searchThicknessText: String = "",
        searchOxygenText: String = "",
        searchTemperatureText: String = "",
        searchEnergyText: String = "",
        searchThicknessToleranceText: String = "",
        searchOxygenToleranceText: String = "",
        searchTemperatureToleranceText: String = "",
        searchEnergyToleranceText: String = "",
        searchHasExecuted: Bool = false,
        expandedWorkflowIDs: Set<String>? = nil,
        expandedSetIDs: Set<String>? = nil,
        expandedUncategorizedIDs: Set<String>? = nil
    ) {
        self.selectedPrefix = selectedPrefix
        self.selectedBatchId = selectedBatchId
        self.selectedSampleId = selectedSampleId
        self.isLibrarySettingsExpanded = isLibrarySettingsExpanded
        self.isRegistryWorkspaceExpanded = isRegistryWorkspaceExpanded
        self.isSearchWorkspaceExpanded = isSearchWorkspaceExpanded
        self.isMetadataSectionExpanded = isMetadataSectionExpanded
        self.searchBatchIdText = searchBatchIdText
        self.searchSubstrateText = searchSubstrateText
        self.searchKeywordText = searchKeywordText
        self.searchThicknessText = searchThicknessText
        self.searchOxygenText = searchOxygenText
        self.searchTemperatureText = searchTemperatureText
        self.searchEnergyText = searchEnergyText
        self.searchThicknessToleranceText = searchThicknessToleranceText
        self.searchOxygenToleranceText = searchOxygenToleranceText
        self.searchTemperatureToleranceText = searchTemperatureToleranceText
        self.searchEnergyToleranceText = searchEnergyToleranceText
        self.searchHasExecuted = searchHasExecuted
        self.expandedWorkflowIDs = expandedWorkflowIDs
        self.expandedSetIDs = expandedSetIDs
        self.expandedUncategorizedIDs = expandedUncategorizedIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedPrefix = try container.decodeIfPresent(String.self, forKey: .selectedPrefix)
        selectedBatchId = try container.decodeIfPresent(String.self, forKey: .selectedBatchId)
        selectedSampleId = try container.decodeIfPresent(String.self, forKey: .selectedSampleId)
        isLibrarySettingsExpanded = try container.decodeIfPresent(Bool.self, forKey: .isLibrarySettingsExpanded) ?? true
        isRegistryWorkspaceExpanded = try container.decodeIfPresent(Bool.self, forKey: .isRegistryWorkspaceExpanded) ?? true
        isSearchWorkspaceExpanded = try container.decodeIfPresent(Bool.self, forKey: .isSearchWorkspaceExpanded) ?? true
        isMetadataSectionExpanded = try container.decodeIfPresent(Bool.self, forKey: .isMetadataSectionExpanded) ?? true
        searchBatchIdText = try container.decodeIfPresent(String.self, forKey: .searchBatchIdText) ?? ""
        searchSubstrateText = try container.decodeIfPresent(String.self, forKey: .searchSubstrateText) ?? ""
        searchKeywordText = try container.decodeIfPresent(String.self, forKey: .searchKeywordText) ?? ""
        searchThicknessText = try container.decodeIfPresent(String.self, forKey: .searchThicknessText) ?? ""
        searchOxygenText = try container.decodeIfPresent(String.self, forKey: .searchOxygenText) ?? ""
        searchTemperatureText = try container.decodeIfPresent(String.self, forKey: .searchTemperatureText) ?? ""
        searchEnergyText = try container.decodeIfPresent(String.self, forKey: .searchEnergyText) ?? ""
        searchThicknessToleranceText = try container.decodeIfPresent(String.self, forKey: .searchThicknessToleranceText) ?? ""
        searchOxygenToleranceText = try container.decodeIfPresent(String.self, forKey: .searchOxygenToleranceText) ?? ""
        searchTemperatureToleranceText = try container.decodeIfPresent(String.self, forKey: .searchTemperatureToleranceText) ?? ""
        searchEnergyToleranceText = try container.decodeIfPresent(String.self, forKey: .searchEnergyToleranceText) ?? ""
        searchHasExecuted = try container.decodeIfPresent(Bool.self, forKey: .searchHasExecuted) ?? false
        expandedWorkflowIDs = try container.decodeIfPresent(Set<String>.self, forKey: .expandedWorkflowIDs)
        expandedSetIDs = try container.decodeIfPresent(Set<String>.self, forKey: .expandedSetIDs)
        expandedUncategorizedIDs = try container.decodeIfPresent(Set<String>.self, forKey: .expandedUncategorizedIDs)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(selectedPrefix, forKey: .selectedPrefix)
        try container.encodeIfPresent(selectedBatchId, forKey: .selectedBatchId)
        try container.encodeIfPresent(selectedSampleId, forKey: .selectedSampleId)
        try container.encode(isLibrarySettingsExpanded, forKey: .isLibrarySettingsExpanded)
        try container.encode(isRegistryWorkspaceExpanded, forKey: .isRegistryWorkspaceExpanded)
        try container.encode(isSearchWorkspaceExpanded, forKey: .isSearchWorkspaceExpanded)
        try container.encode(isMetadataSectionExpanded, forKey: .isMetadataSectionExpanded)
        try container.encode(searchBatchIdText, forKey: .searchBatchIdText)
        try container.encode(searchSubstrateText, forKey: .searchSubstrateText)
        try container.encode(searchKeywordText, forKey: .searchKeywordText)
        try container.encode(searchThicknessText, forKey: .searchThicknessText)
        try container.encode(searchOxygenText, forKey: .searchOxygenText)
        try container.encode(searchTemperatureText, forKey: .searchTemperatureText)
        try container.encode(searchEnergyText, forKey: .searchEnergyText)
        try container.encode(searchThicknessToleranceText, forKey: .searchThicknessToleranceText)
        try container.encode(searchOxygenToleranceText, forKey: .searchOxygenToleranceText)
        try container.encode(searchTemperatureToleranceText, forKey: .searchTemperatureToleranceText)
        try container.encode(searchEnergyToleranceText, forKey: .searchEnergyToleranceText)
        try container.encode(searchHasExecuted, forKey: .searchHasExecuted)
        try container.encodeIfPresent(expandedWorkflowIDs, forKey: .expandedWorkflowIDs)
        try container.encodeIfPresent(expandedSetIDs, forKey: .expandedSetIDs)
        try container.encodeIfPresent(expandedUncategorizedIDs, forKey: .expandedUncategorizedIDs)
    }
}

struct InboxInteractionState: Codable, Equatable {
    var isImportSourceExpanded: Bool = true
    var isPendingQueueExpanded: Bool = true
    var isRoutingReviewExpanded: Bool = true
    var isApplyExpanded: Bool = true
    var fileFilter: String?
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
    var threeOmegaGeometryLxx: Double?
    var threeOmegaGeometryLxy: Double?
    var threeOmegaGeometryDNm: Double?
    var threeOmegaV3Method: String?
    var threeOmegaTitleTemplate: String?
    var threeOmegaStackOffsetMultiplier: Double?
    var threeOmegaMinGapFraction: Double?
    var threeOmegaRTSidecarPath: String?
    var threeOmegaFitRanges: [ThreeOmegaFitRange]?
    /// Per-tab legend positions keyed by ThreeOmegaWorkbenchTab.stableKey.
    var threeOmegaPlotLegendPoints: [String: [Double]]?
    var aheTitleTemplate: String?
    // XY Rotation
    var xyRotationPhiOffsets: [String: Double]?
    var xyRotationActiveTab: String?
    var xyRotationTitleTemplate: String?
    var xyRotationStackOffset: Double?
    var xyRotationCenterBaseline: Bool?
    var xyRotationLinearDetrend: Bool?
    /// Per-tab legend positions keyed by XYRotationWorkbenchTab.rawValue.
    var xyRotationPlotLegendPoints: [String: [Double]]?

    // Chart style overrides (font sizes, tick density) — shared across workflows
    var workbenchChartStyleOverrides: [String: String]?
}
