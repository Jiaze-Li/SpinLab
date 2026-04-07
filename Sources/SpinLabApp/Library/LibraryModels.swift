import Foundation

struct LibraryMetadataItem: Identifiable, Codable, Hashable, Sendable {
    var id: String { key }
    var key: String
    var value: String
}

struct LibrarySettings: Codable, Hashable, Sendable {
    var rootPath: String?
    var registryInternalPath: String?
    var registrySourcePath: String?
    var backupPath: String?
    var backupLastSyncedAt: Date?
    var allowedBatchPrefixes: [String]
    var lastRefreshAt: Date?

    static let `default` = LibrarySettings(
        rootPath: nil,
        registryInternalPath: nil,
        registrySourcePath: nil,
        backupPath: nil,
        backupLastSyncedAt: nil,
        allowedBatchPrefixes: ["PN", "PT", "SL"],
        lastRefreshAt: nil
    )
}

struct LibraryIndex: Codable, Hashable, Sendable {
    var version: Int = 1
    var createdAt: Date
    var updatedAt: Date
    var registryInternalPath: String?
    var registrySourcePath: String?
    var metadataColumnOrder: [String]
    var batches: [LibraryBatch]
    var samples: [LibrarySample]

    init(
        version: Int = 1,
        createdAt: Date,
        updatedAt: Date,
        registryInternalPath: String?,
        registrySourcePath: String?,
        metadataColumnOrder: [String] = [],
        batches: [LibraryBatch],
        samples: [LibrarySample]
    ) {
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.registryInternalPath = registryInternalPath
        self.registrySourcePath = registrySourcePath
        self.metadataColumnOrder = metadataColumnOrder
        self.batches = batches
        self.samples = samples
    }

    enum CodingKeys: String, CodingKey {
        case version
        case createdAt
        case updatedAt
        case registryInternalPath
        case registrySourcePath
        case metadataColumnOrder
        case batches
        case samples
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        registryInternalPath = try container.decodeIfPresent(String.self, forKey: .registryInternalPath)
        registrySourcePath = try container.decodeIfPresent(String.self, forKey: .registrySourcePath)
        metadataColumnOrder = try container.decodeIfPresent([String].self, forKey: .metadataColumnOrder) ?? []
        batches = try container.decodeIfPresent([LibraryBatch].self, forKey: .batches) ?? []
        samples = try container.decodeIfPresent([LibrarySample].self, forKey: .samples) ?? []
    }
}

struct LibraryBatch: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var displayName: String
    var sheetName: String
    var metadata: [String: String]
    var numericTags: [String: Double]
    var numericDisplay: [String: String]
    var sampleKeys: [String]

    var updatedAt: Date
}

struct AppliedMeasurement: Codable, Hashable, Identifiable, Sendable {
    var id: String
    /// Workflow identifier (matches WorkflowDefinition.id).
    var workflow: String
    /// Human-readable name captured from registry at apply time.
    var workflowDisplayName: String
    var conditions: [String: String]
    var appliedAt: Date
    var sourceFileName: String
}

/// User-created grouping of measurements within a single workflow.
/// Pure UI organisation — does not affect search, analysis, or plotting.
struct MeasurementSet: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    /// Workflow ID this set belongs to (e.g. "ahe", "3w"). Matches AppliedMeasurement.workflow.
    var workflow: String
    /// Ordered list of sourceFileName values belonging to this set.
    var memberFileNames: [String]
    var createdAt: Date
}

struct LibrarySample: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var displayName: String
    var batchId: String
    var substrateRaw: String
    var substrateDisplay: String
    var substrateTokens: [String]
    var substrateTags: [String]
    var metadata: [String: String]
    var orderedMetadata: [LibraryMetadataItem]
    var numericTags: [String: Double]
    var numericDisplay: [String: String]
    var sourceSheetName: String?
    var sourceRowNumber: Int?
    var updatedAt: Date
    // Runtime-only V2.6 projection from sidecar scans.
    var appliedMeasurements: [AppliedMeasurement] = []
    // Runtime-only: user-created measurement sets loaded from measurement_sets.json.
    var measurementSets: [MeasurementSet] = []

    init(
        id: String,
        displayName: String,
        batchId: String,
        substrateRaw: String,
        substrateDisplay: String,
        substrateTokens: [String],
        substrateTags: [String],
        metadata: [String: String],
        orderedMetadata: [LibraryMetadataItem] = [],
        numericTags: [String: Double],
        numericDisplay: [String: String],
        sourceSheetName: String? = nil,
        sourceRowNumber: Int? = nil,
        updatedAt: Date,
        appliedMeasurements: [AppliedMeasurement] = [],
        measurementSets: [MeasurementSet] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.batchId = batchId
        self.substrateRaw = substrateRaw
        self.substrateDisplay = substrateDisplay
        self.substrateTokens = substrateTokens
        self.substrateTags = substrateTags
        self.metadata = metadata
        self.orderedMetadata = orderedMetadata
        self.numericTags = numericTags
        self.numericDisplay = numericDisplay
        self.sourceSheetName = sourceSheetName
        self.sourceRowNumber = sourceRowNumber
        self.updatedAt = updatedAt
        self.appliedMeasurements = appliedMeasurements
        self.measurementSets = measurementSets
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case batchId
        case substrateRaw
        case substrateDisplay
        case substrateTokens
        case substrateTags
        case metadata
        case orderedMetadata
        case numericTags
        case numericDisplay
        case sourceSheetName
        case sourceRowNumber
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        batchId = try container.decode(String.self, forKey: .batchId)
        substrateRaw = try container.decode(String.self, forKey: .substrateRaw)
        substrateDisplay = try container.decode(String.self, forKey: .substrateDisplay)
        substrateTokens = try container.decodeIfPresent([String].self, forKey: .substrateTokens) ?? []
        substrateTags = try container.decodeIfPresent([String].self, forKey: .substrateTags) ?? []
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        orderedMetadata = try container.decodeIfPresent([LibraryMetadataItem].self, forKey: .orderedMetadata) ?? []
        numericTags = try container.decodeIfPresent([String: Double].self, forKey: .numericTags) ?? [:]
        numericDisplay = try container.decodeIfPresent([String: String].self, forKey: .numericDisplay) ?? [:]
        sourceSheetName = try container.decodeIfPresent(String.self, forKey: .sourceSheetName)
        sourceRowNumber = try container.decodeIfPresent(Int.self, forKey: .sourceRowNumber)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        appliedMeasurements = []
        measurementSets = []
    }
}

