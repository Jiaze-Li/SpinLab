import Foundation

@MainActor extension LibraryFeatureStore {

    func updateLibraryRoot(to url: URL) {
        librarySettings.rootPath = url.path
        librarySettingsStore.save(librarySettings)
        libraryRootVerificationPath = nil
        libraryRootVerificationMessage = nil
    }

    func updateLibraryBackupPath(to url: URL) {
        librarySettings.backupPath = url.path
        librarySettingsStore.save(librarySettings)
        libraryBackupError = nil
    }

    func updateAllowedBatchPrefixes(from rawValue: String) {
        let prefixes = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        librarySettings.allowedBatchPrefixes = prefixes
        librarySettingsStore.save(librarySettings)
    }

    func verifyLibraryRoot() {
        guard let rootPath = librarySettings.rootPath else {
            libraryRootVerificationMessage = "No Library Root selected."
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        guard let verifyURL = libraryStore.verifyRoot(at: rootURL) else {
            libraryRootVerificationMessage = "Failed to verify Library Root."
            return
        }
        libraryRootVerificationPath = verifyURL.path
        libraryRootVerificationMessage = "Library Root verified."
    }

    func syncLibraryBackup(formatSyncDate: (Date) -> String) {
        libraryBackupError = nil

        guard let rootPath = librarySettings.rootPath else {
            libraryBackupError = "No Library Root selected."
            return
        }
        guard let backupPath = librarySettings.backupPath else {
            libraryBackupError = "No Backup Path selected."
            return
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        let backupURL = URL(fileURLWithPath: backupPath)
        let rootStandardPath = rootURL.standardizedFileURL.path
        let backupStandardPath = backupURL.standardizedFileURL.path

        if backupStandardPath == rootStandardPath {
            libraryBackupError = "Backup Path must be different from Library Root."
            return
        }
        if backupStandardPath.hasPrefix(rootStandardPath + "/") || rootStandardPath.hasPrefix(backupStandardPath + "/") {
            libraryBackupError = "Backup Path cannot overlap with Library Root."
            return
        }

        if libraryStore.syncBackup(from: rootURL, to: backupURL) {
            let syncedAt = Date()
            librarySettings.backupLastSyncedAt = syncedAt
            librarySettingsStore.save(librarySettings)
            libraryBackupMessage = "Backup sync successful at \(formatSyncDate(syncedAt))."
        } else {
            libraryBackupError = "Backup sync failed."
        }
    }

    func refreshLibraryBackupMessage(formatSyncDate: (Date) -> String) {
        guard let lastSyncedAt = librarySettings.backupLastSyncedAt else {
            return
        }
        libraryBackupMessage = "Backup sync successful at \(formatSyncDate(lastSyncedAt))."
    }
}
