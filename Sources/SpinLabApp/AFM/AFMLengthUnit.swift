import Foundation

/// Recognizes IBW length-unit strings and converts to meters. Used only at the
/// `AFMInputAdapter` boundary — nothing downstream re-interprets a unit string.
enum AFMLengthUnit {
    /// Returns the number of meters in one unit of `unit`, or nil if `unit` is not a
    /// recognized length unit (in which case the caller must preserve the value/unit as-is,
    /// never falsely relabeling it as a length).
    static func metersPerUnit(_ unit: String) -> Double? {
        switch unit.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "m": return 1
        case "cm": return 1e-2
        case "mm": return 1e-3
        case "µm", "um": return 1e-6
        case "nm": return 1e-9
        // Bare "A" is ambiguous with Amperes and is intentionally NOT treated as Angstrom here.
        case "Å", "angstrom": return 1e-10
        default: return nil
        }
    }
}
