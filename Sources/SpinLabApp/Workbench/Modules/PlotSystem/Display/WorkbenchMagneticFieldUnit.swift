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
