import Foundation

struct ImportedMeasurementFile {
    let fileName: String
    let sourceFileURL: URL
    let originalFileURL: URL
}

struct InboxImportFilterService: Sendable {
    private let fingerprintService = ContentFingerprintService()

    func importMeasurementFiles(
        from urls: [URL],
        allowedFileExtensions: Set<String>,
        ignoredFileExtensions: Set<String> = [],
        excludedOriginalFilePaths: Set<String> = [],
        excludedContentFingerprints: Set<String> = [],
        excludedFileNames: Set<String> = []
    ) -> [ImportedMeasurementFile] {
        let scannedSourceFiles = scanMeasurementSourceFiles(
            from: urls,
            allowedFileExtensions: allowedFileExtensions,
            ignoredFileExtensions: ignoredFileExtensions,
            excludedOriginalFilePaths: excludedOriginalFilePaths,
            excludedFileNames: excludedFileNames
        )
        var duplicateGuard = DuplicateGuard(
            excludedOriginalPaths: excludedOriginalFilePaths,
            excludedContentFingerprints: excludedContentFingerprints,
            excludedFileNames: excludedFileNames
        )
        return scannedSourceFiles.compactMap { sourceURL in
            let originalPath = sourceURL.path
            let fingerprint = fingerprintService.contentFingerprint(for: sourceURL)
            guard duplicateGuard.accepts(originalPath: originalPath, contentFingerprint: fingerprint) else {
                return nil
            }
            return ImportedMeasurementFile(
                fileName: sourceURL.lastPathComponent,
                sourceFileURL: sourceURL,
                originalFileURL: sourceURL
            )
        }
    }

    func scanMeasurementSourceFiles(
        from urls: [URL],
        allowedFileExtensions: Set<String>,
        ignoredFileExtensions: Set<String> = [],
        excludedOriginalFilePaths: Set<String> = [],
        excludedFileNames: Set<String> = []
    ) -> [URL] {
        let sourceFiles = expandMeasurementSourceFiles(
            from: urls,
            allowedFileExtensions: allowedFileExtensions,
            ignoredFileExtensions: ignoredFileExtensions
        )
        var duplicateGuard = DuplicateGuard(
            excludedOriginalPaths: excludedOriginalFilePaths,
            excludedFileNames: excludedFileNames
        )
        return sourceFiles.filter { sourceURL in
            duplicateGuard.accepts(originalPath: sourceURL.path, contentFingerprint: nil)
        }
    }

    func contentFingerprint(for url: URL) -> String? {
        fingerprintService.contentFingerprint(for: url)
    }

    private func expandMeasurementSourceFiles(
        from urls: [URL],
        allowedFileExtensions: Set<String>,
        ignoredFileExtensions: Set<String>
    ) -> [URL] {
        var collected: [URL] = []

        let fm = FileManager.default
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                if let enumerator = fm.enumerator(
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
        guard !ext.isEmpty else { return false }
        guard !ignoredFileExtensions.contains(ext) else { return false }
        return allowedFileExtensions.contains(ext)
    }
}
