import Foundation

/// Shared magnetic-field unit dimension. `externalMagneticField` and `coerciveField` are distinct
/// physical-quantity identities (see WorkbenchPhysicalQuantity) but both measure in this unit
/// dimension, so the conversion logic is centralized here rather than duplicated per quantity.
enum MagneticFieldUnit: Hashable, Sendable, CaseIterable {
    case oersted
    case tesla
    case millitesla
}

enum WorkbenchMagneticFieldUnitConverter {
    /// Converts a magnetic-field value between units. Oe is the canonical raw-storage unit
    /// (PPMS instrument output); all conversions route through it.
    static func convert(_ value: Double, from: MagneticFieldUnit, to: MagneticFieldUnit) -> Double {
        guard from != to else { return value }
        let oe: Double
        switch from {
        case .oersted: oe = value
        case .tesla: oe = value / 1e-4
        case .millitesla: oe = value / 0.1
        }
        switch to {
        case .oersted: return oe
        case .tesla: return oe * 1e-4
        case .millitesla: return oe * 0.1
        }
    }
}

/// Chooses a magnetic-field display unit (mT vs T) from the magnitude of the values being
/// displayed, so small fields (e.g. coercive fields) read in mT and large fields (e.g. sweep
/// ranges) read in T. `externalMagneticField` and `coerciveField` share this same selector —
/// they remain distinct `WorkbenchPhysicalQuantity` identities; only the unit-selection
/// mechanics are shared. The unit this returns must drive both the numeric conversion and the
/// label — never infer a unit from label text.
enum WorkbenchMagneticFieldDisplayPolicy {
    /// - Parameter canonicalTeslaValues: values already converted to Tesla.
    /// - Returns: `.millitesla` if the max absolute magnitude is below 1.0 T, else `.tesla`.
    ///   Defaults to `.tesla` when `values` is empty — there is no magnitude to measure yet
    ///   (e.g. a manifest skeleton built before any field-sweep data is ingested).
    static func preferredUnit(canonicalTeslaValues values: [Double]) -> MagneticFieldUnit {
        guard let maxAbs = values.map(abs).max() else { return .tesla }
        return maxAbs < 1.0 ? .millitesla : .tesla
    }

    /// Converts `values` from `sourceUnit` to Tesla for magnitude comparison, then selects a
    /// display unit. Does not convert `values` itself — callers convert to the returned unit
    /// separately via `WorkbenchMagneticFieldUnitConverter`.
    static func preferredUnit(values: [Double], sourceUnit: MagneticFieldUnit) -> MagneticFieldUnit {
        preferredUnit(canonicalTeslaValues: values.map {
            WorkbenchMagneticFieldUnitConverter.convert($0, from: sourceUnit, to: .tesla)
        })
    }
}
