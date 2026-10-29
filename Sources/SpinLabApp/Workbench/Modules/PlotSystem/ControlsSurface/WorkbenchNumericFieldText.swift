import Foundation

/// Shared numeric leaf-field conversion. An Int conversion is only attempted when representable.
enum WorkbenchNumericFieldText {
    static func parseFinite(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)), value.isFinite else { return nil }
        return value
    }

    static func formatIntegerIfExact(_ value: Double) -> String {
        guard let integer = Int(exactly: value) else { return String(value) }
        return String(integer)
    }

    /// Fit bounds historically display the nearest integer when it fits in Int.
    static func formatRoundedIfRepresentable(_ value: Double) -> String {
        guard value.isFinite, let integer = Int(exactly: value.rounded()) else { return String(value) }
        return String(integer)
    }
}
