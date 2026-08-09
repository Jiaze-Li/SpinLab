import Foundation

/// Stable, persisted identity for Tier-A physical quantities — primitives with a real unit
/// dimension, as opposed to the Workbench display layer's Tier-B cases (raheCombined, sigmaXX,
/// scalingLawX, scalingLawY, temperatureDependenceERatio, hallResistance, diffractionIntensity —
/// analysis/fit outputs, not promoted here; see the 2026-08-08 registry audit §1).
///
/// `rawValue` is the persisted wire format and must not change once a quantity ships in
/// Sidecar/MeasurementData data. Values were chosen to match today's dominant free-text spelling
/// where one already exists (`"field"`, `"temperature"`, `"current"` match the built-in Sidecar
/// condition IDs in `config/measuring_condition.json`; `"Hc"` matches the existing
/// `WorkbenchMetricRecord.metric` string) so introducing this type is non-breaking against
/// existing persisted free-text data.
enum PhysicalQuantityID: String, Codable, Hashable, Sendable, CaseIterable {
    case externalMagneticField = "field"
    case coerciveField = "Hc"
    case temperature = "temperature"
    case deviceAngle = "deviceAngle"
    case angleOffset = "angleOffset"
    case current = "current"
    case voltage = "voltage"
    case resistance1omega = "resistance1omega"
    case resistance3omega = "resistance3omega"
    case rxx = "rxx"
    case rxy = "rxy"
    case reciprocalH = "reciprocalH"
    case reciprocalK = "reciprocalK"
    case reciprocalL = "reciprocalL"
}
