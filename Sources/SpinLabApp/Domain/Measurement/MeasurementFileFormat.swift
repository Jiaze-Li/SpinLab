import Foundation

/// Identifies which format loader produced a `LoadedMeasurement`, per the 2026-08-08
/// MeasurementData/Signal architecture audit §8. Only `.zurichLVM` is produced by any loader as
/// of Phase 3c (IV vertical slice) — `.ppmsDAT`/`.rsmText` are declared now so the enum does not
/// need to churn again when RT/AHE/XYRotation/RSM are migrated in later phases, but no loader
/// returns them yet.
enum MeasurementFileFormat: String, Hashable, Sendable {
    case zurichLVM
    case ppmsDAT
    case rsmText
}
