import Foundation

struct RegistryLoadContext {
    var snapshot: SampleRegistrySnapshot
    var installedURL: URL
    var sourceURL: URL?
    var registryState: SampleRegistryIndexing
    var presentation: RegistryPresentationState
}

typealias RegistryLoadOutcome = WorkflowOutcome<RegistryLoadContext>
typealias RegistryReloadOutcome = ReloadWorkflowOutcome<RegistryLoadContext>

@MainActor
struct RegistryCoordinator {
    func makePresentation(
        sampleRegistry: SampleRegistryIndexing,
        registryLifecycleService: RegistryLifecycleService
    ) -> RegistryPresentationState {
        registryLifecycleService.makePresentationState(from: sampleRegistry)
    }

    func refreshRoutingRuleMetadata(
        inboxStore: InboxFeatureStore,
        forceReload: Bool
    ) -> RuleLoader.LoadResult {
        inboxStore.refreshRoutingRuleMetadata(forceReload: forceReload)
    }

    func loadSampleRegistry(
        from sourceURL: URL,
        managedStorage: SpinLabManagedStorage,
        registryLifecycleService: RegistryLifecycleService,
        dataActor: any SpinLabDataActing
    ) async -> RegistryLoadOutcome {
        let installedURL: URL
        do {
            installedURL = try registryLifecycleService.installRegistry(from: sourceURL, managedStorage: managedStorage)
        } catch {
            return .failure(AppError.from(error, fallback: "Failed to install sample registry."))
        }

        do {
            let snapshot = try await registryLifecycleService.loadSnapshot(
                from: installedURL,
                previewRowCount: 10,
                dataActor: dataActor
            )
            let registryState = SnapshotSampleRegistryIndex(snapshot: snapshot)
            let presentation = registryLifecycleService.makePresentationState(from: registryState)
            return .success(
                RegistryLoadContext(
                    snapshot: snapshot,
                    installedURL: installedURL,
                    sourceURL: sourceURL,
                    registryState: registryState,
                    presentation: presentation
                )
            )
        } catch {
            return .failure(AppError.from(error, fallback: "Failed to load sample registry."))
        }
    }

    func reloadSampleRegistry(
        librarySettings: LibrarySettings,
        resolveRegistrySourceURL: () -> URL?,
        registryLifecycleService: RegistryLifecycleService,
        dataActor: any SpinLabDataActing
    ) async -> RegistryReloadOutcome {
        guard let fallbackURL = registryLifecycleService.resolveReloadSourceURL(
            librarySettings: librarySettings,
            resolveRegistrySourceURL: resolveRegistrySourceURL
        ) else {
            return .unavailable
        }

        if librarySettings.registrySourcePath == fallbackURL.path {
            return .forward(fallbackURL)
        }

        do {
            let snapshot = try await registryLifecycleService.loadSnapshot(
                from: fallbackURL,
                previewRowCount: 10,
                dataActor: dataActor
            )
            let registryState = SnapshotSampleRegistryIndex(snapshot: snapshot)
            let presentation = registryLifecycleService.makePresentationState(from: registryState)
            return .success(
                RegistryLoadContext(
                    snapshot: snapshot,
                    installedURL: fallbackURL,
                    sourceURL: nil,
                    registryState: registryState,
                    presentation: presentation
                )
            )
        } catch {
            return .failure(AppError.from(error, fallback: "Failed to reload sample registry."))
        }
    }
}
