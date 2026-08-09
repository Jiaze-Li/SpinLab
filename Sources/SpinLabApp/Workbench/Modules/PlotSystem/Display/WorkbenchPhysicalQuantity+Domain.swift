import Foundation

/// Bridges Tier-A `WorkbenchPhysicalQuantity` cases (primitive physical quantities) to the
/// shared Domain `PhysicalQuantityID` (2026-08-08 registry migration, Phase 3a). Lives in
/// Workbench/, not Domain/, because it depends on the Workbench-only `WorkbenchPhysicalQuantity`
/// type — Domain must not depend on Workbench (architecture guard, see
/// V5114ArchitectureImportDirectionTests INV-15).
///
/// Tier-B cases (`.rahe1omega`, `.rahe3omega`, `.raheCombined`, `.hallResistance`, `.sigmaXX`,
/// `.scalingLawX`, `.scalingLawY`, `.temperatureDependenceERatio`, `.diffractionIntensity`) are
/// derived/analysis-specific display labels, not persisted domain identity, and return `nil`.
extension WorkbenchPhysicalQuantity {
    var physicalQuantityID: PhysicalQuantityID? {
        switch self {
        case .externalMagneticField: return .externalMagneticField
        case .coerciveField: return .coerciveField
        case .temperature: return .temperature
        case .deviceAngle: return .deviceAngle
        case .angleOffset: return .angleOffset
        case .current: return .current
        case .voltage: return .voltage
        case .resistance1omega: return .resistance1omega
        case .resistance3omega: return .resistance3omega
        case .rxx: return .rxx
        case .rxy: return .rxy
        case .reciprocalH: return .reciprocalH
        case .reciprocalK: return .reciprocalK
        case .reciprocalL: return .reciprocalL
        case .rahe1omega, .rahe3omega, .raheCombined, .hallResistance, .sigmaXX,
             .scalingLawX, .scalingLawY, .temperatureDependenceERatio, .diffractionIntensity:
            return nil
        }
    }
}
