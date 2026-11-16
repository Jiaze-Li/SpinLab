import Foundation

@MainActor extension LibraryFeatureStore {

    func updateLibraryRoot(to url: URL) {
        if let isolation = IsolatedLaunch.active, !isolation.authorizesLibraryRoot(url) {
            libraryRootVerificationMessage = "Isolated test mode: the Library Root is fixed and cannot be changed."
            return
        }
        librarySettings.rootPath = url.path
        librarySettings.rootBookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        librarySettingsStore.save(librarySettings)
        libraryRootVerificationPath = nil
        libraryRootVerificationMessage = nil
    }

    func updateLibraryBackupPath(to url: URL) {
        if let isolation = IsolatedLaunch.active, !isolation.authorizes(url) {
            libraryBackupError = "Isolated test mode: the backup path must stay inside the isolated test folders."
            return
        }
        librarySettings.backupPath = url.path
        librarySettingsStore.save(librarySettings)
        libraryBackupError = nil
    }

    func updateWebLibraryRepoPath(to url: URL) {
        if let isolation = IsolatedLaunch.active, !isolation.authorizes(url) {
            return
        }
        librarySettings.webLibraryRepoPath = url.path
        librarySettingsStore.save(librarySettings)
    }

    /// The Rules Book is the only list of batch prefixes: the library settings copy follows it
    /// (an empty Rules Book list means no prefix filtering, as before).
    func syncBatchPrefixesFromRulesBook(_ override: [String]? = nil) {
        let prefixes = override ?? BatchPrefixes.current()
        guard librarySettings.allowedBatchPrefixes != prefixes else { return }
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
