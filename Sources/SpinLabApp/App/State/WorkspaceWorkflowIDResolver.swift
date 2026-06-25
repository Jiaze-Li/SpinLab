import Foundation

/// Resolves workspace workflow IDs from the active Rule Book definitions.
///
/// Each workspace slot maps to a definition loaded from `workflow.json`.
/// WorkflowKey is used internally as the lookup key because it is the typed
/// projection of Rule Book IDs; the value returned is always the definition's
/// own `id` field, not the enum raw value directly.
struct WorkspaceWorkflowIDResolver {
    let aheID: String?
    let threeOmegaID: String?
    let xyRotationID: String?
    let ivID: String?
    let rsmID: String?
    let rtID: String?

    init(definitions: [WorkflowDefinition]) {
        func resolve(_ key: WorkflowKey) -> String? {
            definitions.first(where: { $0.id == key.rawValue })?.id
        }
        self.aheID        = resolve(.ahe)
        self.threeOmegaID = resolve(.threeOmega)
        self.xyRotationID = resolve(.xyRotation)
        self.ivID         = resolve(.iv)
        self.rsmID        = resolve(.rsm)
        self.rtID         = resolve(.rt)
    }
}
