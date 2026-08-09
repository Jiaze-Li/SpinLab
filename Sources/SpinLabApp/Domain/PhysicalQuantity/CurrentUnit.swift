import Foundation

/// Typed current unit dimension, added 2026-08-08 (PhysicalQuantity registry migration,
/// Phase 3a). Milliampere is canonical, matching `config/measuring_condition.json`'s "current"
/// condition (`standardUnit: "mA"`). Microampere is included because that same rule's raw-source
/// matches include "uA" — the only three current units observed anywhere in the codebase.
///
/// Deliberately distinct from `IVCurrentBasis` (Workbench/V3/IVIngestionContracts.swift), which
/// encodes peak-vs-RMS *measurement basis*, not a unit dimension — a peak or RMS reading can be
/// expressed in any of these three units. The two concerns are not merged (2026-08-08 audit §5/§10c).
enum CurrentUnit: String, Codable, Hashable, Sendable, CaseIterable {
    case ampere
    case milliampere
    case microampere
}

enum CurrentUnitConverter {
    /// Converts a current value between units. Milliampere is canonical; all conversions route
    /// through it.
    static func convert(_ value: Double, from: CurrentUnit, to: CurrentUnit) -> Double {
        guard from != to else { return value }
        let mA: Double
        switch from {
        case .ampere: mA = value * 1000.0
        case .milliampere: mA = value
        case .microampere: mA = value * 0.001
        }
        switch to {
        case .ampere: return mA / 1000.0
        case .milliampere: return mA
        case .microampere: return mA / 0.001
        }
    }
}
