import Foundation

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

        try? fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: registryDirectoryURL, withIntermediateDirectories: true)
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

    func installSampleRegistry(from url: URL) -> URL? {
        let sanitizedName = sanitizedFileName(url.lastPathComponent)
        let destinationURL = registryDirectoryURL.appending(path: sanitizedName)

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: url, to: destinationURL)
            return destinationURL
        } catch {
            return nil
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
