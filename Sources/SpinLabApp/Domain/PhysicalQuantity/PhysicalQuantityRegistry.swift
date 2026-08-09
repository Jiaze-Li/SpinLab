import Foundation

/// Identifies which typed unit-family type (if any) governs a `PhysicalQuantityID`. This is
/// identity metadata only — it never carries a unit *value*; two quantities sharing a family
/// (e.g. `.externalMagneticField` and `.coerciveField` both `.magneticField`) remain distinct
/// `PhysicalQuantityID` cases (2026-08-08 audit §5: quantity identity != unit identity).
enum PhysicalQuantityUnitFamily: Hashable, Sendable {
    case magneticField
    case temperature
    case current
    /// No typed unit family exists yet for this quantity (angle, voltage, resistance,
    /// reciprocal-space coordinates) — current evidence supports alias normalization at most,
    /// not real conversion (2026-08-08 audit §3). Not a placeholder for a future generic type.
    case untyped
}

/// Minimum shared metadata for Tier-A quantities: identity, bare physics symbol, and unit-family
/// membership. Deliberately does NOT own axis labels, manifest labels, math markup, or any other
/// context-dependent display wording — that remains the Workbench display vocabulary's
/// responsibility (2026-08-08 audit §6). Consumers needing formatted display text still go
/// through that layer; this registry is for Sidecar/MeasurementData/Workflow code that needs
/// quantity/unit identity without a Workbench display dependency.
enum PhysicalQuantityRegistry {
    struct Entry: Hashable, Sendable {
        let symbol: String
        let unitFamily: PhysicalQuantityUnitFamily
    }

    static func entry(for id: PhysicalQuantityID) -> Entry {
        switch id {
        case .externalMagneticField:
            return Entry(symbol: "H", unitFamily: .magneticField)
        case .coerciveField:
            return Entry(symbol: "Hc", unitFamily: .magneticField)
        case .temperature:
            return Entry(symbol: "T", unitFamily: .temperature)
        case .current:
            return Entry(symbol: "I", unitFamily: .current)
        case .deviceAngle:
            return Entry(symbol: "Ψ", unitFamily: .untyped)
        case .angleOffset:
            return Entry(symbol: "φ", unitFamily: .untyped)
        case .voltage:
            return Entry(symbol: "V", unitFamily: .untyped)
        case .resistance1omega:
            return Entry(symbol: "R(1ω)", unitFamily: .untyped)
        case .resistance3omega:
            return Entry(symbol: "R(3ω)", unitFamily: .untyped)
        case .rxx:
            return Entry(symbol: "Rxx", unitFamily: .untyped)
        case .rxy:
            return Entry(symbol: "Rxy", unitFamily: .untyped)
        case .reciprocalH:
            return Entry(symbol: "H", unitFamily: .untyped)
        case .reciprocalK:
            return Entry(symbol: "K", unitFamily: .untyped)
        case .reciprocalL:
            return Entry(symbol: "L", unitFamily: .untyped)
        }
    }

    /// Canonical internal unit for each typed unit family, expressed via that family's own typed
    /// enum (never a free-text string). `nil` for `.untyped` quantities.
    static let canonicalMagneticFieldUnit: MagneticFieldUnit = .tesla
    static let canonicalTemperatureUnit: TemperatureUnit = .kelvin
    static let canonicalCurrentUnit: CurrentUnit = .milliampere
}
