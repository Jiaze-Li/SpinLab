import Foundation

/// Canonical, additive mapping between known built-in Sidecar condition IDs and the shared
/// `PhysicalQuantityID` registry (2026-08-08 registry audit, Phase 3b). Sidecar storage itself
/// is unchanged — conditions remain `[String: SourcedValue]` / `[String: String]`; this mapping
/// only lets typed callers ask "does this condition ID correspond to a known physical quantity?"
///
/// Only conditions with an unambiguous, already-established physical-quantity meaning are
/// mapped. `device` (an arbitrary device-angle-or-wafer label, not a numeric physical quantity in
/// its raw form) and `shift` (a free-text custom condition) are deliberately NOT mapped, per the
/// Phase 3b instructions — forcing them into `PhysicalQuantityID` would misrepresent what they
/// are. Arbitrary user-defined condition IDs are likewise never mapped; `physicalQuantity(for:)`
/// returns `nil` for anything not in this table, and callers must treat `nil` as "keep using the
/// raw string" rather than an error.
enum SidecarPhysicalQuantityMapping {
    /// Built-in Sidecar condition ID -> PhysicalQuantityID. Single source of truth; do not
    /// duplicate this switch elsewhere (see V5114ArchitectureImportDirectionTests INV-16).
    static func physicalQuantity(forConditionID conditionID: String) -> PhysicalQuantityID? {
        switch conditionID {
        case "temperature": return .temperature
        case "field": return .externalMagneticField
        case "current": return .current
        default: return nil
        }
    }

    /// Inverse lookup: the built-in condition ID a given quantity is sourced from, if any.
    /// Quantities with no built-in Sidecar condition (e.g. `.rxx`, `.voltage`) return `nil`.
    static func conditionID(for quantity: PhysicalQuantityID) -> String? {
        switch quantity {
        case .temperature: return "temperature"
        case .externalMagneticField: return "field"
        case .current: return "current"
        default: return nil
        }
    }
}
