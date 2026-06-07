import Foundation
import Observation

enum RulesBookState: Equatable {
    case notConfigured
    case incompleteBook([String])
    case ready
}

@MainActor
@Observable
final class RulesBookSettings {
    private(set) var rulesBookURL: URL?
    let internalPaths: AppInternalPaths

    var rulesBookPaths: RulesConfigPaths? {
        guard let url = rulesBookURL else { return nil }
        return RulesConfigPaths(configDirectoryURL: url)
    }

    var hasLegacyApplicationSupportRules: Bool {
        let legacyDir = internalPaths.appSupportDirectoryURL.appendingPathComponent("config")
        let legacyPaths = RulesConfigPaths(configDirectoryURL: legacyDir)
        return FileManager.default.fileExists(atPath: legacyPaths.importFiltersURL.path)
    }

    var legacyApplicationSupportPaths: RulesConfigPaths {
        RulesConfigPaths(configDirectoryURL:
            internalPaths.appSupportDirectoryURL.appendingPathComponent("config"))
    }

    init(internalPaths: AppInternalPaths = AppInternalPaths()) {
        self.internalPaths = internalPaths
        loadFromDisk()
    }

    func configure(url: URL) {
        rulesBookURL = url
        saveToDisk()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        let settingsURL = internalPaths.rulesBookSettingsURL
        guard let data = try? Data(contentsOf: settingsURL),
              let raw = try? JSONDecoder().decode(Stored.self, from: data),
              !raw.rulesBookPath.isEmpty else { return }
        let resolved = URL(fileURLWithPath: raw.rulesBookPath)
            .standardizedFileURL.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir),
              isDir.boolValue else {
            AppLogger.shared.warning(.system, "RulesBookSettings: configured path no longer exists",
                                     metadata: ["path": raw.rulesBookPath])
            return
        }
        rulesBookURL = resolved
    }

    private func saveToDisk() {
        guard let url = rulesBookURL else { return }
        guard let data = try? JSONEncoder().encode(Stored(rulesBookPath: url.path)) else { return }
        do {
            try FileManager.default.createDirectory(
                at: internalPaths.appSupportDirectoryURL,
                withIntermediateDirectories: true)
            try data.write(to: internalPaths.rulesBookSettingsURL, options: .atomic)
        } catch {
            AppLogger.shared.error(.system, "RulesBookSettings: save failed",
                                   metadata: ["reason": error.localizedDescription])
        }
    }

    private struct Stored: Codable {
        var rulesBookPath: String
    }
}
