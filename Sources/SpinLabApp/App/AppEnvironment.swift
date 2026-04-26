import Foundation

struct AppEnvironment {
    var persistence: SpinLabPersistence
    var managedStorage: SpinLabManagedStorage
    var sampleRegistry: SampleRegistryIndexing
    var registrySubstrateRules: any RegistrySubstrateRuleProviding
    var routingCapabilities: RoutingCapabilities
    var ruleRuntime: any RuleRuntimeCapability
    var dataActor: any SpinLabDataActing
    var workflowRegistryStore: WorkflowRegistryStore = WorkflowRegistryStore()

    static func live(previewRowCount: Int = 10) -> AppEnvironment {
        AppEnvironment(
            persistence: LocalJSONPersistence(),
            managedStorage: SpinLabManagedStorage(),
            sampleRegistry: XLSXPrefixSampleRegistryIndex.fromEnvironment(previewRowCount: previewRowCount),
            registrySubstrateRules: RegistrySubstrateRuleBook(),
            routingCapabilities: .live,
            ruleRuntime: DefaultRuleRuntimeCapability(),
            dataActor: SpinLabDataActor(),
            workflowRegistryStore: WorkflowRegistryStore()
        )
    }
}
