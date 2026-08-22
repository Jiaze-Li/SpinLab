import Foundation

// MARK: - Obsidian growth → Registry import plan (Phase 5A)
//
// Read-only preview model. Nothing in this file performs I/O or mutation —
// see `RegistryGrowthImportPlanner` (builds a plan) and
// `RegistryGrowthMutationService` (executes a subset of it). A plan is a
// snapshot: it captures the Registry's content fingerprint at build time so
// `RegistryGrowthMutationService` can detect a stale plan before writing
// anything (spec §3).

/// What the planner decided to do with one Obsidian-observed batch, relative
/// to the current Registry state. Deliberately not a `Bool` (spec §2) — each
/// case carries the reasoning a caller/UI needs to explain itself.
enum RegistryGrowthImportAction: Hashable, Sendable {
    /// No Registry row exists yet for this batch on its routed target sheet.
    /// A new row will be appended, styled from the nearest existing data row.
    case appendNewRow(targetSheet: String)
    /// A Registry row already exists with only the ID cell filled (all other
    /// growth cells empty) — an ID reserved ahead of time. Values will be
    /// filled into that exact row rather than appending a duplicate.
    case fillReservedRow(targetSheet: String, rowNumber: Int)
    /// A Registry row already exists with real growth data. Import never
    /// overwrites an existing record in this phase — always skipped.
    case skipExisting(targetSheet: String, rowNumber: Int)
    /// Cannot safely proceed. `reasons` explains why; never guessed past.
    case blocked(reasons: [RegistryGrowthBlockingReason])
}

enum RegistryGrowthBlockingReason: Hashable, Sendable {
    case missingBatchId
    case missingDate
    case missingMaterialEvidence
    case missingSubstrateEvidence
    /// Substrate evidence exists (spec: `missingSubstrateEvidence` does not
    /// apply), but none of it parsed into a canonical
    /// `LibrarySubstrate`/sample key via `LibrarySubstrateParser` — e.g. a
    /// raw string the classifier has no material/orientation/treatment
    /// signal for. Never appended/filled with evidence that cannot produce
    /// a Sample the Library will actually recognize.
    case unresolvedSubstrateIdentity(rawHint: String?)
    case unroutableMaterialOrPrefix(rawHint: String?)
    /// The batch's series (e.g. "PN" from "PN110") already exists on more
    /// than one routable sheet — Registry historical evidence doesn't
    /// uniquely say where it belongs, and this phase never guesses among
    /// candidates.
    case ambiguousTargetSheet(batchSeries: String, candidateSheets: [String])
    /// Registry historical series evidence uniquely names one sheet, but the
    /// hard-coded prefix/material routing rule names a different one —
    /// surfaced rather than silently preferring either source.
    case routingEvidenceConflict(batchSeries: String, observedSheet: String, explicitSheet: String)
    case targetSheetNotFound(sheetName: String)
    case duplicateRegistryRow(sheet: String, rowNumbers: [Int])
    case obsidianInternalConflict(field: String)
    case obsidianDateConflict
    case libraryObsidianConflictOnExistingBatch(field: String)
    case other(String)
}

/// Where one column's value came from, for provenance/audit — Phase 5A
/// spec §10. Not written into the workbook; carried alongside the plan item
/// only.
struct RegistryGrowthValueProvenance: Hashable, Sendable {
    var columnHeader: String
    var notePath: String
    var rawKey: String
    var rawValue: String
}

/// One column that the planner determined it cannot fill with evidence —
/// surfaced to preview UIs as "this column will stay blank", never guessed.
struct RegistryGrowthBlankColumn: Hashable, Sendable {
    var columnHeader: String
    var reason: String
}

/// One candidate batch's import plan item.
struct RegistryGrowthImportItem: Identifiable, Hashable, Sendable {
    var id: String { "\(batchId)|\(targetSheetHint ?? "")" }

