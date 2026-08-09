import Foundation

/// Per-column unit identity for a `MeasurementColumn`, added 2026-08-08 (Phase 3c,
/// LoadedMeasurement foundation). Wraps the three typed, convertible unit families that exist
/// today (magnetic field, temperature, current) plus two honest fallback states for everything
/// else, so every loaded column can state what unit its values are already in without a loader
/// ever needing to invent a speculative unit enum for a quantity that has none yet (resistance,
/// voltage, angle, reciprocal-lattice indices — see `PhysicalQuantityRegistry`'s `.untyped`
/// families).
///
/// `.raw` preserves the literal unit text/symbol exactly as the file declared it (e.g. "Ohm" vs
/// "Ohms" are kept distinct, not normalized) — normalization is a workflow/display decision, not
/// a loading fact. `.undeclared` means the file/format provides no unit information at all (e.g.
/// LVM's headerless positional columns).
///
/// This type is purely descriptive. Nothing on `LoadedMeasurement`/`MeasurementColumn` ever
/// converts values — conversion is workflow-owned, via the existing typed converters
/// (`WorkbenchMagneticFieldUnitConverter`, `TemperatureUnitConverter`, `CurrentUnitConverter`).
enum PhysicalQuantityUnitTag: Hashable, Sendable {
    case magneticField(MagneticFieldUnit)
    case temperature(TemperatureUnit)
    case current(CurrentUnit)
    case raw(String)
    case undeclared
}