struct LibraryPreview: Hashable, Sendable {
    var index: LibraryIndex
    var warnings: [LibraryWarning]
}

struct LibraryPreviewBatchGroup: Identifiable, Hashable {
    var id: String { batchId }
    var batchId: String
    var samples: [LibrarySample]
}

struct LibraryWarning: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var message: String
    var affectedSampleKey: String?
    var severity: WarningSeverity = .warning

    enum WarningSeverity: String, Hashable, Sendable {
        case warning
        case error
    }
}

enum LibrarySyncBatchStatus: String, Hashable {
    case added
    case changed
    case removed
    case unchanged
}

struct LibraryDiff: Hashable {
    var newSamples: [LibrarySample]
    var changedSamples: [LibrarySampleChange]
    var removedSamples: [LibrarySample]
    var changedBatches: [LibraryBatchChange]
    var removedBatches: [LibraryBatch]
    var warnings: [LibraryWarning]
}

struct LibraryRefreshReview: Identifiable, Hashable {
    var id: UUID = UUID()
    var generatedAt: Date
    var newSamples: [LibrarySample]
    var changedSamples: [LibrarySampleChange]
    var removedSamples: [LibrarySample]
    var changedBatches: [LibraryBatchChange]
    var removedBatches: [LibraryBatch]
    var autoAppliedChanges: [LibrarySampleChange]
    var deferredNumericChanges: [LibrarySampleChange]

    var totalChangesCount: Int {
        newSamples.count + changedSamples.count + removedSamples.count + changedBatches.count + removedBatches.count
    }
}

struct LibrarySampleChange: Identifiable, Hashable {
    var id: String { sample.id }
    var sample: LibrarySample
    var fieldChanges: [LibraryFieldChange]
    var requiresConfirm: Bool
}

struct LibraryFieldChange: Hashable {
    var key: String
    var oldValue: String?
    var newValue: String?
    var isNumeric: Bool
}

struct LibraryBatchChange: Identifiable, Hashable {
    var id: String { batch.id }
    var batch: LibraryBatch
    var fieldChanges: [LibraryFieldChange]
}

struct LibraryMatchStatus: Hashable {
    var batchMatched: Bool
    var sampleMatched: Bool
    var matchedBatchId: String?
    var matchedSampleKey: String?
    var candidates: [LibrarySample]
}

struct LibraryEditableKeyValue: Identifiable, Hashable {
    var id: String { key }
    var key: String
    var value: String
}

struct LibraryEditableNumericValue: Identifiable, Hashable {
    var id: String { key }
    var key: String
    var value: String
    var unit: String
}

struct LibrarySampleEditDraft: Hashable {
    var sampleId: String
    var batchId: String
    var baseUpdatedAt: Date
    var substrateTagsText: String
    var numericValues: [LibraryEditableNumericValue]
    var metadataValues: [LibraryEditableKeyValue]
}

struct LibrarySampleChangeLogItem: Codable, Hashable {
    var key: String
    var oldValue: String?
    var newValue: String?
}

struct LibrarySampleChangeLogEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var sampleId: String
    var batchId: String
    var changedAt: Date
    var source: String
    var changes: [LibrarySampleChangeLogItem]
}

struct LibraryRegistrySourceSyncResult: Hashable {
    var metadataWrittenCount: Int
    var metadataFailedCount: Int
    var manualLoggedCount: Int
    var metadataLogSheetName: String
    var manualLogSheetName: String
}

enum LibraryManualLogStatus: String, Codable, CaseIterable, Hashable {
    case pending
    case done
    case ignored
}

struct LibraryManualUpdateLogEntry: Identifiable, Hashable {
    var id: String { "\(rowIndex)" }
    var rowIndex: Int
    var timestamp: Date?
    var sampleId: String
    var batchId: String
    var sheetName: String
    var rowNumber: Int
    var fieldType: String
    var fieldKey: String
    var oldValue: String?
    var newValue: String?
    var status: LibraryManualLogStatus
    var statusChangedAt: Date?
    var statusChangedBy: String?
}

struct LibraryMetadataSyncLogEntry: Identifiable, Hashable {
    var id: String { "\(rowIndex)" }
    var rowIndex: Int
    var timestamp: Date?
    var sampleId: String
    var batchId: String
    var sheetName: String
    var rowNumber: Int
    var columnName: String
    var oldValue: String?
    var newValue: String?
    var writeResult: String
    var errorMessage: String?
}
