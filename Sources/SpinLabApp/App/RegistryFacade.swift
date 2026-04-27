import Foundation

@MainActor
final class RegistryFacade {
    private let managedStorage: SpinLabManagedStorage
    private let registryLifecycleService: RegistryLifecycleService
    private let registryCoordinator: RegistryCoordinator
    private let dataActor: any SpinLabDataActing
    private let appLogger: AppLogger

    private let currentLibrarySettings: () -> LibrarySettings
    private let resolveRegistrySourceURL: () -> URL?
    private let onApplyRegistryContext: (RegistryLoadContext) -> Void
    private let onPresentError: (AppError, String) -> Void
    private let onForwardLoad: (URL) -> Void

    init(
        managedStorage: SpinLabManagedStorage,
        registryLifecycleService: RegistryLifecycleService,
        registryCoordinator: RegistryCoordinator,
        dataActor: any SpinLabDataActing,
        appLogger: AppLogger,
        currentLibrarySettings: @escaping () -> LibrarySettings,
        resolveRegistrySourceURL: @escaping () -> URL?,
        onApplyRegistryContext: @escaping (RegistryLoadContext) -> Void,
        onPresentError: @escaping (AppError, String) -> Void,
        onForwardLoad: @escaping (URL) -> Void
    ) {
        self.managedStorage = managedStorage
        self.registryLifecycleService = registryLifecycleService
        self.registryCoordinator = registryCoordinator
        self.dataActor = dataActor
        self.appLogger = appLogger
        self.currentLibrarySettings = currentLibrarySettings
        self.resolveRegistrySourceURL = resolveRegistrySourceURL
        self.onApplyRegistryContext = onApplyRegistryContext
        self.onPresentError = onPresentError
        self.onForwardLoad = onForwardLoad
    }

    func canReloadSampleRegistry() -> Bool {
        resolveRegistrySourceURL() != nil
    }

    func refreshRoutingRuleMetadata(inboxStore: InboxFeatureStore, forceReload: Bool) {
        let loadResult = registryCoordinator.refreshRoutingRuleMetadata(
            inboxStore: inboxStore,
            forceReload: forceReload
        )
        let sourceFileName = URL(fileURLWithPath: loadResult.metadata.sourcePath).lastPathComponent
        appLogger.info(.import, "Routing rule metadata updated", metadata: [
            "version": "\(loadResult.metadata.version)",
            "source": loadResult.metadata.sourceLabel,
            "sourceFileName": sourceFileName,
            "fingerprint": loadResult.metadata.fingerprint,
            "hashPrefix": loadResult.metadata.contentHashPrefix8
        ])
    }

    func loadSampleRegistry(from url: URL) {
        Task {
            let outcome = await registryCoordinator.loadSampleRegistry(
                from: url,
                managedStorage: managedStorage,
                registryLifecycleService: registryLifecycleService,
                dataActor: dataActor
            )
            await MainActor.run {
                switch outcome {
                case let .success(context):
                    onApplyRegistryContext(context)
                case let .failure(appError):
                    onPresentError(appError, "Registry Load Failed")
                    appLogger.warning(.import, "Sample registry load failed", metadata: ["error": appError.localizedDescription])
                }
            }
        }
    }

    func reloadSampleRegistry() {
        Task {
            let outcome = await registryCoordinator.reloadSampleRegistry(
                librarySettings: currentLibrarySettings(),
                resolveRegistrySourceURL: resolveRegistrySourceURL,
                registryLifecycleService: registryLifecycleService,
                dataActor: dataActor
            )
            await MainActor.run {
                switch outcome {
                case .unavailable:
                    break
                case let .forward(url):
                    onForwardLoad(url)
                case let .success(context):
                    onApplyRegistryContext(context)
                case let .failure(appError):
                    onPresentError(appError, "Registry Reload Failed")
                    appLogger.warning(.import, "Sample registry reload failed", metadata: ["error": appError.localizedDescription])
                }
            }
        }
    }
}
