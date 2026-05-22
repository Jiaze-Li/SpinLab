import Foundation

// MARK: - Chart Asset Audit Report

struct ChartAssetAuditReport: Sendable {
    struct OrphanFile: Sendable, Hashable, Identifiable {
        var id: String { relativePath }
        var relativePath: String
        var sampleKey: String?
        var filename: String
    }

    struct MissingActiveFile: Sendable, Hashable {
        var chartIdentityKey: String
        var relativePath: String
        var sampleKey: String
    }

    var activeChartCount: Int
    var orphanImages: [OrphanFile]
    var orphanManifests: [OrphanFile]
    var missingActiveImages: [MissingActiveFile]
    var missingActiveManifests: [MissingActiveFile]
}

// MARK: - Chart Asset Audit Service

enum ChartAssetAuditService {

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMddHHmmss"
        return f
    }()

    private static let archiveEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    // MARK: - Audit

    /// Scans the library root and classifies chart assets as active, orphan, or missing.
    /// - Active: referenced by results_index.json and/or measurement_plot_index.json.
    /// - Orphan: PNG/manifest exists on disk but is not referenced by any active index.
    /// - Missing: active reference exists in index but the file is absent on disk.
    nonisolated static func audit(rootURL: URL) -> ChartAssetAuditReport {
        let resolver = LibraryPathResolver(libraryRootURL: rootURL)
        let fm = FileManager.default

        let samplesURL = rootURL.appending(path: "samples")
        let sampleDirs = sampleDirectories(at: samplesURL, using: fm)

        // 1. Collect all active refs from every sample's results_index.json.
        var activeImagePaths = Set<String>()
        var activeManifestPaths = Set<String>()
        var identityByImagePath: [String: String] = [:]
        var identityByManifestPath: [String: String] = [:]
        var sampleKeyByImagePath: [String: String] = [:]
        var sampleKeyByManifestPath: [String: String] = [:]

        for sampleDir in sampleDirs {
            let sk = sampleDir.lastPathComponent
            guard let index = LoadWorkbenchResultsUseCase(pathResolver: resolver).execute(sampleKey: sk) else { continue }
            for ref in index.references {
                activeImagePaths.insert(ref.chartImagePath)
                activeManifestPaths.insert(ref.manifestPath)
                identityByImagePath[ref.chartImagePath] = ref.chartIdentityKey
                identityByManifestPath[ref.manifestPath] = ref.chartIdentityKey
                if sampleKeyByImagePath[ref.chartImagePath] == nil {
                    sampleKeyByImagePath[ref.chartImagePath] = sk
                }
                if sampleKeyByManifestPath[ref.manifestPath] == nil {
                    sampleKeyByManifestPath[ref.manifestPath] = sk
                }
            }
        }

        // 2. Scan charts directories for actual files on disk.
        var foundImagePaths = Set<String>()
        var foundManifestPaths = Set<String>()

        for sampleDir in sampleDirs {
            scanChartsDirectory(sampleDir.appending(path: "charts"), resolver: resolver, fm: fm,
                                images: &foundImagePaths, manifests: &foundManifestPaths)
        }
        scanChartsDirectory(rootURL.appending(path: "_spinlab/multi-sample/charts"), resolver: resolver, fm: fm,
                            images: &foundImagePaths, manifests: &foundManifestPaths)

        // 3. Classify orphans (found on disk but not in any active index).
        let orphanImages = foundImagePaths.subtracting(activeImagePaths).sorted().map { rp in
            ChartAssetAuditReport.OrphanFile(relativePath: rp, sampleKey: sampleKeyFromPath(rp),
                                             filename: URL(fileURLWithPath: rp).lastPathComponent)
        }
        let orphanManifests = foundManifestPaths.subtracting(activeManifestPaths).sorted().map { rp in
            ChartAssetAuditReport.OrphanFile(relativePath: rp, sampleKey: sampleKeyFromPath(rp),
                                             filename: URL(fileURLWithPath: rp).lastPathComponent)
        }

        // 4. Classify missing active files (in active index but absent on disk).
        let missingActiveImages: [ChartAssetAuditReport.MissingActiveFile] = activeImagePaths.sorted().compactMap { rp in
            guard let absURL = try? resolver.absoluteURL(for: rp), !fm.fileExists(atPath: absURL.path) else { return nil }
            return ChartAssetAuditReport.MissingActiveFile(
                chartIdentityKey: identityByImagePath[rp] ?? "",
                relativePath: rp,
                sampleKey: sampleKeyByImagePath[rp] ?? "")
        }
        let missingActiveManifests: [ChartAssetAuditReport.MissingActiveFile] = activeManifestPaths.sorted().compactMap { rp in
            guard let absURL = try? resolver.absoluteURL(for: rp), !fm.fileExists(atPath: absURL.path) else { return nil }
            return ChartAssetAuditReport.MissingActiveFile(
                chartIdentityKey: identityByManifestPath[rp] ?? "",
                relativePath: rp,
                sampleKey: sampleKeyByManifestPath[rp] ?? "")
        }

        return ChartAssetAuditReport(
            activeChartCount: activeImagePaths.count,
            orphanImages: orphanImages,
            orphanManifests: orphanManifests,
            missingActiveImages: missingActiveImages,
            missingActiveManifests: missingActiveManifests
        )
    }

    // MARK: - Archive orphan files

    /// Moves orphan files into `deleted-charts/orphan-{timestamp}/` folders and writes `archive.json`.
    /// Returns count of successfully archived files.
    @discardableResult
    nonisolated static func archiveOrphanFiles(_ relativePaths: [String], rootURL: URL) -> Int {
        guard !relativePaths.isEmpty else { return 0 }
        let resolver = LibraryPathResolver(libraryRootURL: rootURL)
        let fm = FileManager.default
        let timestamp = timestampFormatter.string(from: Date())

        // Group files by their archive directory: parent-of-charts / deleted-charts / orphan-{ts}
        var byArchiveDir: [URL: [(source: URL, relPath: String)]] = [:]
        for relPath in relativePaths {
            guard let sourceURL = try? resolver.absoluteURL(for: relPath),
                  fm.fileExists(atPath: sourceURL.path) else {
                fputs("[SpinLab] ChartAssetAudit: source not found — \(relPath)\n", stderr)
                continue
            }
            let chartsDir = sourceURL.deletingLastPathComponent()
            let sampleDir = chartsDir.deletingLastPathComponent()
            let archiveDir = sampleDir.appending(path: "deleted-charts/orphan-\(timestamp)")
            byArchiveDir[archiveDir, default: []].append((sourceURL, relPath))
        }

        var successCount = 0

        for (archiveDir, entries) in byArchiveDir {
            do {
                try fm.createDirectory(at: archiveDir, withIntermediateDirectories: true)
            } catch {
                fputs("[SpinLab] ChartAssetAudit: cannot create archive dir \(archiveDir.path): \(error)\n", stderr)
                continue
            }

            var archiveEntries: [OrphanArchiveEntry] = []
            for (sourceURL, originalRelPath) in entries {
                let destURL = archiveDir.appending(path: sourceURL.lastPathComponent)
                do {
                    try fm.moveItem(at: sourceURL, to: destURL)
                    let archivedRelPath = (try? resolver.relativePath(for: destURL)) ?? destURL.path
                    archiveEntries.append(OrphanArchiveEntry(
                        originalRelativePath: originalRelPath,
                        archivedRelativePath: archivedRelPath))
                    successCount += 1
                } catch {
                    fputs("[SpinLab] ChartAssetAudit: move failed \(sourceURL.path): \(error)\n", stderr)
                }
            }

            let record = OrphanArchiveRecord(archivedAt: Date(), entries: archiveEntries)
            if let data = try? archiveEncoder.encode(record) {
                let recordURL = archiveDir.appending(path: "archive.json")
                try? data.write(to: recordURL, options: .atomic)
            }
        }

        return successCount
    }

    // MARK: - Helpers

    private static func sampleDirectories(at samplesURL: URL, using fm: FileManager) -> [URL] {
        guard let entries = try? fm.contentsOfDirectory(
            at: samplesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        return entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }

    private static func scanChartsDirectory(
        _ chartsDir: URL,
        resolver: LibraryPathResolver,
        fm: FileManager,
        images: inout Set<String>,
        manifests: inout Set<String>
    ) {
        guard let files = try? fm.contentsOfDirectory(
            at: chartsDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        ) else { return }
        for file in files {
            guard let relPath = try? resolver.relativePath(for: file) else { continue }
            let name = file.lastPathComponent
            if name.hasSuffix(".png") {
                images.insert(relPath)
            } else if name.hasSuffix(".manifest.json") {
                manifests.insert(relPath)
            }
        }
    }

    private static func sampleKeyFromPath(_ relativePath: String) -> String? {
        let parts = relativePath.split(separator: "/", maxSplits: 3)
        guard parts.count >= 2, parts[0] == "samples" else { return nil }
        return String(parts[1])
    }

    // MARK: - Private archive models

    private struct OrphanArchiveEntry: Codable {
        var originalRelativePath: String
        var archivedRelativePath: String
    }

    private struct OrphanArchiveRecord: Codable {
        var schemaVersion: Int
        var archivedAt: Date
        var entries: [OrphanArchiveEntry]

        init(archivedAt: Date, entries: [OrphanArchiveEntry]) {
            schemaVersion = 1
            self.archivedAt = archivedAt
            self.entries = entries
        }
    }
}
