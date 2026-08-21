import Foundation

/// Classifies a Registry metadata field as owned by the Batch, owned by the
/// Sample, or Unknown (no classification evidence yet).
///
/// Growth-condition fields (e.g. temperature, pressure) belong to the Batch
/// per `docs/experiment-data-contract.md` §3.1; substrate identity fields
/// belong to the Sample per §3.2. A field with no classification evidence
/// must never be silently treated as Sample-owned — see
/// `docs/library-architecture-audit.md` §13.6/F1, and §10 "Needs Decision"
/// for the fields this deliberately leaves Unknown.
enum LibraryFieldOwnershipScope: Equatable, Sendable {
    case batch
    case sample
    case unknown
}

/// Single source of truth for Batch-vs-Sample field ownership, shared by the
/// Sample-edit path (`LibrarySampleEditService`) and the Registry write path
/// (`LibraryXLSXSyncService`) so both layers classify a field the same way.
struct LibraryFieldOwnershipRuleBook: Sendable {
    /// Batch-owned aliases seeded only where BOTH the contract names the
    /// field (`docs/experiment-data-contract.md` §3.1: growth date,
    /// temperature, pressure, laser energy, pulse, target-substrate
    /// distance, growth-level RHEED/observations) AND an existing, already
    /// -confirmed header alias exists elsewhere in this codebase
    /// (`numericKeyAliases` in `config/library_import_rules.json`).
    /// Growth date / pulse / target-substrate distance / RHEED /
    /// observations have no confirmed header alias anywhere in the
    /// codebase today, so they are intentionally left unclassified
    /// (`.unknown`) rather than guessed — see
    /// `docs/library-architecture-audit.md` §10.
    static let defaultBatchOwnedAliases: Set<String> = [
        "温度", "temperature",
        "氧压", "pressure",
        "能量", "energy"
    ]

    /// Sample-owned aliases: substrate identity is Sample-owned per the
    /// contract (§3.2, §4) and already has a confirmed header alias
    /// (`substrateHeaderAliases` in `config/library_import_rules.json`).
    static let defaultSampleOwnedAliases: Set<String> = [
        "substrate", "衬底"
    ]

    /// Default rule book used by production call sites. Tests should inject
    /// a custom instance via the memberwise initializer instead of mutating
    /// this shared value.
    static let shared = LibraryFieldOwnershipRuleBook()

    private let batchAliases: Set<String>
    private let sampleAliases: Set<String>

    /// If the same normalized alias appears in both sets, Batch takes
    /// precedence deterministically. Production defaults never overlap;
    /// this only matters for custom/test rule books.
    init(
        batchOwnedAliases: Set<String> = LibraryFieldOwnershipRuleBook.defaultBatchOwnedAliases,
        sampleOwnedAliases: Set<String> = LibraryFieldOwnershipRuleBook.defaultSampleOwnedAliases
    ) {
        batchAliases = Set(batchOwnedAliases.map(Self.normalize))
        sampleAliases = Set(sampleOwnedAliases.map(Self.normalize))
    }

    func scope(for fieldKey: String) -> LibraryFieldOwnershipScope {
        let normalized = Self.normalize(fieldKey)
        if batchAliases.contains(normalized) { return .batch }
        if sampleAliases.contains(normalized) { return .sample }
        return .unknown
    }

    /// Batch-owned keys among `changedKeys`, in stable sorted order — used
    /// by both enforcement layers to build a deterministic rejection list.
    func batchOwnedKeys(among changedKeys: some Sequence<String>) -> [String] {
        changedKeys.filter { scope(for: $0) == .batch }.sorted()
    }

    private static func normalize(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