    var batchId: String
    /// Every Obsidian note path this item's evidence was drawn from.
    var sourceNotePaths: [String]
    /// The routed target sheet, if routing succeeded (nil only when
    /// `action` is `.blocked` for a routing-stage reason).
    var targetSheetHint: String?
    var action: RegistryGrowthImportAction
    /// Header → value, for columns the planner has evidence for. Only
    /// headers present in the Phase 5A confirmed field mapping (spec §6)
    /// ever appear here.
    var columnValues: [String: String]
    var provenance: [RegistryGrowthValueProvenance]
    /// Growth columns in the confirmed mapping that have no evidence and
    /// will be left blank.
    var blankColumns: [RegistryGrowthBlankColumn]
    /// Canonical Library sample keys expected to exist once this item is
    /// applied and the Registry is re-parsed — computed by the planner via
    /// the same canonical substrate/sample identity logic
    /// `LibraryRegistryParser` uses (`LibrarySubstrateParser.sampleKey`),
    /// never a Registry-growth-specific identity parser (Phase 5A review
    /// blocker #3). Only populated for items that carry substrate evidence
    /// (i.e. never for `.blocked`); `RegistryGrowthMutationService`
    /// re-checks these after apply, not just that the Batch row exists —
    /// a Batch can parse even when its substrate fails to produce a Sample.
    var expectedSampleKeys: [String]
    var warnings: [String]
    /// Populated when `action` is `.blocked`; mirrors the reasons inside
    /// `action` for convenience (UI can read this without pattern-matching
    /// the action enum).
    var blockingReasons: [RegistryGrowthBlockingReason]

    var isExecutable: Bool {
        switch action {
        case .appendNewRow, .fillReservedRow: return true
        case .skipExisting, .blocked: return false
        }
    }
}

/// A generic (non-batch-specific) diagnostic surfaced by the planner — e.g.
/// an Obsidian note that never resolved a batch identity at all, so it
/// cannot become a candidate item.
struct RegistryGrowthPlanDiagnostic: Hashable, Sendable {
    var message: String
    var notePath: String?
}

struct RegistryGrowthImportPlan: Sendable {
    /// Content hash of the Registry .xlsx at plan-build time. Re-checked by
    /// `RegistryGrowthMutationService.apply` before any write — a mismatch
    /// means the workbook changed since this plan was generated, and the
    /// whole apply call must abort (spec §3, TOCTOU guard).
    var registryFingerprint: String
    var registrySourcePath: String
    var builtAt: Date
    var items: [RegistryGrowthImportItem]
    var diagnostics: [RegistryGrowthPlanDiagnostic]

    var appendCount: Int { items.filter { if case .appendNewRow = $0.action { return true }; return false }.count }
    var fillReservedCount: Int { items.filter { if case .fillReservedRow = $0.action { return true }; return false }.count }
    var skipExistingCount: Int { items.filter { if case .skipExisting = $0.action { return true }; return false }.count }
    var blockedCount: Int { items.filter { if case .blocked = $0.action { return true }; return false }.count }
}

// MARK: - Apply result

struct RegistryGrowthApplyResult: Sendable {
    var appliedBatchIds: [String]
    var backupPath: String
}

enum RegistryGrowthMutationError: LocalizedError {
    case staleFingerprint(planFingerprint: String, currentFingerprint: String)
    case itemNotFound(batchId: String)
    case itemNotExecutable(batchId: String, action: String)
    case targetSheetMissing(sheetName: String)
    case candidateValidationFailed(String)
    case rowValidationFailed(batchId: String, reason: String)
    case unexpectedSheetChange(String)
    case postApplyValidationFailed(String, backupPath: String)
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .staleFingerprint:
            return "Registry changed since this import plan was generated. Regenerate the plan before applying."
        case let .itemNotFound(batchId):
            return "No plan item found for batch \(batchId)."
        case let .itemNotExecutable(batchId, action):
            return "Batch \(batchId) is not executable (action: \(action)). Only appendNewRow/fillReservedRow items may be applied."
        case let .targetSheetMissing(sheetName):
            return "Target sheet \(sheetName) does not exist in the Registry. Refusing to auto-create it."
        case let .candidateValidationFailed(message):
            return "Candidate workbook failed validation before replace; original Registry left untouched: \(message)"
        case let .rowValidationFailed(batchId, reason):
            return "Row validation failed for batch \(batchId): \(reason)"
        case let .unexpectedSheetChange(message):
            return "Unexpected sheet structure change detected in candidate workbook: \(message)"
        case let .postApplyValidationFailed(message, backupPath):
            return "Registry was replaced but post-apply validation failed: \(message). A backup is available at \(backupPath) — the applied change may need manual review."
        case let .underlying(message):
            return message
        }
    }
}
