import Foundation

struct LibraryPathResolver {
    let libraryRootURL: URL

    init(libraryRootURL: URL) {
        self.libraryRootURL = libraryRootURL.standardizedFileURL
    }

    func relativePath(for absoluteURL: URL) throws -> String {
        let normalizedAbsolute = absoluteURL.standardizedFileURL
        guard isContainedInRoot(normalizedAbsolute) else {
            throw AppError.validation("Path is outside Library root: \(absoluteURL.path)")
        }

        let rootPath = libraryRootURL.path
        let absolutePath = normalizedAbsolute.path
        if absolutePath == rootPath {
            return "."
        }
        return String(absolutePath.dropFirst(rootPath.count + 1))
    }

    func absoluteURL(for relativePath: String) throws -> URL {
        let normalizedRelative = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRelative.isEmpty else {
            throw AppError.validation("Relative path cannot be empty.")
        }
        guard normalizedRelative.hasPrefix("/") == false else {
            throw AppError.validation("Absolute path is not allowed in relative-path persistence: \(relativePath)")
        }

        let resolved = libraryRootURL.appending(path: normalizedRelative, directoryHint: .inferFromPath).standardizedFileURL
        guard isContainedInRoot(resolved) else {
            throw AppError.validation("Resolved path escapes Library root: \(relativePath)")
        }
        return resolved
    }

    private func isContainedInRoot(_ absoluteURL: URL) -> Bool {
        let rootPath = libraryRootURL.path
        let absolutePath = absoluteURL.path
        return absolutePath == rootPath || absolutePath.hasPrefix(rootPath + "/")
    }
}
