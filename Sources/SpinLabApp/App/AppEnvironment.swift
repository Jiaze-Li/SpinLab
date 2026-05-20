import Foundation

struct AppEnvironment {
    var persistence: SpinLabPersistence
    var inboxImportFilter: InboxImportFilterService
    var libraryArchiveScan: LibraryArchiveScanService
    var sampleRegistry: SampleRegistryIndexing
    var registrySubstrateRules: any RegistrySubstrateRuleProviding
    var routingCapabilities: RoutingCapabilities
    var ruleRuntime: any RuleRuntimeCapability
    var dataActor: any SpinLabDataActing
    var workflowDefinitionStore: WorkflowDefinitionStore = WorkflowDefinitionStore()
    var libraryAccess: any LibraryAccessCapability = LibraryStore()
    var webLibraryPublisher: any WebLibraryPublishingCapability = WebLibraryPublishService()

    static func live(previewRowCount: Int = 10) -> AppEnvironment {
        AppEnvironment(
            persistence: LocalJSONPersistence(),
            inboxImportFilter: InboxImportFilterService(),
            libraryArchiveScan: LibraryArchiveScanService(),
            sampleRegistry: XLSXPrefixSampleRegistryIndex.fromEnvironment(previewRowCount: previewRowCount),
            registrySubstrateRules: RegistrySubstrateRuleBook(),
            routingCapabilities: .live,
            ruleRuntime: DefaultRuleRuntimeCapability(),
            dataActor: SpinLabDataActor(),
            workflowDefinitionStore: WorkflowDefinitionStore()
        )
    }
}
