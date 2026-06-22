import Foundation

/// Parses a device/angle string into a numeric degree value.
///
/// Supported formats:
///   "0deg", "0 deg", "30deg", "-15deg", "+45deg", "45°", "device_30deg"
///
/// Returns nil if no numeric angle can be parsed.
struct ThreeOmegaDeviceAngleParser {

    // Matches an optional sign, integer or decimal digits, optional whitespace,
    // then either "deg" (case-insensitive) or "°".
    // Embedded in a larger string (e.g. "device_30deg") is fine; firstMatch is used.
    private static let pattern = #"([+-]?\d+(?:\.\d+)?)\s*(?:deg|°)"#
    private static let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)

    static func parseDegrees(_ raw: String) -> Double? {
        let nsRange = NSRange(raw.startIndex..., in: raw)
        guard let match = regex.firstMatch(in: raw, range: nsRange),
              let numRange = Range(match.range(at: 1), in: raw) else { return nil }
        return Double(raw[numRange])
    }
}
