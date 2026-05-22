import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Fixture

private struct AuditFixture {
    let rootURL: URL
    let resolver: LibraryPathResolver
    private let fm = FileManager.default

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    init() throws {
        rootURL = fm.temporaryDirectory.appending(
            path: "spinlab-v538-audit-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        resolver = LibraryPathResolver(libraryRootURL: rootURL)
    }

    func cleanup() { try? fm.removeItem(at: rootURL) }

    // MARK: - Helpers

    func writeResultsIndex(sampleKey: String, references: [WorkbenchResultReference]) throws {
        let index = WorkbenchResultsIndex(sampleKey: sampleKey, updatedAt: Date(), references: references)
        let data = try Self.encoder.encode(index)
        let url = rootURL.appending(path: "samples/\(sampleKey)/_spinlab/results_index.json")
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// Writes a dummy PNG file at the given library-root-relative path.
    func writePNG(relativePath: String) throws {
        let url = try resolver.absoluteURL(for: relativePath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("PNG".utf8).write(to: url)
    }

    /// Writes a dummy manifest JSON file at the given library-root-relative path.
    func writeManifest(relativePath: String) throws {
        let url = try resolver.absoluteURL(for: relativePath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: url)
    }

    /// Builds a WorkbenchResultReference with the given paths, relative to library root.
    func makeRef(sampleKey: String, imagePath: String, manifestPath: String) -> WorkbenchResultReference {
        WorkbenchResultReference(
            chartIdentityKey: "chart_\(UUID().uuidString.prefix(8))",
            chartImagePath: imagePath,
            manifestPath: manifestPath,
            workflowID: "threeOmega",
            generatedAt: Date()
        )
    }
}

// MARK: - Tests

@Suite("V538 Chart Asset Audit")
struct V538ChartAssetAuditTests {

    // MARK: - Audit classification

    @Test("Active chart with existing PNG is not classified as orphan")
    func activeChartNotOrphan() throws {
        let fixture = try AuditFixture()
        defer { fixture.cleanup() }

        let imagePath = "samples/S1/charts/R1ω_20240101_000000_aabbccdd.png"
        let manifestPath = "samples/S1/charts/R1ω_20240101_000000_aabbccdd.manifest.json"
        let ref = fixture.makeRef(sampleKey: "S1", imagePath: imagePath, manifestPath: manifestPath)

        try fixture.writeResultsIndex(sampleKey: "S1", references: [ref])
        try fixture.writePNG(relativePath: imagePath)
        try fixture.writeManifest(relativePath: manifestPath)

        let report = ChartAssetAuditService.audit(rootURL: fixture.rootURL)

        #expect(report.activeChartCount == 1)
        #expect(report.orphanImages.isEmpty)
        #expect(report.orphanManifests.isEmpty)
        #expect(report.missingActiveImages.isEmpty)
        #expect(report.missingActiveManifests.isEmpty)
    }

    @Test("PNG on disk not in any index is classified as orphan image")
    func orphanPNGDetected() throws {
        let fixture = try AuditFixture()
        defer { fixture.cleanup() }

        // Write a PNG that is not referenced by any results_index.json
        let orphanPath = "samples/S1/charts/old_chart_orphan.png"
        try fixture.writePNG(relativePath: orphanPath)

        // No results_index.json exists for this sample (or it exists but is empty)
        try fixture.writeResultsIndex(sampleKey: "S1", references: [])

        let report = ChartAssetAuditService.audit(rootURL: fixture.rootURL)

        #expect(report.activeChartCount == 0)
        #expect(report.orphanImages.count == 1)
        #expect(report.orphanImages[0].relativePath == orphanPath)
        #expect(report.orphanImages[0].sampleKey == "S1")
    }

    @Test("Manifest on disk not in any index is classified as orphan manifest")
    func orphanManifestDetected() throws {
        let fixture = try AuditFixture()
        defer { fixture.cleanup() }

        let orphanManifestPath = "samples/S2/charts/old_chart_orphan.manifest.json"
        try fixture.writeManifest(relativePath: orphanManifestPath)
        try fixture.writeResultsIndex(sampleKey: "S2", references: [])

        let report = ChartAssetAuditService.audit(rootURL: fixture.rootURL)

        #expect(report.orphanManifests.count == 1)
        #expect(report.orphanManifests[0].relativePath == orphanManifestPath)
        #expect(report.orphanManifests[0].sampleKey == "S2")
    }

    @Test("Active ref whose PNG is absent on disk is classified as missing active image")
    func missingActivePNG() throws {
        let fixture = try AuditFixture()
        defer { fixture.cleanup() }

        let imagePath = "samples/S3/charts/missing_chart.png"
        let manifestPath = "samples/S3/charts/missing_chart.manifest.json"
        let ref = fixture.makeRef(sampleKey: "S3", imagePath: imagePath, manifestPath: manifestPath)

        // Index says the chart exists, but we do NOT write the PNG file
        try fixture.writeResultsIndex(sampleKey: "S3", references: [ref])
        // Write only the manifest (so only the PNG is missing)
        try fixture.writeManifest(relativePath: manifestPath)

        let report = ChartAssetAuditService.audit(rootURL: fixture.rootURL)

        #expect(report.activeChartCount == 1)
        #expect(report.missingActiveImages.count == 1)
        #expect(report.missingActiveImages[0].relativePath == imagePath)
        #expect(report.missingActiveImages[0].sampleKey == "S3")
        #expect(report.orphanImages.isEmpty)
    }

    @Test("Mix: one active chart + one orphan PNG classified correctly")
    func mixedActiveAndOrphan() throws {
        let fixture = try AuditFixture()
        defer { fixture.cleanup() }

        let activeImagePath = "samples/S4/charts/active_chart.png"
        let activeManifestPath = "samples/S4/charts/active_chart.manifest.json"
        let orphanImagePath = "samples/S4/charts/orphan_chart.png"

        let ref = fixture.makeRef(sampleKey: "S4", imagePath: activeImagePath, manifestPath: activeManifestPath)
        try fixture.writeResultsIndex(sampleKey: "S4", references: [ref])
        try fixture.writePNG(relativePath: activeImagePath)
        try fixture.writeManifest(relativePath: activeManifestPath)
        try fixture.writePNG(relativePath: orphanImagePath)

        let report = ChartAssetAuditService.audit(rootURL: fixture.rootURL)

        #expect(report.activeChartCount == 1)
        #expect(report.orphanImages.count == 1)
        #expect(report.orphanImages[0].relativePath == orphanImagePath)
        #expect(report.missingActiveImages.isEmpty)
    }

    // MARK: - Archive orphan files

    @Test("Archiving orphan PNG moves it to deleted-charts/orphan-{timestamp}/ and writes archive.json")
    func archiveOrphanPNG() throws {
        let fixture = try AuditFixture()
        defer { fixture.cleanup() }

        let orphanPath = "samples/S5/charts/orphan.png"
        try fixture.writePNG(relativePath: orphanPath)

        let count = ChartAssetAuditService.archiveOrphanFiles([orphanPath], rootURL: fixture.rootURL)
        #expect(count == 1)

        // PNG should no longer be at original location
        let originalURL = try fixture.resolver.absoluteURL(for: orphanPath)
        #expect(!FileManager.default.fileExists(atPath: originalURL.path))

        // deleted-charts/orphan-{ts}/ should exist under samples/S5/
        let deletedChartsURL = fixture.rootURL.appending(path: "samples/S5/deleted-charts")
        let contents = try FileManager.default.contentsOfDirectory(
            at: deletedChartsURL,
            includingPropertiesForKeys: nil
        )
        let orphanFolders = contents.filter { $0.lastPathComponent.hasPrefix("orphan-") }
        #expect(orphanFolders.count == 1)

        // archive.json should exist in the orphan folder
        let archiveJSON = orphanFolders[0].appending(path: "archive.json")
        #expect(FileManager.default.fileExists(atPath: archiveJSON.path))
    }

    @Test("Archiving orphan PNG is reflected in a subsequent audit run")
    func archiveThenReaudit() throws {
        let fixture = try AuditFixture()
        defer { fixture.cleanup() }

        let orphanPath = "samples/S6/charts/old_orphan.png"
        try fixture.writePNG(relativePath: orphanPath)
        try fixture.writeResultsIndex(sampleKey: "S6", references: [])

        let reportBefore = ChartAssetAuditService.audit(rootURL: fixture.rootURL)
        #expect(reportBefore.orphanImages.count == 1)

        ChartAssetAuditService.archiveOrphanFiles([orphanPath], rootURL: fixture.rootURL)

        let reportAfter = ChartAssetAuditService.audit(rootURL: fixture.rootURL)
        #expect(reportAfter.orphanImages.isEmpty)
    }

    @Test("Web export audit: orphan files absent from active index stay invisible to LoadWorkbenchResultsUseCase")
    func orphanFilesNotInActiveIndex() throws {
        let fixture = try AuditFixture()
        defer { fixture.cleanup() }

        // Write orphan PNG with no index entry
        try fixture.writePNG(relativePath: "samples/S7/charts/orphan_web.png")
        try fixture.writeResultsIndex(sampleKey: "S7", references: [])

        // Web export reads via LoadWorkbenchResultsUseCase
        let resolver = LibraryPathResolver(libraryRootURL: fixture.rootURL)
        let index = LoadWorkbenchResultsUseCase(pathResolver: resolver).execute(sampleKey: "S7")
        #expect(index?.references.isEmpty == true)

        // Audit sees it as orphan
        let report = ChartAssetAuditService.audit(rootURL: fixture.rootURL)
        #expect(report.orphanImages.count == 1)
    }
}
