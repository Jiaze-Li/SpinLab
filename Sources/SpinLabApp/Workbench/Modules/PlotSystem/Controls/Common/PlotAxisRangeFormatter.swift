import Foundation

/// Locale-independent axis-range bound formatter shared by every Cartesian XY
/// and Dual Axis numeric bound field/placeholder. `0` prints literally;
/// magnitudes in [0.001, 100_000) use `%g`; everything else uses scientific
/// notation. Always formats under `en_US_POSIX` so the decimal separator
/// cannot shift with the user's locale.
func formatPlotAxisRangeValue(_ value: Double?) -> String {
    guard let value else { return "" }
    if value == 0 { return "0" }
    let magnitude = Swift.abs(value)
    if magnitude >= 0.001 && magnitude < 100_000 {
        return String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
    return String(format: "%.3e", locale: Locale(identifier: "en_US_POSIX"), value)
}
