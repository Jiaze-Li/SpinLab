import Foundation

/// Typed temperature unit dimension, added 2026-08-08 (PhysicalQuantity registry migration,
/// Phase 3a). Kelvin is canonical, matching every existing temperature consumer
/// (`ThreeOmegaIngestionDomain`, `ThreeOmegaLVMParser`, the Workbench display vocabulary's
/// per-series temperature-value formatter) — none of which currently parses Celsius input.
enum TemperatureUnit: String, Codable, Hashable, Sendable, CaseIterable {
    case kelvin
    case celsius
}

enum TemperatureUnitConverter {
    /// Converts a temperature value between units. Kelvin is canonical; all conversions route
    /// through it. Uses the physically correct 273.15 offset — deliberately NOT the `+273`
    /// approximation `config/measuring_condition.json`'s Sidecar-condition rule uses today. That
    /// JSON rule is a separate, unaudited legacy mechanism (see 2026-08-08 registry audit §10a)
    /// and is out of scope for this migration; this converter must not inherit its rounding.
    static func convert(_ value: Double, from: TemperatureUnit, to: TemperatureUnit) -> Double {
        guard from != to else { return value }
        let kelvin: Double
        switch from {
        case .kelvin: kelvin = value
        case .celsius: kelvin = value + 273.15
        }
        switch to {
        case .kelvin: return kelvin
        case .celsius: return kelvin - 273.15
        }
    }
}
