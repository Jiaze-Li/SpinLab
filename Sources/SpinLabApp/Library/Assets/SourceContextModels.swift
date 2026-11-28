import Foundation

// MARK: - WP1 — Source ingest vocabulary (design-11-wp1-source-ingest §3.0–§3.2)
//
// Value types for the Source ingest step. This file deliberately knows nothing about adapters,
// Datasets, Workbench or automatic plotting: ingest keeps original bytes, identity, ownership and
// the *confirmed or unknown* measurement context, and nothing else.

/// Where a context value came from. `unknown` means the value is not confirmed (never guessed).
enum ContextOrigin: String, Codable, Equatable, Sendable {
    case rule
    case manual
    case fallback
    case unknown

    var isConfirmed: Bool { self != .unknown }
}

/// One confirmed measurement condition (e.g. temperature 10 K) and its provenance.
struct ContextConditionValue: Codable, Equatable, Sendable {
    var value: String
    var origin: ContextOrigin
}

/// A channel of a Source that belongs to the owning Sample (K12). `NULL` channels = unconfirmed.
struct EffectiveChannel: Codable, Equatable, Hashable, Sendable {
    var id: String
    var role: String?

    init(id: String, role: String? = nil) {
        self.id = id
        self.role = role
    }
}

/// Context supplied by the caller at ingest. The file modification time is not part of the request:
/// ingest reads it from the very same file read that provides the bytes.
struct SourceContextInput: Codable, Equatable, Sendable {
    var workflowID: String?
    var workflowOrigin: ContextOrigin
    var conditions: [String: ContextConditionValue]
    var measuredAt: String?
    var measuredAtOrigin: ContextOrigin
    /// Free-form provenance (rule id, parser note); stored, never interpreted by ingest.
    var interpretation: [String: String]
    /// Historical provenance only; never identity.
    var legacyPath: String?

    init(
        workflowID: String? = nil, workflowOrigin: ContextOrigin = .unknown,
        conditions: [String: ContextConditionValue] = [:],
        measuredAt: String? = nil, measuredAtOrigin: ContextOrigin = .unknown,
        interpretation: [String: String] = [:], legacyPath: String? = nil
    ) {
        let trimmed = workflowID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.workflowID = (trimmed?.isEmpty == false) ? trimmed : nil
        self.workflowOrigin = self.workflowID == nil ? .unknown : workflowOrigin
        self.conditions = conditions
        self.measuredAt = measuredAt
        self.measuredAtOrigin = measuredAt == nil ? .unknown : measuredAtOrigin
        self.interpretation = interpretation
        self.legacyPath = legacyPath
    }

    static let unknown = SourceContextInput()
}

/// The persisted context of one Source (`source_context` row; absent row = unknown legacy Source).
struct SourceContextRecord: Codable, Equatable, Sendable {
    var sourceID: String
    var workflowID: String?
    var workflowOrigin: ContextOrigin
    var conditions: [String: ContextConditionValue]
    var measuredAt: String?
    var measuredAtOrigin: ContextOrigin
    var sourceMTime: String?
    var legacyPath: String?
    var interpretation: [String: String]
    var recordedAt: String
}

/// What a caller asks `ingestSource` to do. No adapter, no Dataset, no plotting intent.
struct SourceIngestRequest: Sendable {
    var sourceFileURL: URL
    var targetSampleUID: String
    var operationID: String
    var context: SourceContextInput
    /// `nil` = unconfirmed (not "all channels").
    var effectiveChannels: [EffectiveChannel]?
    var reuseSourceID: String?

    init(
        sourceFileURL: URL, targetSampleUID: String, operationID: String,
        context: SourceContextInput = .unknown, effectiveChannels: [EffectiveChannel]? = nil,
        reuseSourceID: String? = nil
    ) {
        self.sourceFileURL = sourceFileURL
        self.targetSampleUID = targetSampleUID
        self.operationID = operationID
        self.context = context
        self.effectiveChannels = effectiveChannels
        self.reuseSourceID = reuseSourceID
    }
}

/// Self-contained ingest receipt: says only that the original file is stored and owned.
struct SourceReceipt: Codable, Equatable, Sendable {
    let sourceID: String
    let sampleUID: String
    let sha256: String
    let byteSize: Int
    /// `true` when the request was answered with an already stored Source (user-chosen reuse).
    let reusedSource: Bool

    init(sourceID: String, sampleUID: String, sha256: String, byteSize: Int, reusedSource: Bool = false) {
        self.sourceID = sourceID
        self.sampleUID = sampleUID
        self.sha256 = sha256
        self.byteSize = byteSize
        self.reusedSource = reusedSource
    }
}

/// Audited supplement of unknown context (user decision P4): only unknown → confirmed.
struct SourceContextAmendment: Codable, Equatable, Sendable {
    var workflowID: String?
    var conditions: [String: String]
    var effectiveChannels: [EffectiveChannel]?
    var measuredAt: String?

    init(
        workflowID: String? = nil, conditions: [String: String] = [:],
        effectiveChannels: [EffectiveChannel]? = nil, measuredAt: String? = nil
    ) {
        let trimmed = workflowID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.workflowID = (trimmed?.isEmpty == false) ? trimmed : nil
        self.conditions = conditions
        self.effectiveChannels = effectiveChannels
        self.measuredAt = measuredAt
    }

    var isEmpty: Bool {
        workflowID == nil && conditions.isEmpty && effectiveChannels == nil && measuredAt == nil
    }
}

struct SourceAmendmentReceipt: Codable, Equatable, Sendable {
    let sourceID: String
    /// Names of the fields that were turned from unknown into confirmed by this operation.
    let changedFields: [String]
}

// MARK: - Standardization step vocabulary (WP1 §3.2 ②)

/// Typed, deliberate refusal by an adapter. It means "this Source is not turned into a Dataset"
/// and is recorded as `not_standardized`; any other thrown error is a technical failure.
struct StandardizationRejected: Error, Equatable, LocalizedError, Sendable {
    let code: String
    let detail: String

    init(code: String, detail: String) {
        self.code = code
        self.detail = detail
    }

    var errorDescription: String? { "Not standardized (\(code)): \(detail)" }
}

enum StandardizationResult: Codable, Equatable, Sendable {
    case standardized(datasetIDs: [String], datasetRevision: Int)
    case notStandardized(code: String, detail: String)

    var datasetIDs: [String] {
        if case let .standardized(ids, _) = self { return ids }
        return []
    }
}

/// Standardization state of a Source as seen by lists. No row = not yet processed.
enum StandardizationState: Equatable, Sendable {
    case pending
    case standardized(adapterID: String?)
    case notStandardized(code: String, detail: String)
}

/// The Library-held bytes of a Source after hash verification (the read-only data contract).
struct SourceContent: Sendable {
    let sourceID: String
    let originalFileName: String
    let bytes: Data
    let sha256: String
}

/// Everything a Library list needs to show one Source honestly (design P3).
struct SourceStatusSummary: Equatable, Sendable {
    let sourceID: String
    let originalFileName: String
    let sampleUID: String
    let datasetCount: Int
    let standardization: StandardizationState
    let workflowID: String?
    let workflowOrigin: ContextOrigin
    let effectiveChannels: [EffectiveChannel]?
    let hasContextRow: Bool
}
