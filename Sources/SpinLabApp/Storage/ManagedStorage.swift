import Foundation

enum ManagedStorageError: LocalizedError {
    case createDirectoryFailed(path: String, reason: String)
    case removeExistingRegistryFailed(path: String, reason: String)
    case copyRegistryFailed(source: String, destination: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .createDirectoryFailed(path, reason):
            return "Failed to create directory at \(path): \(reason)"
        case let .removeExistingRegistryFailed(path, reason):
            return "Failed to replace existing registry file at \(path): \(reason)"
        case let .copyRegistryFailed(source, destination, reason):
            return "Failed to copy registry from \(source) to \(destination): \(reason)"
        }
    }
}

struct ImportedMeasurementFile {
    let fileName: String
    let sourceFileURL: URL
    let originalFileURL: URL
}

final class SpinLabManagedStorage {
    private let fileManager = FileManager.default
    private let rootURL: URL

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            self.rootURL = appSupportURL.appending(path: "SpinLab", directoryHint: .isDirectory)
        }

        do {
            try fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: registryDirectoryURL, withIntermediateDirectories: true)
        } catch {
            // Keep initialization non-throwing; runtime operations will surface concrete errors.
        }
    }

    var measurementsDirectoryURL: URL {
        rootURL.appending(path: "measurements", directoryHint: .isDirectory)
    }

    var registryDirectoryURL: URL {
        rootURL.appending(path: "registry", directoryHint: .isDirectory)
    }

    func importMeasurementFiles(
        from urls: [URL],
        allowedFileExtensions: Set<String>,
        ignoredFileExtensions: Set<String> = [],
        excludedOriginalFilePaths: Set<String> = []
    ) -> [ImportedMeasurementFile] {
        let sourceFiles = expandMeasurementSourceFiles(
            from: urls,
            allowedFileExtensions: allowedFileExtensions,
            ignoredFileExtensions: ignoredFileExtensions
        )
        let excluded = Set(excludedOriginalFilePaths.map(normalizedPath))
        var seenInCurrentBatch: Set<String> = []
        return sourceFiles.compactMap { sourceURL in
            let originalPath = normalizedPath(sourceURL.path)
            guard !excluded.contains(originalPath) else {
                return nil
            }
            guard seenInCurrentBatch.insert(originalPath).inserted else {
                return nil
            }
            return ImportedMeasurementFile(
                fileName: sourceURL.lastPathComponent,
                sourceFileURL: sourceURL,
                originalFileURL: sourceURL
            )
        }
    }

    func isManagedMeasurementPath(_ path: String) -> Bool {
        normalizedPath(path).hasPrefix(measurementsDirectoryURL.standardizedFileURL.path + "/")
    }

    func clearManagedMeasurementCopies() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: measurementsDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in urls {
            try? fileManager.removeItem(at: url)
        }
    }

    func installSampleRegistry(from url: URL) throws -> URL {
        let sanitizedName = sanitizedFileName(url.lastPathComponent)
        let destinationURL = registryDirectoryURL.appending(path: sanitizedName)

        do {
            try fileManager.createDirectory(at: registryDirectoryURL, withIntermediateDirectories: true)
        } catch {
            throw ManagedStorageError.createDirectoryFailed(
                path: registryDirectoryURL.path,
                reason: error.localizedDescription
            )
        }

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
        } catch {
            throw ManagedStorageError.removeExistingRegistryFailed(
                path: destinationURL.path,
                reason: error.localizedDescription
            )
        }

        do {
            try fileManager.copyItem(at: url, to: destinationURL)
            return destinationURL
        } catch {
            throw ManagedStorageError.copyRegistryFailed(
                source: url.path,
                destination: destinationURL.path,
                reason: error.localizedDescription
            )
        }
    }

    func currentSampleRegistryFileURL() -> URL? {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: registryDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return urls
            .filter { $0.pathExtension.lowercased() == "xlsx" }
            .sorted {
                let lhsDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
            .first
    }

    private func sanitizedFileName(_ fileName: String) -> String {
        fileName.replacingOccurrences(of: "/", with: "-")
    }

    private func expandMeasurementSourceFiles(
        from urls: [URL],
        allowedFileExtensions: Set<String>,
        ignoredFileExtensions: Set<String>
    ) -> [URL] {
        var collected: [URL] = []

        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                if let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for case let fileURL as URL in enumerator {
                        guard shouldImportMeasurementFile(
                            fileURL,
                            allowedFileExtensions: allowedFileExtensions,
                            ignoredFileExtensions: ignoredFileExtensions
                        ) else {
                            continue
                        }
                        collected.append(fileURL)
                    }
                }
            } else if shouldImportMeasurementFile(
                url,
                allowedFileExtensions: allowedFileExtensions,
                ignoredFileExtensions: ignoredFileExtensions
            ) {
                collected.append(url)
            }
        }

        return collected.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func shouldImportMeasurementFile(
        _ url: URL,
        allowedFileExtensions: Set<String>,
        ignoredFileExtensions: Set<String>
    ) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else {
            return false
        }
        guard !ignoredFileExtensions.contains(ext) else {
            return false
        }
        return allowedFileExtensions.contains(ext)
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
