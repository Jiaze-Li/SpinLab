import Foundation

struct LibraryRegistrySyncService {
    let libraryStore: LibraryStore
    private let xlsxSyncService = LibraryXLSXSyncService()

    func syncEditedSample(
        oldSample: LibrarySample,
        updatedSample: LibrarySample,
        registrySourceURL: URL
    ) throws -> LibraryRegistrySourceSyncResult {
        let changes = libraryStore.sampleChangeItems(old: oldSample, new: updatedSample)

        let metadataWrites: [LibraryXLSXSyncService.MetadataWrite] = changes.compactMap { change in
            guard change.key.hasPrefix("metadata.") else {
                return nil
            }
            let key = String(change.key.dropFirst("metadata.".count))
            return LibraryXLSXSyncService.MetadataWrite(
                key: key,
                oldValue: change.oldValue,
                newValue: change.newValue
            )
        }

        let numericLogs: [LibraryXLSXSyncService.NumericLogWrite] = changes.compactMap { change in
            guard change.key.hasPrefix("numeric.") else {
                return nil
            }
            return LibraryXLSXSyncService.NumericLogWrite(
                key: String(change.key.dropFirst("numeric.".count)),
                oldValue: change.oldValue,
                newValue: change.newValue
            )
        }

        return try xlsxSyncService.syncEditedSample(
            oldSample: oldSample,
            updatedSample: updatedSample,
            registrySourceURL: registrySourceURL,
            metadataWrites: metadataWrites,
            numericWrites: numericLogs
        )
    }
}
