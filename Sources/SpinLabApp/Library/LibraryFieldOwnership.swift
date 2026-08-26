import Foundation

/// Classifies a Registry metadata field as owned by the Batch, owned by the
/// Sample, or Unknown (no classification evidence yet).
///
/// Growth-condition fields (e.g. growth temperature, pressure) belong to the
/// Batch per `docs/experiment-data-contract.md` §3.1. The raw Registry
/// substrate cell (e.g. `STO(110), STO(111)`) describes the whole Batch's
/// sample composition and is itself Batch-owned — it is not the same thing
/// as the *parsed* per-Sample substrate identity (`LibrarySample
/// .substrateDisplay`/`.substrateTags`/`.substrateTokens`), which is derived
/// from that cell but lives outside the generic `metadata` dict and is not
/// written back to the Registry through this path. A field with no
/// classification evidence must never be silently treated as Sample-owned —
/// see `docs/library-architecture-audit.md` §13.6/F1, and §10 "Needs
/// Decision" for the fields this deliberately leaves Unknown.
enum LibraryFieldOwnershipScope: Equatable, Sendable {
    case batch
    case sample
    case unknown
}

/// Single source of truth for Batch-vs-Sample field ownership, shared by the
/// Sample-edit path (`LibrarySampleEditService`) and the Registry write path
/// (`LibraryXLSXSyncService`) so both layers classify a field the same way.
///
/// Policy for Sample→Registry mutation (enforced by both layers via
/// `nonSampleOwnedKeys`): only a field confirmed `.sample` may be written
/// from a Sample edit context. Both `.batch` and `.unknown` are rejected —
/// an unclassified Registry column is never silently written into the
/// shared Batch row, warned-and-allowed or otherwise. See
/// `docs/library-architecture-audit.md` §13.6/F1.
struct LibraryFieldOwnershipRuleBook: Sendable {
    /// Batch-owned aliases. Confirmed against the real material-sheet
    /// Registry schema (identity/batch columns: 编号; growth-condition
    /// columns: 日期, 生长温度, 靶机距, 氧压, 能量, 预打, 生长次数, 靶, 生长;
    /// plus the raw substrate/composition cell, which describes the whole
    /// Batch's sample composition, not one Sample — see the type doc
    /// comment above). `温度`/`temperature`/`pressure`/`energy` are kept
    /// alongside the confirmed `生长温度` etc. as historically-evidenced
    /// aliases (`numericKeyAliases` in `config/library_import_rules.json`)
    /// for sheets that may use the shorter spelling.
    ///
    /// `remark`/`备注` and any other column with no confirmed evidence stay
    /// unclassified (`.unknown`) rather than guessed — see
    /// `docs/library-architecture-audit.md` §10.
    static let defaultBatchOwnedAliases: Set<String> = [
        "编号", "batch", "batchid", "batch id",
        "日期",
        "温度", "temperature", "生长温度",
        "氧压", "pressure",
        "能量", "energy",
        "靶机距",
        "预打", "生长次数",
        "靶",
        "生长",
        "substrate", "衬底"
    ]

    /// Sample-owned aliases: no Registry metadata column has confirmed
    /// evidence of being Sample-specific (a single Registry row's substrate
    /// cell can describe multiple Samples at once — see the type doc
    /// comment). Left empty rather than guessed; parsed per-Sample identity
    /// fields (`substrateDisplay`/`substrateTags`/`substrateTokens`) are
    /// edited outside this metadata-write path entirely and are unaffected
    /// by this being empty.
    static let defaultSampleOwnedAliases: Set<String> = []

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

    /// Batch-owned keys among `changedKeys`, in stable sorted order.
    /// Exposed for diagnostics/tests; enforcement should use
    /// `nonSampleOwnedKeys`, which also fail-closes on Unknown.
    func batchOwnedKeys(among changedKeys: some Sequence<String>) -> [String] {
        changedKeys.filter { scope(for: $0) == .batch }.sorted()
    }

    /// Keys among `changedKeys` that are NOT confirmed Sample-owned — i.e.
    /// `.batch` or `.unknown`. This is the fail-closed check both
    /// enforcement layers use for Sample→Registry mutation: only an
    /// explicitly confirmed Sample-owned field may be written from a Sample
    /// edit context.
    func nonSampleOwnedKeys(among changedKeys: some Sequence<String>) -> [String] {
        changedKeys.filter { scope(for: $0) != .sample }.sorted()
    }

    private static func normalize(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
