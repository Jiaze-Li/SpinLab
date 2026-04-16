import Foundation

extension LibraryFeatureStore {
    // MARK: - Global Manual Logs

    func loadLibraryGlobalManualLogs(resolveRegistrySourceURL: () -> URL?) -> LoadLibraryLogOutcome {
        libraryGlobalManualLogError = nil
        libraryGlobalManualLogMessage = nil

        guard let registrySourceURL = resolveRegistrySourceURL() else {
            let error = AppError.notFound("No registry source found. Load registry from Library first.")
            libraryGlobalManualLogError = error.localizedDescription
            libraryGlobalManualLogs = []
            return .failure(error)
        }

        do {
            let entries = try libraryStore.loadRegistryManualUpdateLogEntries(registrySourceURL: registrySourceURL)
            libraryGlobalManualLogs = entries
            let message = "Loaded \(entries.count) global log entries."
            libraryGlobalManualLogMessage = message
            return .success(count: entries.count, message: message)
        } catch {
            let appError = AppError.from(error, fallback: "Failed to load global manual logs.")
            libraryGlobalManualLogError = appError.localizedDescription
            libraryGlobalManualLogs = []
            return .failure(appError)
        }
    }

    // MARK: - Metadata Sync Logs

    func loadLibraryMetadataSyncLogs(resolveRegistrySourceURL: () -> URL?) -> LoadLibraryLogOutcome {
        libraryMetadataSyncLogError = nil
        libraryMetadataSyncLogMessage = nil

        guard let registrySourceURL = resolveRegistrySourceURL() else {
            let error = AppError.notFound("No registry source found. Load registry from Library first.")
            libraryMetadataSyncLogError = error.localizedDescription
            libraryMetadataSyncLogs = []
            return .failure(error)
        }

        do {
            let entries = try libraryStore.loadRegistryMetadataSyncLogEntries(registrySourceURL: registrySourceURL)
            libraryMetadataSyncLogs = entries
            let message = "Loaded \(entries.count) metadata log entries."
            libraryMetadataSyncLogMessage = message
            return .success(count: entries.count, message: message)
        } catch {
            let appError = AppError.from(error, fallback: "Failed to load metadata sync logs.")
            libraryMetadataSyncLogError = appError.localizedDescription
            libraryMetadataSyncLogs = []
            return .failure(appError)
        }
    }

    // MARK: - Log Status Update

    func markLibraryGlobalManualLogStatus(
        rowIndex: Int,
        status: LibraryManualLogStatus,
        statusChangedBy: String = "user",
        resolveRegistrySourceURL: () -> URL?
    ) -> MarkLibraryLogStatusOutcome {
        libraryGlobalManualLogError = nil
        libraryGlobalManualLogMessage = nil

        guard let registrySourceURL = resolveRegistrySourceURL() else {
            let error = AppError.notFound("No registry source found. Load registry from Library first.")
            libraryGlobalManualLogError = error.localizedDescription
            return .failure(error)
        }

        do {
            try libraryStore.updateRegistryManualUpdateLogStatus(
                registrySourceURL: registrySourceURL,
                rowIndex: rowIndex,
                status: status,
                statusChangedBy: statusChangedBy
            )
        } catch {
            let appError = AppError.from(error, fallback: "Failed to update manual log status.")
            libraryGlobalManualLogError = appError.localizedDescription
            return .failure(appError)
        }

        switch loadLibraryGlobalManualLogs(resolveRegistrySourceURL: resolveRegistrySourceURL) {
        case .success:
            let message = "Updated status for log row \(rowIndex) to \(status.rawValue)."
            libraryGlobalManualLogMessage = message
            return .success(message: message)
        case let .failure(error):
            return .failure(error)
        }
    }
}
