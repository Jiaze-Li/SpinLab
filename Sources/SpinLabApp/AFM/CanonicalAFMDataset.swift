import Foundation

/// IBW note provenance for one channel's Planefit/Flatten state at scan time. Provenance only —
/// never read by AFM processing to decide SpinLab's own Plane Level / Line Flatten defaults.
/// See `docs/architecture/workbench/datasets/AFMDatasetContract.md`.
struct AFMChannelProvenance: Sendable, Equatable, Codable {
    let planefit: String?
    let planefitOrder: Double?
    let flattenOrder: Double?
    let planefitOffset: Double?
    let planefitXSlope: Double?
    let planefitYSlope: Double?
}

/// File-level provenance, for run trace / pack metadata.
struct AFMSourceProvenance: Sendable, Equatable, Codable {
    let sourceFilePath: String
    let waveName: String
    let sourceWidth: Int
    let sourceHeight: Int
    /// Full raw IBW note text, kept for audit. Run trace (Phase 4) surfaces the specific fields
    /// that matter rather than this raw blob.
    let rawNote: String
}

/// One AFM channel's immutable source data, exactly as parsed from the IBW file plus unit
/// interpretation. See `AFMDatasetContract.md` for the full field-by-field contract.
struct CanonicalAFMChannel: Sendable, Equatable, Identifiable, Codable {
    /// Stable identity derived from `sourceIndex` + `sourceLabel` — survives `displayLabel`
    /// being changed later and survives pack/restore.
    let id: String
    /// 0-based index into the IBW channel dimension.
    let sourceIndex: Int
    /// Raw IBW dimension label, e.g. "HeightRetrace".
    let sourceLabel: String
    /// Raw semantic-type string from the IBW note's `Channel<N>DataType` field (e.g. "Height"),
    /// or nil if absent/"None".
    let semanticTypeRaw: String?
    /// User-facing label; defaults to `sourceLabel`.
    let displayLabel: String
    /// `values[y][x]`, in `canonicalUnit`.
    let values: [[Double]]
    /// Unit `values` is expressed in (e.g. "nm" for a length-like channel).
    let canonicalUnit: String
    /// Raw IBW data unit (e.g. "m") before any conversion.
    let sourceUnit: String
    let provenance: AFMChannelProvenance

    /// True when `semanticTypeRaw` case-insensitively equals "height".
    var isSemanticHeight: Bool {
        semanticTypeRaw?.caseInsensitiveCompare("height") == .orderedSame
    }
}

/// Immutable, workflow-owned AFM dataset produced by `AFMInputAdapter` from a parsed `IBWWave`.
/// Every field is a `let`; there is no mutating API anywhere on this type or `CanonicalAFMChannel`
/// — AFM processing (Phase 3) always starts a fresh transform from these source matrices.
struct CanonicalAFMDataset: Sendable, Equatable, Codable {
    let sourceRef: String
    /// Default display title — the IBW wave's own name.
    let title: String
    /// µm, fast-scan axis, length == every channel's `values[y].count`.
    let xCoordinates: [Double]
    /// µm, slow-scan axis, length == every channel's `values.count`.
    let yCoordinates: [Double]
    let channels: [CanonicalAFMChannel]
    let sourceMetadata: AFMSourceProvenance

    static let xUnit = "µm"
    static let yUnit = "µm"
}
