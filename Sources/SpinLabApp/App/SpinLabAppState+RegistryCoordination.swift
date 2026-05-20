import Foundation

extension SpinLabAppState {

    var canReloadSampleRegistry: Bool {
        registryFacade.canReloadSampleRegistry()
    }

    var registryPrefixMap: [String: String] {
        sampleRegistry.prefixToSheet
    }

    func loadSampleRegistry(from url: URL) {
        registryFacade.loadSampleRegistry(from: url)
    }

    func reloadSampleRegistry() {
        registryFacade.reloadSampleRegistry()
    }

    func refreshRoutingRuleMetadata(forceReload: Bool) {
        registryFacade.refreshRoutingRuleMetadata(inboxStore: inboxFeatureStore, forceReload: forceReload)
        if hasRestoredInteractionSnapshot {
            notifyIfRoutingRulesChanged()
        }
    }

    func applyLoadedRegistryContext(_ context: RegistryLoadContext) {
        sampleRegistry = context.registryState
        updateLibraryRegistryPaths(installedURL: context.installedURL, sourceURL: context.sourceURL)
        libraryFeatureStore.libraryPreview = nil
        libraryFeatureStore.libraryPreviewWarnings = []
        libraryFeatureStore.libraryPreviewMessage = nil
        libraryFeatureStore.librarySyncStatusMessage = nil
        registryFeatureStore.applyPresentation(context.presentation)
        refreshPendingDrawerMatches()
    }

    func resolveRegistrySourceURL() -> URL? {
        let fileManager = FileManager.default
        if let sourcePath = libraryFeatureStore.librarySettings.registrySourcePath, fileManager.fileExists(atPath: sourcePath) {
            return URL(fileURLWithPath: sourcePath)
        }
        if let internalPath = libraryFeatureStore.librarySettings.registryInternalPath, fileManager.fileExists(atPath: internalPath) {
            return URL(fileURLWithPath: internalPath)
        }
        if let current = libraryArchiveScan.currentSampleRegistryFileURL(), fileManager.fileExists(atPath: current.path) {
            return current
        }
        return nil
    }

    private func updateLibraryRegistryPaths(installedURL: URL, sourceURL: URL?) {
        libraryFeatureStore.librarySettings.registryInternalPath = installedURL.path
        libraryFeatureStore.librarySettings.registrySourcePath = sourceURL?.path
        libraryFeatureStore.librarySettingsStore.save(libraryFeatureStore.librarySettings)
    }

    func resolvedLibraryRegistryPath() -> String? {
        let fileManager = FileManager.default
        let sourcePath = libraryFeatureStore.librarySettings.registrySourcePath
        let internalPath = libraryFeatureStore.librarySettings.registryInternalPath ?? libraryArchiveScan.currentSampleRegistryFileURL()?.path
        if let sourcePath, fileManager.fileExists(atPath: sourcePath) {
            return sourcePath
        }
        return internalPath
    }
}
