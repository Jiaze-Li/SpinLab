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

    // MARK: - Load from runtime config directory (with auto-write on first cold start)

    /// Loads pointer from `<runtimeConfigDir>/.repo_pointer.json`.
    /// If the file is absent and a dev-build repo can be detected heuristically, writes the pointer first.
    static func load(
        runtimeConfigDir: URL,
        fileManager: FileManager = .default,
        localDevelopmentRepoRootFallback: URL? = nil,
        allowAutoWriteInTests: Bool = false
    ) -> RepositoryPointer? {
        let pointerURL = runtimeConfigDir.appendingPathComponent(pointerFileName)
        if fileManager.fileExists(atPath: pointerURL.path) {
            return load(from: pointerURL, fileManager: fileManager)
        }
        // No pointer file: skip auto-write in test environments
        guard !RulesConfigPaths.isRunningTests() || allowAutoWriteInTests else { return nil }
        if let localDevelopmentRepoRootFallback {
            if let pointer = attemptAutoWrite(
                pointerURL: pointerURL,
                repositoryConfigDir: localDevelopmentRepoRootFallback.appendingPathComponent("Sources/SpinLabApp/config", isDirectory: true),
                repoRoot: localDevelopmentRepoRootFallback,
                fileManager: fileManager
            ) {
                return pointer
            }
        }
        // Try auto-write for developer builds
        guard let repoConfigDir = detectDeveloperRepoConfigDir(from: Bundle.main.bundleURL) else {
            AppLogger.shared.info(.system, "repo pointer: absent and no dev repo detected, skipping mirror")
            return nil
        }
        let repoRoot = repoConfigDir
            .deletingLastPathComponent()  // Sources/SpinLabApp
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()  // repo root
        return attemptAutoWrite(
            pointerURL: pointerURL,
            repositoryConfigDir: repoConfigDir,
            repoRoot: repoRoot,
            fileManager: fileManager
        )
    }

    /// Walks up from `startURL` looking for a dir that contains both `Sources/SpinLabApp/config` and `.git`.
    static func detectDeveloperRepoConfigDir(from startURL: URL) -> URL? {
        var candidate = startURL.standardizedFileURL
        for _ in 0..<12 {
            candidate = candidate.deletingLastPathComponent()
            let configDir = candidate.appendingPathComponent("Sources/SpinLabApp/config")
            let gitDir = candidate.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: configDir.path) &&
               FileManager.default.fileExists(atPath: gitDir.path) {
                return configDir.standardizedFileURL.resolvingSymlinksInPath()
            }
        }
        return nil
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

    private static func attemptAutoWrite(
        pointerURL: URL,
        repositoryConfigDir: URL,
        repoRoot: URL,
        fileManager: FileManager = .default
    ) -> RepositoryPointer? {
        do {
            try write(to: pointerURL, repositoryConfigDir: repositoryConfigDir, repoRoot: repoRoot)
            AppLogger.shared.info(.system, "repo pointer: auto-written for developer build")
        } catch {
            AppLogger.shared.warning(
                .system,
                "repo pointer: auto-write failed, skipping mirror",
                metadata: ["reason": error.localizedDescription]
            )
            return nil
        }
        return load(from: pointerURL, fileManager: fileManager)
    }
}
