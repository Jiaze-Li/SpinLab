import Foundation

/// Where a `SidecarMeasurementTimestamp.value` came from, ranked from most to
/// least trustworthy: instrumentHeader > filename > filesystemFallback > unknown.
/// Recompute must never replace a higher-ranked provenance with a lower one.
enum MeasurementTimestampProvenance: String, Codable, Hashable, Sendable {
    case instrumentHeader
    case filename
    case filesystemFallback
    case unknown
}

/// The measurement's actual clock time — distinct from `SpinLabFileSidecar.appliedAt`,
/// which is sidecar/import/recompute write time and must never be used as a stand-in.
///
/// PPMS FILEOPENTIME (instrumentHeader provenance) carries no UTC offset — it is a
/// local wall-clock reading from whatever machine ran the instrument software, with
/// no way to recover the true offset after the fact. `value` is parsed as wall-clock
/// time in the reading machine's current time zone (TimeZone.current), which is the
/// best-effort interpretation available; it must not be treated as an authoritative
/// absolute instant across time zones. `rawText` preserves the original source text
/// verbatim so the ambiguity is always recoverable from the sidecar itself.
struct SidecarMeasurementTimestamp: Codable, Hashable, Sendable {
    var value: Date?
    var provenance: MeasurementTimestampProvenance
    var rawText: String?

    static let unknown = SidecarMeasurementTimestamp(value: nil, provenance: .unknown, rawText: nil)

    /// True when no usable timestamp was ever resolved — the only state recompute
    /// is allowed to backfill over.
    var isUnresolved: Bool {
        value == nil && provenance == .unknown
    }
}
