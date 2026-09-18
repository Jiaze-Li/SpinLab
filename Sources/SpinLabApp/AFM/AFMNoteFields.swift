import Foundation

/// Parses an IBW wave note's `key: value` lines (Asylum Research AFM convention) into a
/// lookup, and exposes the specific fields AFM needs: per-channel semantic type and
/// Planefit/Flatten provenance. Lines are separated by `\r` in real files (legacy Mac line
/// ending); `\n` and `\r\n` are also accepted defensively.
struct AFMNoteFields {
    private let pairs: [String: String]

    init(note: String) {
        var dict: [String: String] = [:]
        for rawLine in note.components(separatedBy: CharacterSet(charactersIn: "\r\n")) {
            guard let colonIndex = rawLine.firstIndex(of: ":") else { continue }
            let key = rawLine[rawLine.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            let value = rawLine[rawLine.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            dict[key] = value   // last occurrence wins — deterministic, no dependency on Note ordering assumptions
        }
        self.pairs = dict
    }

    /// The `Channel<N>DataType` field for 1-based `N` (0-based `index` = `N - 1`). Returns nil
    /// if absent or explicitly `"None"`.
    func channelDataType(index: Int) -> String? {
        guard let value = pairs["Channel\(index + 1)DataType"], value != "None" else { return nil }
        return value
    }

    /// Planefit/Flatten provenance for 0-based channel `index`, matching the note's own indexing.
    func provenance(index: Int) -> AFMChannelProvenance {
        AFMChannelProvenance(
            planefit: pairs["Planefit \(index)"],
            planefitOrder: doubleValue("PlanefitOrder \(index)"),
            flattenOrder: doubleValue("FlattenOrder \(index)"),
            planefitOffset: doubleValue("Planefit Offset \(index)"),
            planefitXSlope: doubleValue("Planefit X Slope \(index)"),
            planefitYSlope: doubleValue("Planefit Y Slope \(index)")
        )
    }

    private func doubleValue(_ key: String) -> Double? {
        pairs[key].flatMap(Double.init)
    }
}
