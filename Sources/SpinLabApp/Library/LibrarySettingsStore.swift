import Foundation

final class LibrarySettingsStore {
    private let fileManager = FileManager.default
    private let logger = AppLogger.shared
    private let settingsURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        let spinLabURL = appSupportURL.appending(path: "SpinLab", directoryHint: .isDirectory)
        settingsURL = spinLabURL.appending(path: "library_settings.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try? fileManager.createDirectory(at: spinLabURL, withIntermediateDirectories: true)
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
            return try decoder.decode(LibrarySettings.self, from: data)
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
