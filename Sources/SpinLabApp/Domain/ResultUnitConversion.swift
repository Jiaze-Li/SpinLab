import Foundation

/// Minimal unit reconciliation between a computed metric's canonical unit (T / Ω) and the unit of the
/// Result Definition the user picked (Task 12, design §3.1). Only SI prefixes of the same physical
/// quantity (plus the existing Oe↔T magnetic-field convention) are converted; anything else is refused.
/// This is not a unit system: no CGS beyond Oe, no other quantities, no free-text matching.
enum ResultUnitConversion {
    enum Outcome: Equatable {
        /// Same unit: the value is written as is.
        case identical(value: Double)
        /// Known compatible unit: `value` is the converted number that would be written.
        case converted(value: Double, note: String)
        /// Unknown, empty or incompatible: nothing may be written.
        case rejected(reason: String)

        var writableValue: Double? {
            switch self {
            case let .identical(value): return value
            case let .converted(value, _): return value
            case .rejected: return nil
            }
        }
    }

    private enum Family { case magneticField, resistance }

    private struct Parsed {
        var family: Family
        var exponent: Int      // power of ten relative to the base unit (T or Ω)
        var isOersted: Bool
    }

    static func convert(_ value: Double, from canonicalUnit: String, to definitionUnit: String) -> Outcome {
        guard value.isFinite else { return .rejected(reason: "The computed value is not a finite number.") }
        let target = definitionUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            return .rejected(reason: "This Result Definition has no unit, so the value cannot be matched. Enter it by hand in the Library if you still want it.")
        }
        guard let source = parse(canonicalUnit) else {
            return .rejected(reason: "The computed unit \(canonicalUnit) is not supported for assignment.")
        }
        guard let destination = parse(target) else {
            return .rejected(reason: "The Definition unit \(target) is not a known unit for this value. Enter it by hand in the Library if you still want it.")
        }
        guard source.family == destination.family else {
            return .rejected(reason: "The Definition unit \(target) measures a different quantity than \(canonicalUnit).")
        }
        if source.exponent == destination.exponent, source.isOersted == destination.isOersted {
            return .identical(value: value)
        }

        let result: Double
        let note: String
        if destination.isOersted {
            // Existing AHE convention (IngestAHESelectionsUseCase): 1 Oe = 1e-4 T.
            let tesla = scaled(value, by: source.exponent)
            result = WorkbenchMagneticFieldUnitConverter.convert(tesla, from: .tesla, to: .oersted)
            note = "1 Oe = 10⁻⁴ T"
        } else if source.isOersted {
            return .rejected(reason: "The computed unit \(canonicalUnit) is not supported for assignment.")
        } else {
            result = scaled(value, by: source.exponent - destination.exponent)
            note = "1 \(canonicalUnit.trimmingCharacters(in: .whitespaces)) = \(factorText(source.exponent - destination.exponent)) \(target)"
        }
        let cleaned = result
        guard cleaned.isFinite else {
            return .rejected(reason: "The converted value is not a finite number.")
        }
        return .converted(value: cleaned, note: note)
    }

    // MARK: - Parsing

    private static func normalized(_ unit: String) -> String {
        unit.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00B5}", with: "u")   // µ micro sign
            .replacingOccurrences(of: "\u{03BC}", with: "u")   // μ Greek mu
            .replacingOccurrences(of: "\u{2126}", with: "Ω")   // Ω ohm sign
            .replacingOccurrences(of: "\u{03A9}", with: "Ω")   // Ω Greek capital omega
    }

    private static func parse(_ unit: String) -> Parsed? {
        let text = normalized(unit)
        guard !text.isEmpty else { return nil }

        // Oersted: the existing magnetic-field convention; no prefixes.
        if text.lowercased() == "oe" { return Parsed(family: .magneticField, exponent: 0, isOersted: true) }

        // Tesla: prefix is case-sensitive; only m and µ are meaningful here.
        if text.hasSuffix("T") {
            let prefix = String(text.dropLast())
            switch prefix {
            case "": return Parsed(family: .magneticField, exponent: 0, isOersted: false)
            case "m": return Parsed(family: .magneticField, exponent: -3, isOersted: false)
            case "u": return Parsed(family: .magneticField, exponent: -6, isOersted: false)
            default: return nil
            }
        }

        // Ohm: Ω or "ohm" (case-insensitive word); SI prefix case matters (mΩ ≠ MΩ).
        var prefix: String?
        if text.hasSuffix("Ω") {
            prefix = String(text.dropLast())
        } else if text.lowercased().hasSuffix("ohm") {
            prefix = String(text.dropLast(3))
        }
        if let prefix {
            switch prefix {
            case "": return Parsed(family: .resistance, exponent: 0, isOersted: false)
            case "m": return Parsed(family: .resistance, exponent: -3, isOersted: false)
            case "u": return Parsed(family: .resistance, exponent: -6, isOersted: false)
            case "k": return Parsed(family: .resistance, exponent: 3, isOersted: false)
            case "M": return Parsed(family: .resistance, exponent: 6, isOersted: false)
            default: return nil
            }
        }
        return nil
    }

    // MARK: - Arithmetic

    /// `value × 10^power`, using division by an exact power of ten for negative powers.
    private static func scaled(_ value: Double, by power: Int) -> Double {
        if power == 0 { return value }
        let factor = pow(10.0, Double(abs(power)))
        return power > 0 ? value * factor : value / factor
    }

    private static func factorText(_ power: Int) -> String {
        power >= 0 ? String(Int(pow(10.0, Double(power)))) : "1/\(Int(pow(10.0, Double(-power))))"
    }
}
