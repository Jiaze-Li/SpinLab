import Foundation

/// Parsed, canonicalized, and identity-checked repository pointer.
/// A nil result from `load(from:)` means the pointer is absent or invalid; mirror writes are skipped.
struct RepositoryPointer: Sendable {
    let repositoryConfigDir: URL
    let repoRoot: URL

    static let pointerFileName = ".repo_pointer.json"

    // MARK: - Load

    static func load(from url: URL, fileManager: FileManager = .default) -> RepositoryPointer? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data: data, fileManager: fileManager)
    }

    // Exposed separately so tests can parse raw JSON without a file on disk.
    static func parse(data: Data, fileManager: FileManager = .default) -> RepositoryPointer? {
        struct _File: Decodable {
            let version: Int
            let repository_config_dir: String
            let repo_root: String
        }

        guard let raw = try? JSONDecoder().decode(_File.self, from: data) else {
            AppLogger.shared.error(.system, "repo pointer: JSON parse failed, skipping mirror")
            return nil
        }

        guard raw.version == 1 else {
            AppLogger.shared.warning(.system, "repo pointer: unsupported version \(raw.version), skipping mirror")
            return nil
        }

        let rawConfigDir = raw.repository_config_dir.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawRepoRoot = raw.repo_root.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawConfigDir.isEmpty, !rawRepoRoot.isEmpty else {
            AppLogger.shared.warning(.system, "repo pointer: missing required fields, skipping mirror")
            return nil
        }

        let configDir = URL(fileURLWithPath: rawConfigDir).standardizedFileURL.resolvingSymlinksInPath()
        let repoRoot = URL(fileURLWithPath: rawRepoRoot).standardizedFileURL.resolvingSymlinksInPath()

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: repoRoot.path, isDirectory: &isDir), isDir.boolValue else {
            AppLogger.shared.warning(.system, "repo pointer identity check failed: repo_root missing or not a directory, skipping mirror")
            return nil
        }
        guard fileManager.fileExists(atPath: repoRoot.appendingPathComponent(".git").path) else {
            AppLogger.shared.warning(.system, "repo pointer identity check failed: repo_root does not contain .git, skipping mirror")
            return nil
        }

        let repoRootPrefix = repoRoot.path.hasSuffix("/") ? repoRoot.path : repoRoot.path + "/"
        guard configDir.path.hasPrefix(repoRootPrefix) else {
            AppLogger.shared.warning(.system, "repo pointer: repository_config_dir is not under repo_root, skipping mirror")
            return nil
        }

        return RepositoryPointer(repositoryConfigDir: configDir, repoRoot: repoRoot)
    }

    // MARK: - Write (auto-write on first cold start; s6b calls this)

    static func write(to url: URL, repositoryConfigDir: URL, repoRoot: URL) throws {
        let canonConfigDir = repositoryConfigDir.standardizedFileURL.resolvingSymlinksInPath()
        let canonRepoRoot = repoRoot.standardizedFileURL.resolvingSymlinksInPath()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let dict: [String: Any] = [
            "version": 1,
            "repository_config_dir": canonConfigDir.path,
            "repo_root": canonRepoRoot.path,
            "set_at": formatter.string(from: Date())
        ]
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
