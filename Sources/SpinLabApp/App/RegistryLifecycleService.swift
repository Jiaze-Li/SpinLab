import Foundation

struct RegistryPresentationState {
    var registrySourceFilePath: String?
    var registryFileName: String?
    var registryPrefixEntries: [RegistryPrefixEntry]
}

struct RegistryLifecycleService {
    func installRegistry(from sourceURL: URL, managedStorage: SpinLabManagedStorage) throws -> URL {
        try managedStorage.installSampleRegistry(from: sourceURL)
    }

    func loadSnapshot(
        from installedURL: URL,
        previewRowCount: Int,
        dataActor: any SpinLabDataActing
    ) async throws -> SampleRegistrySnapshot {
        try await dataActor.loadRegistrySnapshot(from: installedURL, previewRowCount: previewRowCount)
    }

    func resolveReloadSourceURL(
        librarySettings: LibrarySettings,
        resolveRegistrySourceURL: () -> URL?
    ) -> URL? {
        let fileManager = FileManager.default
        if let sourcePath = librarySettings.registrySourcePath,
           fileManager.fileExists(atPath: sourcePath) {
            return URL(fileURLWithPath: sourcePath)
        }
        return resolveRegistrySourceURL()
    }

    func makePresentationState(from sampleRegistry: SampleRegistryIndexing) -> RegistryPresentationState {
        RegistryPresentationState(
            registrySourceFilePath: sampleRegistry.sourceFilePath,
            registryFileName: sampleRegistry.sourceFilePath.map { URL(fileURLWithPath: $0).lastPathComponent },
            registryPrefixEntries: sampleRegistry.prefixToSheet
                .map { RegistryPrefixEntry(prefix: $0.key, sheetName: $0.value) }
                .sorted { $0.prefix < $1.prefix }
        )
    }
}
