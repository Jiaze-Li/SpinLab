import Foundation

// MARK: - Tier 3 Library UI projections
// Presentation-layer types used by LibraryFeatureStore, Views, and ViewModels.
// Must not be used by the UseCase layer.

struct LibraryPreview: Hashable, Sendable {
    var index: LibraryIndex
    var warnings: [LibraryWarning]
}

struct LibraryPreviewBatchGroup: Identifiable, Hashable {
    var id: String { batchId }
    var batchId: String
    var samples: [LibrarySample]
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

struct LibraryRegistrySourceSyncResult: Hashable {
    var metadataWrittenCount: Int
    var metadataFailedCount: Int
    var manualLoggedCount: Int
    var metadataLogSheetName: String
    var manualLogSheetName: String
    /// Metadata keys written this sync whose Batch/Sample ownership is not
    /// classified (`LibraryFieldOwnershipScope.unknown`). Not rejected —
    /// preserves existing edit behavior for unclassified fields — but
    /// surfaced explicitly so a silent write is never mistaken for a
    /// confirmed Sample-owned field. See docs/library-architecture-audit.md
    /// §13.6/F1 and §10 "Needs Decision".
    var unknownFieldWarnings: [String] = []
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
