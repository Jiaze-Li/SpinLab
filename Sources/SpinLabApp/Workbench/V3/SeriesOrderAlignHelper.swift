import Foundation

/// Aligns a persisted series order against the current sweep set after re-analysis.
///
/// - Returns: The aligned order to use, or nil if the default order should be used.
///   Returns nil when `old` is nil/empty, OR when the aligned result matches `defaultIDs` exactly
///   (so the caller can skip writing seriesOrder and let the default render path stay clean).
func alignSeriesOrder(old: [String]?, defaultIDs: [String]) -> [String]? {
    guard let old, !old.isEmpty else { return nil }
    let currentSet = Set(defaultIDs)
    var seen: Set<String> = []
    var kept: [String] = []
    for id in old where currentSet.contains(id) && seen.insert(id).inserted {
        kept.append(id)
    }
    let keptSet = Set(kept)
    var result = kept
    for id in defaultIDs where !keptSet.contains(id) {
        result.append(id)
    }
    return result == defaultIDs ? nil : result
}
