import Foundation

/// Typed condition access built on `SidecarPhysicalQuantityMapping`. Does not duplicate condition
/// data — the authoritative stored value remains `effectiveConditions`/`ruleSnapshot`; these are
/// thin, read-only lookups over that same storage (2026-08-08 registry audit, Phase 3b).
extension SpinLabFileSidecar {
    /// The `PhysicalQuantityID` a built-in condition ID maps to, if any.
    func physicalQuantity(forConditionID conditionID: String) -> PhysicalQuantityID? {
        SidecarPhysicalQuantityMapping.physicalQuantity(forConditionID: conditionID)
    }

    /// The raw effective condition string for a given quantity, via its mapped condition ID.
    /// `nil` if the quantity has no built-in condition mapping, or the condition is absent.
    func conditionValue(for quantity: PhysicalQuantityID) -> String? {
        guard let conditionID = SidecarPhysicalQuantityMapping.conditionID(for: quantity) else {
            return nil
        }
        return effectiveConditions[conditionID]
    }
}
