import Foundation

extension LibraryStore {
    func syncBackup(from rootURL: URL, to backupURL: URL) -> Bool {
        // A read-only instance must not push its (possibly stale) view over the shared backup.
        guard LibraryWriteLease.shared.allowsWrite(to: rootURL) else { return false }
        let layout = resolveLayout(at: rootURL)
        if layout.isInvalid { return false }
        // Storage v2 keeps relations in SQLite (WAL) next to files under storage/ and records/.
        // This file-by-file merge cannot produce a point-in-time consistent copy of both, so a v2
        // Library is refused outright (no partial copy, no false success) until a consistent
        // backup exists.
        if layout.isV2 { return false }
        do {
            var isRootDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isRootDirectory), isRootDirectory.boolValue else {
                return false
            }

            try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)
            try mergeBackupContents(from: rootURL, to: backupURL)
            return true
        } catch {
            return false
        }
    }

    func mergeBackupContents(from sourceRootURL: URL, to destinationRootURL: URL) throws {
        let resolvedSourceRoot = sourceRootURL.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = fileManager.enumerator(
            at: resolvedSourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let rootPrefix = resolvedSourceRoot.path.hasSuffix("/") ? resolvedSourceRoot.path : resolvedSourceRoot.path + "/"
        for case let sourceURL as URL in enumerator {
            let resolvedSourcePath = sourceURL.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolvedSourcePath.hasPrefix(rootPrefix) else {
                continue
            }
            let relativePath = String(resolvedSourcePath.dropFirst(rootPrefix.count))
            guard !relativePath.isEmpty else {
                continue
            }

            let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
            let destinationURL = destinationRootURL.appending(path: relativePath, directoryHint: values.isDirectory == true ? .isDirectory : .notDirectory)

            if values.isDirectory == true {
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                continue
            }

            try copyOrReplaceFileIfNeeded(from: sourceURL, to: destinationURL)
        }
    }

    func copyOrReplaceFileIfNeeded(from sourceURL: URL, to destinationURL: URL) throws {
        let parentURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: destinationURL.path) else {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return
        }

        if isSameFile(sourceURL, destinationURL) {
            return
        }

        try fileManager.removeItem(at: destinationURL)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    func isSameFile(_ lhsURL: URL, _ rhsURL: URL) -> Bool {
        guard
            let lhs = try? fileManager.attributesOfItem(atPath: lhsURL.path),
            let rhs = try? fileManager.attributesOfItem(atPath: rhsURL.path),
            let lhsSize = lhs[.size] as? NSNumber,
            let rhsSize = rhs[.size] as? NSNumber
        else {
            return false
        }

        guard lhsSize.int64Value == rhsSize.int64Value else {
            return false
        }

        let lhsModified = lhs[.modificationDate] as? Date
        let rhsModified = rhs[.modificationDate] as? Date
        if lhsModified == rhsModified {
            return true
        }

        return fileContentsEqual(lhsURL, rhsURL)
    }

    func fileContentsEqual(_ lhsURL: URL, _ rhsURL: URL) -> Bool {
        let chunkSize = 64 * 1024

        guard
            let lhsHandle = try? FileHandle(forReadingFrom: lhsURL),
            let rhsHandle = try? FileHandle(forReadingFrom: rhsURL)
        else {
            return false
        }
        defer {
            try? lhsHandle.close()
            try? rhsHandle.close()
        }

        while true {
            guard
                let lhsData = try? lhsHandle.read(upToCount: chunkSize),
                let rhsData = try? rhsHandle.read(upToCount: chunkSize)
            else {
                return false
            }

            guard lhsData == rhsData else {
                return false
            }

            if lhsData.isEmpty {
                return true
            }
        }
    }
}
