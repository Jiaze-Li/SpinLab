import Foundation

extension LibraryStore {
    func loadRegistryManualUpdateLogEntries(registrySourceURL: URL) throws -> [LibraryManualUpdateLogEntry] {
        try xlsxSyncService.loadNumericLogEntries(registrySourceURL: registrySourceURL)
    }

    func updateRegistryManualUpdateLogStatus(
        registrySourceURL: URL,
        rowIndex: Int,
        status: LibraryManualLogStatus,
        statusChangedBy: String
    ) throws {
        try xlsxSyncService.updateNumericLogStatus(
            registrySourceURL: registrySourceURL,
            rowIndex: rowIndex,
            status: status,
            statusChangedBy: statusChangedBy
        )
    }

    func loadRegistryMetadataSyncLogEntries(registrySourceURL: URL) throws -> [LibraryMetadataSyncLogEntry] {
        try xlsxSyncService.loadMetadataLogEntries(registrySourceURL: registrySourceURL)
    }
}
