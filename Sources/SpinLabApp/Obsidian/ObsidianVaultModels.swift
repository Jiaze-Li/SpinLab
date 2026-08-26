import Foundation

// MARK: - Read-only Obsidian source projection
//
// Describes only what an Obsidian note actually says. This is not application
// state (see `LibraryIndex`) and not a reconciliation result (see
// `SampleDossierIndex`) — see docs/library-architecture-audit.md Phase 4 scope
// notes for the three-layer separation this type family exists to preserve.

/// Where one field's value came from: which note, which raw frontmatter key,
/// and its raw (pre-normalization) string. Lets `SampleDossierBuilder` answer
/// "where did this Obsidian value come from" when it surfaces a conflict.
struct ObsidianProvenance: Hashable, Sendable {
    var notePath: String
    var rawKey: String
    var rawValue: String
}

/// One field value as claimed by a single note, with its provenance attached.
struct ObsidianFieldClaim: Hashable, Sendable {
    var value: String
    var provenance: ObsidianProvenance
}

/// The Batch-owned growth fields this phase normalizes, per
/// docs/experiment-data-contract.md §3.1 and the Phase 3A ownership boundary.
/// Deliberately does not include `core`/`purpose`/`note`/growth-film
/// `material` — those stay as raw, uninterpreted fields (see
/// `ObsidianNoteRecord.rawFields`) because their semantics are not yet stable
/// evidence.
enum ObsidianGrowthField: String, Hashable, Sendable, CaseIterable {
    case growthDate
    case growthTemperature
    case oxygenPressure
    case laserEnergy
    case pulseCount
    case targetSubstrateDistance
    case growthEnvironment

    /// Case-insensitive frontmatter key aliases observed in the real vault
    /// (see Phase 4 audit fixtures). Not exhaustive by design — an
    /// unrecognized key is left in `rawFields` rather than guessed into one
    /// of these.
    static func matching(rawKey: String) -> ObsidianGrowthField? {
        switch rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "date": return .growthDate
        case "lab": return .growthEnvironment
        case "temperature": return .growthTemperature
        case "pressure": return .oxygenPressure
        case "energy": return .laserEnergy
        case "pulse": return .pulseCount
        case "sample height": return .targetSubstrateDistance
        default: return nil
        }
    }
}

/// One substrate entry as written in a note (scalar or list form), before
/// classification. `raw` is the untouched string (e.g. "STO 110").
struct ObsidianSubstrateEntry: Hashable, Sendable {
    var raw: String
    var provenance: ObsidianProvenance
    /// Canonical material display name if the shared substrate classifier
    /// recognized it; nil if the entry carries no recognizable material.
    var material: String?
    /// Canonical orientation display name if recognized; nil otherwise.
    var orientation: String?
}

enum ObsidianIdentityResolution: Hashable, Sendable {
    /// batch resolved, and exactly one substrate entry could be matched to
    /// form a canonical sampleKey.
    case resolvedSample(sampleKey: String)
    /// batch resolved, but no single substrate entry could be attributed
    /// (zero matches, or more than one candidate with no disambiguator).
    case unresolvedSample
    /// no batch token could be extracted from the note at all.
    case unresolvedBatch
    /// more than one conflicting batch token candidate found in the note.
    case ambiguousBatch
}

enum ObsidianDiagnosticKind: String, Hashable, Sendable {
    case unresolvedSampleIdentity
    case unresolvedBatchIdentity
    case ambiguousBatchIdentity
    case ambiguousSampleIdentity
    case missingGrowthDate
    case noFrontmatter
}

struct ObsidianDiagnostic: Hashable, Sendable {
    var kind: ObsidianDiagnosticKind
    var notePath: String
    var message: String
}

/// One parsed Obsidian note. A note may contribute Batch growth claims,
/// a resolved Sample identity, or both (see Phase 4 spec §8/§9) — role is
/// evidence-derived, never decided from filename structure alone.
struct ObsidianNoteRecord: Hashable, Sendable {
    var notePath: String
    var batchId: String?
    var identity: ObsidianIdentityResolution

    /// Batch-owned growth field claims found on this note. Present even when
    /// `identity` resolves to a Sample — per Phase 3A ownership, a growth
    /// field written on a sample-tracking note is still a *candidate Batch*
    /// claim, never a Sample-owned field.
    var growthClaims: [ObsidianGrowthField: ObsidianFieldClaim]

    /// Raw, non-normalized fields (growth-film `material`, `core`, `purpose`,
    /// `note`, any unrecognized key) kept for provenance/debugging only.
    var rawFields: [ObsidianFieldClaim]

    /// Sample-owned test/measurement-status claims (`test_3w`, `test_xy`, …),
    /// keyed by the workflow token as written (lowercased, `test_` prefix
    /// stripped). Only meaningful when `identity` resolves to a Sample.
    var testStatus: [String: ObsidianFieldClaim]

    /// Sample-owned free-text observation claims (`core`, `note`, `purpose`
    /// treated as opaque observation text, not merged into one field).
    var sampleObservations: [ObsidianFieldClaim]

    var substrateEntries: [ObsidianSubstrateEntry]
}

/// Pure, read-only projection of an Obsidian vault. Aggregates
/// `ObsidianNoteRecord`s by batch/sample identity; carries no application
/// state and performs no mutation.
struct ObsidianVaultIndex: Sendable {
    struct BatchRecord: Hashable, Sendable {
        var batchId: String
        /// Every growth-field claim from every contributing note, so the
        /// Dossier builder can detect agreement vs. conflict across notes
        /// rather than silently picking one.
        var growthClaims: [ObsidianGrowthField: [ObsidianFieldClaim]]
        var notePaths: [String]
    }

    struct SampleRecord: Hashable, Sendable {
        var sampleKey: String
        var batchId: String
        var testStatus: [String: [ObsidianFieldClaim]]
        var sampleObservations: [ObsidianFieldClaim]
        var notePaths: [String]
    }

    var sourceRootPath: String
    var noteCount: Int
    var batches: [BatchRecord]
    var samples: [SampleRecord]
    var diagnostics: [ObsidianDiagnostic]
    /// Every parsed note, unaggregated — used by tests and the real-vault
    /// validation report; not consumed by the Dossier builder directly.
    var notes: [ObsidianNoteRecord]
}
