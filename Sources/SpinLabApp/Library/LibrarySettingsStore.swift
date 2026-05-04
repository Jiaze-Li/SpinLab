import Foundation

final class LibrarySettingsStore {
    private let fileManager = FileManager.default
    private let logger = AppLogger.shared
    let settingsURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    convenience init() {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        let spinLabURL = appSupportURL.appending(path: "SpinLab", directoryHint: .isDirectory)
        let url = spinLabURL.appending(path: "library_settings.json")
        self.init(settingsURL: url)
    }

    init(settingsURL: URL) {
        self.settingsURL = settingsURL

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try? fileManager.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func load() -> LibrarySettings {
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return .default
        }
        let data: Data
        do {
            data = try Data(contentsOf: settingsURL)
        } catch {
            logger.error(.library, "Failed to read library settings", metadata: [
                "path": settingsURL.path,
                "reason": error.localizedDescription
            ])
            return .default
        }
        do {
            let settings = try decoder.decode(LibrarySettings.self, from: data)
            if let rootPath = settings.rootPath, !rootPath.isEmpty,
               !fileManager.fileExists(atPath: rootPath) {
                logger.warning(.library, "Library rootPath does not exist on disk", metadata: [
                    "rootPath": rootPath
                ])
            }
            return settings
        } catch {
            logger.error(.library, "Failed to decode library settings (corrupt file, using defaults)", metadata: [
                "path": settingsURL.path,
                "reason": error.localizedDescription
            ])
            return .default
        }
    }

    func save(_ settings: LibrarySettings) {
        let data: Data
        do {
            data = try encoder.encode(settings)
        } catch {
            logger.error(.library, "Failed to encode library settings", metadata: [
                "reason": error.localizedDescription
            ])
            return
        }

        if fileManager.fileExists(atPath: settingsURL.path) {
            let backupURL = settingsURL.appendingPathExtension("backup")
            do {
                if fileManager.fileExists(atPath: backupURL.path) {
                    try fileManager.removeItem(at: backupURL)
                }
                try fileManager.copyItem(at: settingsURL, to: backupURL)
            } catch {
                logger.warning(.library, "Failed to write settings backup before save (safety net unavailable for this write)", metadata: [
                    "backupPath": backupURL.path,
                    "reason": error.localizedDescription
                ])
            }
        }

        do {
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            logger.error(.library, "Failed to persist library settings", metadata: [
                "path": settingsURL.path,
                "reason": error.localizedDescription
            ])
        }
    }
}
