import Foundation

/// Read-time-only normalization of a mapped built-in condition's raw string value into its unit
/// family's canonical unit (2026-08-08 registry audit, Phase 3b). Never mutates Sidecar storage —
/// `effectiveConditions` and `ruleSnapshot` are untouched; this only computes a derived numeric
/// view on demand. Custom or unparseable values return `nil`; callers must fall back to the raw
/// string exactly as before.
///
/// Deliberately independent from `FilenameRuleSet`'s `+273`/`*1000`/etc. `transform` expressions
/// (Import/Rules/FilenameRuleSet.swift), which run once at rule-application time to produce the
/// standardized string this normalizer later reads (e.g. "25C" -> "298K"). By the time a
/// condition value reaches Sidecar storage it already carries its `standardUnit` suffix (`K` for
/// temperature, `T` for field, `mA` for current) — so in practice this normalizer's Celsius/
/// Oersted/Ampere/Microampere branches only fire for values that bypass that pipeline (e.g. a
/// manually-entered override). Because of that split, the JSON rule's `+273` approximation and
/// this normalizer's physically-correct 273.15 offset (`TemperatureUnitConverter`) never compete
/// to convert the same value — see the 2026-08-08 audit §5/Phase 3b notes on why the JSON
/// transform itself was left unchanged this phase (changing it alters live, tested filename-
/// parsing output for Celsius-labeled files, which is out of scope here).
enum SidecarConditionNormalizer {
    /// Parses `rawValue` as `<number><unit suffix>` (e.g. "300K", "0.5T", "10mA") and converts it
    /// to `quantity`'s canonical unit. Returns `nil` when `quantity` has no typed unit family, the
    /// string doesn't parse as a leading number, or the unit suffix isn't recognized for that
    /// family — in every `nil` case the caller's existing raw-string behavior is unaffected.
    static func normalizedCanonicalValue(quantity: PhysicalQuantityID, rawValue: String) -> Double? {
        guard let (numericValue, unitSuffix) = splitNumericAndUnitSuffix(rawValue) else { return nil }

        switch PhysicalQuantityRegistry.entry(for: quantity).unitFamily {
        case .temperature:
            guard let unit = temperatureUnit(forSuffix: unitSuffix) else { return nil }
            return TemperatureUnitConverter.convert(
                numericValue, from: unit, to: PhysicalQuantityRegistry.canonicalTemperatureUnit
            )
        case .magneticField:
            guard let unit = magneticFieldUnit(forSuffix: unitSuffix) else { return nil }
            return WorkbenchMagneticFieldUnitConverter.convert(
                numericValue, from: unit, to: PhysicalQuantityRegistry.canonicalMagneticFieldUnit
            )
        case .current:
            guard let unit = currentUnit(forSuffix: unitSuffix) else { return nil }
            return CurrentUnitConverter.convert(
                numericValue, from: unit, to: PhysicalQuantityRegistry.canonicalCurrentUnit
            )
        case .untyped:
            return nil
        }
    }

    private static func splitNumericAndUnitSuffix(_ raw: String) -> (value: Double, unitSuffix: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let numberRange = trimmed.range(of: #"^-?\d+(\.\d+)?"#, options: .regularExpression) else {
            return nil
        }
        guard let value = Double(trimmed[numberRange]) else { return nil }
        let unitSuffix = trimmed[numberRange.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !unitSuffix.isEmpty else { return nil }
        return (value, unitSuffix)
    }

    private static func temperatureUnit(forSuffix suffix: String) -> TemperatureUnit? {
        switch suffix {
        case "K": return .kelvin
        case "C", "\u{00B0}C": return .celsius
        default: return nil
        }
    }

    private static func magneticFieldUnit(forSuffix suffix: String) -> MagneticFieldUnit? {
        switch suffix {
        case "mT": return .millitesla
        case "T": return .tesla
        case "Oe": return .oersted
        default: return nil
        }
    }

    private static func currentUnit(forSuffix suffix: String) -> CurrentUnit? {
        switch suffix {
        case "mA": return .milliampere
        case "uA", "\u{00B5}A": return .microampere
        case "A": return .ampere
        default: return nil
        }
    }
}

extension SpinLabFileSidecar {
    /// Convenience: normalizes this sidecar's effective condition value for `quantity` (via its
    /// mapped condition ID) into the quantity's canonical unit. `nil` under the same conditions as
    /// `SidecarConditionNormalizer.normalizedCanonicalValue` — including when the quantity has no
    /// built-in condition mapping or the condition is absent.
    func normalizedConditionValue(for quantity: PhysicalQuantityID) -> Double? {
        guard let rawValue = conditionValue(for: quantity) else { return nil }
        return SidecarConditionNormalizer.normalizedCanonicalValue(quantity: quantity, rawValue: rawValue)
    }
}
