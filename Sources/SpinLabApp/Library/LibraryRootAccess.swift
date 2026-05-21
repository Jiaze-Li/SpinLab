import Foundation

enum LibraryRootAccessStatus: Sendable, Equatable {
    case available(rootURL: URL)
    case missingBookmark
    case staleBookmark(rootURL: URL)
    case fallback(rootURL: URL)
}

/// Central access helper for traversing the Library Root.
///
/// The helper resolves the stored bookmark first. In sandboxed builds,
/// bookmark failure is treated as a hard access problem so the UI can ask
/// the user to reselect the Library Root. In non-sandbox/dev runs, it falls
/// back to the raw path with a warning.
struct LibraryRootAccess: Sendable {
    func resolveRootURL(
        settings: LibrarySettings,
        sandboxed: Bool = Self.isSandboxed()
    ) -> LibraryRootAccessStatus {
        guard let rootPath = settings.rootPath, !rootPath.isEmpty else {
            return .missingBookmark
        }

        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)

        guard let bookmarkData = settings.rootBookmarkData, !bookmarkData.isEmpty else {
            return sandboxed ? .missingBookmark : .fallback(rootURL: rootURL)
        }

        var stale = false
        do {
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if stale {
                return sandboxed ? .staleBookmark(rootURL: resolvedURL) : .fallback(rootURL: resolvedURL)
            }
            return .available(rootURL: resolvedURL)
        } catch {
            return sandboxed ? .missingBookmark : .fallback(rootURL: rootURL)
        }
    }

    func withAccess<T>(
        settings: LibrarySettings,
        sandboxed: Bool = Self.isSandboxed(),
        _ body: (URL) throws -> T
    ) rethrows -> T {
        switch resolveRootURL(settings: settings, sandboxed: sandboxed) {
        case .available(let rootURL), .staleBookmark(let rootURL), .fallback(let rootURL):
            let started = rootURL.startAccessingSecurityScopedResource()
            defer {
                if started {
                    rootURL.stopAccessingSecurityScopedResource()
                }
            }
            return try body(rootURL)
        case .missingBookmark:
            return try body(URL(fileURLWithPath: settings.rootPath ?? "", isDirectory: true))
        }
    }

    func enumerateSidecarURLs(
        settings: LibrarySettings,
        fileManager: FileManager = .default,
        sandboxed: Bool = Self.isSandboxed()
    ) -> (status: LibraryRootAccessStatus, urls: [URL]) {
        let status = resolveRootURL(settings: settings, sandboxed: sandboxed)
        switch status {
        case .available, .staleBookmark, .fallback:
            break
        case .missingBookmark:
            return (status, [])
        }

        return (status, withAccess(settings: settings, sandboxed: sandboxed) { actualRoot in
            let enumerator = fileManager.enumerator(
                at: actualRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            guard let enumerator else { return [] }

            var urls: [URL] = []
            for case let fileURL as URL in enumerator {
                guard fileURL.lastPathComponent.hasSuffix(".spinlab.json") else { continue }
                let normalizedPath = fileURL.path.replacingOccurrences(of: "\\", with: "/").lowercased()
                guard normalizedPath.contains("/measurements/") else { continue }
                urls.append(fileURL)
            }
            return urls
        })
    }

    private static func isSandboxed() -> Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
}
