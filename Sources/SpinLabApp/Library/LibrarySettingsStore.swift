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
        guard let data = try? Data(contentsOf: settingsURL) else {
            return .default
        }
        return (try? decoder.decode(LibrarySettings.self, from: data)) ?? .default
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
