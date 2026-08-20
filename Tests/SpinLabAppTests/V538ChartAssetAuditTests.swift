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

    // MARK: - Writers

    func writeResultsIndex(sampleKey: String, references: [WorkbenchResultReference]) throws {
        let index = WorkbenchResultsIndex(sampleKey: sampleKey, updatedAt: Date(), references: references)
        let data = try Self.encoder.encode(index)
        let url = rootURL.appending(path: "samples/\(sampleKey)/_spinlab/results_index.json")
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func writeCorruptResultsIndex(sampleKey: String) throws {
        let url = rootURL.appending(path: "samples/\(sampleKey)/_spinlab/results_index.json")
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not valid json".utf8).write(to: url)
    }

    func writePlotIndex(sampleKey: String, entries: [String: [String]]) throws {
        let index = MeasurementPlotIndex(sampleKey: sampleKey, updatedAt: Date(), entries: entries)
        let data = try Self.encoder.encode(index)
        let url = rootURL.appending(path: "samples/\(sampleKey)/_spinlab/measurement_plot_index.json")
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func writePNG(relativePath: String) throws {
        let url = try resolver.absoluteURL(for: relativePath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("PNG".utf8).write(to: url)
    }

    func writeManifest(relativePath: String) throws {
        let url = try resolver.absoluteURL(for: relativePath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: url)
    }

    func fileExists(relativePath: String) -> Bool {
        guard let url = try? resolver.absoluteURL(for: relativePath) else { return false }
        return fm.fileExists(atPath: url.path)
    }

    func makeRef(imagePath: String, manifestPath: String) -> WorkbenchResultReference {
        WorkbenchResultReference(
            chartIdentityKey: "chart_\(UUID().uuidString.prefix(8))",
            chartImagePath: imagePath,
            manifestPath: manifestPath,
            workflowID: "threeOmega",
            generatedAt: Date()
        )
    }

    func loadResultsIndex(sampleKey: String) -> WorkbenchResultsIndex? {
        LoadWorkbenchResultsUseCase(pathResolver: resolver).execute(sampleKey: sampleKey)
    }

    func loadPlotIndex(sampleKey: String) -> MeasurementPlotIndex? {
        LoadMeasurementPlotIndexUseCase(pathResolver: resolver).execute(sampleKey: sampleKey)
    }
}

// MARK: - Audit classification

@Suite("V538 Chart Asset Audit — Classification")
struct V538ClassificationTests {

    @Test("Active chart with existing PNG/manifest is not orphan or missing")
    func activeChartNotOrphanOrMissing() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        let imagePath = "samples/S1/charts/R1ω_20240101_000000_aabbccdd.png"
        let manifestPath = "samples/S1/charts/R1ω_20240101_000000_aabbccdd.manifest.json"
        let ref = fix.makeRef(imagePath: imagePath, manifestPath: manifestPath)
        try fix.writeResultsIndex(sampleKey: "S1", references: [ref])
        try fix.writePNG(relativePath: imagePath)
        try fix.writeManifest(relativePath: manifestPath)

        let report = ChartAssetAuditService.audit(rootURL: fix.rootURL)

        #expect(report.activeChartCount == 1)
        #expect(report.orphanImages.isEmpty)
        #expect(report.orphanManifests.isEmpty)
        #expect(report.missingActiveImages.isEmpty)
        #expect(report.missingActiveManifests.isEmpty)
    }

    @Test("PNG on disk not in any index is classified as orphan image")
    func orphanPNGDetected() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        let orphanPath = "samples/S1/charts/old_chart_orphan.png"
        try fix.writePNG(relativePath: orphanPath)
        try fix.writeResultsIndex(sampleKey: "S1", references: [])

        let report = ChartAssetAuditService.audit(rootURL: fix.rootURL)

        #expect(report.activeChartCount == 0)
        #expect(report.orphanImages.count == 1)
        #expect(report.orphanImages[0].relativePath == orphanPath)
        #expect(report.orphanImages[0].sampleKey == "S1")
    }

    @Test("Manifest on disk not in any index is classified as orphan manifest")
    func orphanManifestDetected() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        let orphanManifestPath = "samples/S2/charts/old_chart_orphan.manifest.json"
        try fix.writeManifest(relativePath: orphanManifestPath)
        try fix.writeResultsIndex(sampleKey: "S2", references: [])

        let report = ChartAssetAuditService.audit(rootURL: fix.rootURL)

        #expect(report.orphanManifests.count == 1)
        #expect(report.orphanManifests[0].relativePath == orphanManifestPath)
        #expect(report.orphanManifests[0].sampleKey == "S2")
    }

    @Test("Active ref whose PNG is absent on disk is classified as missing active image")
    func missingActivePNG() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        let imagePath = "samples/S3/charts/missing_chart.png"
        let manifestPath = "samples/S3/charts/missing_chart.manifest.json"
        let ref = fix.makeRef(imagePath: imagePath, manifestPath: manifestPath)
        try fix.writeResultsIndex(sampleKey: "S3", references: [ref])
        try fix.writeManifest(relativePath: manifestPath)  // manifest present, PNG absent

        let report = ChartAssetAuditService.audit(rootURL: fix.rootURL)

        #expect(report.activeChartCount == 1)
        #expect(report.missingActiveImages.count == 1)
        #expect(report.missingActiveImages[0].relativePath == imagePath)
        #expect(report.missingActiveImages[0].sampleKey == "S3")
        #expect(report.orphanImages.isEmpty)
    }

    @Test("Mix: one active chart + one orphan PNG classified correctly")
    func mixedActiveAndOrphan() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        let activeImagePath = "samples/S4/charts/active_chart.png"
        let activeManifestPath = "samples/S4/charts/active_chart.manifest.json"
        let orphanImagePath = "samples/S4/charts/orphan_chart.png"

        let ref = fix.makeRef(imagePath: activeImagePath, manifestPath: activeManifestPath)
        try fix.writeResultsIndex(sampleKey: "S4", references: [ref])
        try fix.writePNG(relativePath: activeImagePath)
        try fix.writeManifest(relativePath: activeManifestPath)
        try fix.writePNG(relativePath: orphanImagePath)

        let report = ChartAssetAuditService.audit(rootURL: fix.rootURL)

        #expect(report.activeChartCount == 1)
        #expect(report.orphanImages.count == 1)
        #expect(report.orphanImages[0].relativePath == orphanImagePath)
        #expect(report.missingActiveImages.isEmpty)
    }

    @Test("Web export: orphan file is invisible to LoadWorkbenchResultsUseCase")
    func orphanFilesInvisibleToWebExport() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        try fix.writePNG(relativePath: "samples/S7/charts/orphan_web.png")
        try fix.writeResultsIndex(sampleKey: "S7", references: [])

        let index = fix.loadResultsIndex(sampleKey: "S7")
        #expect(index?.references.isEmpty == true)

        let report = ChartAssetAuditService.audit(rootURL: fix.rootURL)
        #expect(report.orphanImages.count == 1)
    }

    // MARK: - Corrupt-index safety (Debt #3 Phase E)

    @Test("Corrupt results_index: sample is reported unreadable, not empty")
    func corruptIndexReportedUnreadable() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        try fix.writeCorruptResultsIndex(sampleKey: "SCORRUPT")

        let report = ChartAssetAuditService.audit(rootURL: fix.rootURL)

        #expect(report.unreadableIndexSampleKeys == ["SCORRUPT"])
    }

    @Test("Corrupt results_index: real chart files owned by that sample are excluded from orphan classification")
    func corruptIndexExcludesRealFilesFromOrphans() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        // A real, still-referenced chart under a sample whose index is corrupt.
        let imagePath = "samples/SCORRUPT/charts/still_referenced.png"
        let manifestPath = "samples/SCORRUPT/charts/still_referenced.manifest.json"
        try fix.writePNG(relativePath: imagePath)
        try fix.writeManifest(relativePath: manifestPath)
        try fix.writeCorruptResultsIndex(sampleKey: "SCORRUPT")

        let report = ChartAssetAuditService.audit(rootURL: fix.rootURL)

        #expect(report.unreadableIndexSampleKeys.contains("SCORRUPT"))
        #expect(report.orphanImages.isEmpty)
        #expect(report.orphanManifests.isEmpty)
        #expect(!report.orphanImages.contains { $0.relativePath == imagePath })
        #expect(!report.orphanManifests.contains { $0.relativePath == manifestPath })
    }

    @Test("Corrupt results_index: deleteOrphanFiles never touches that sample's real chart files")
    func corruptIndexFilesSurviveDeleteOrphans() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        let imagePath = "samples/SCORRUPT/charts/still_referenced.png"
        let manifestPath = "samples/SCORRUPT/charts/still_referenced.manifest.json"
        try fix.writePNG(relativePath: imagePath)
        try fix.writeManifest(relativePath: manifestPath)
        try fix.writeCorruptResultsIndex(sampleKey: "SCORRUPT")

        let report = ChartAssetAuditService.audit(rootURL: fix.rootURL)
        let allOrphanPaths = (report.orphanImages + report.orphanManifests).map(\.relativePath)
        _ = ChartAssetAuditService.deleteOrphanFiles(allOrphanPaths, rootURL: fix.rootURL)

        #expect(fix.fileExists(relativePath: imagePath))
        #expect(fix.fileExists(relativePath: manifestPath))
    }

    @Test("Corrupt index in one sample does not affect classification of a healthy sample")
    func corruptIndexIsolatedFromHealthySample() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        try fix.writeCorruptResultsIndex(sampleKey: "SCORRUPT")

        let orphanPath = "samples/SHEALTHY/charts/real_orphan.png"
        try fix.writePNG(relativePath: orphanPath)
        try fix.writeResultsIndex(sampleKey: "SHEALTHY", references: [])

        let report = ChartAssetAuditService.audit(rootURL: fix.rootURL)

        #expect(report.unreadableIndexSampleKeys == ["SCORRUPT"])
        #expect(report.orphanImages.count == 1)
        #expect(report.orphanImages[0].relativePath == orphanPath)
    }

    @Test("Corrupt sample index + shared multi-sample chart on disk: shared chart is NOT classified as orphan")
    func corruptIndexExcludesSharedMultiSampleChartFromOrphans() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        // A real shared multi-sample chart that could only be referenced by the
        // corrupt sample's results_index.json.
        let sharedImagePath = "_spinlab/multi-sample/charts/shared_chart.png"
        let sharedManifestPath = "_spinlab/multi-sample/charts/shared_chart.manifest.json"
        try fix.writePNG(relativePath: sharedImagePath)
        try fix.writeManifest(relativePath: sharedManifestPath)
        try fix.writeCorruptResultsIndex(sampleKey: "SCORRUPT")

        let report = ChartAssetAuditService.audit(rootURL: fix.rootURL)

        #expect(report.unreadableIndexSampleKeys.contains("SCORRUPT"))
        #expect(!report.orphanImages.contains { $0.relativePath == sharedImagePath })
        #expect(!report.orphanManifests.contains { $0.relativePath == sharedManifestPath })
    }

    @Test("Corrupt sample index + shared multi-sample chart: deleteOrphanFiles cannot receive it from the audit report")
    func corruptIndexSharedChartSurvivesDeleteOrphans() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        let sharedImagePath = "_spinlab/multi-sample/charts/shared_chart.png"
        let sharedManifestPath = "_spinlab/multi-sample/charts/shared_chart.manifest.json"
        try fix.writePNG(relativePath: sharedImagePath)
        try fix.writeManifest(relativePath: sharedManifestPath)
        try fix.writeCorruptResultsIndex(sampleKey: "SCORRUPT")

        let report = ChartAssetAuditService.audit(rootURL: fix.rootURL)
        let allOrphanPaths = (report.orphanImages + report.orphanManifests).map(\.relativePath)
        #expect(!allOrphanPaths.contains(sharedImagePath))
        #expect(!allOrphanPaths.contains(sharedManifestPath))

        _ = ChartAssetAuditService.deleteOrphanFiles(allOrphanPaths, rootURL: fix.rootURL)

        #expect(fix.fileExists(relativePath: sharedImagePath))
        #expect(fix.fileExists(relativePath: sharedManifestPath))
    }

    // MARK: - Path-resolution-failure safety (PR #168 closeout)

    @Test("Path-resolution failure on the results_index path fails closed as .corrupt, not .missing")
    func pathResolutionFailureFailsClosedAsCorrupt() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        let layout = LibraryArtifactLayout(pathResolver: fix.resolver)
        let store = LibraryChartIndexStore(layout: layout)

        // "../../escape" makes the composed relative path
        // ("samples/../../escape/_spinlab/results_index.json") standardize to a
        // location outside the Library root ("samples/.." cancels back to root,
        // then the extra ".." walks above it), tripping LibraryPathResolver's
        // root-escape guard before any file lookup happens. `ChartAssetAuditService`
        // can never source a sample key like this from real directory
        // enumeration (a literal ".." path component cannot exist as a
        // filesystem entry name), so this exercises the fail-closed policy
        // directly against `LibraryChartIndexStore` rather than inventing a
        // filesystem test seam in the audit service.
        let status = store.loadResultsIndexForAudit(sampleKey: "../../escape")

        guard case .corrupt = status else {
            Issue.record("expected .corrupt for an unresolvable results_index path, got \(status)")
            return
        }
    }

    @Test("Path-resolution failure and JSON-decode failure report the same .corrupt case audit relies on to exclude a sample from orphan classification")
    func pathResolutionFailureMatchesDecodeFailureCase() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        let layout = LibraryArtifactLayout(pathResolver: fix.resolver)
        let store = LibraryChartIndexStore(layout: layout)

        try fix.writeCorruptResultsIndex(sampleKey: "SCORRUPT")

        let resolutionFailureStatus = store.loadResultsIndexForAudit(sampleKey: "../../escape")
        let decodeFailureStatus = store.loadResultsIndexForAudit(sampleKey: "SCORRUPT")

        // `ChartAssetAuditService.audit` branches only on the `LibraryIndexReadStatus`
        // case, not on why a read failed — a resolved-path decode failure is already
        // proven (above, `corruptIndexExcludesRealFilesFromOrphans` et al.) to keep
        // that sample's real chart files out of orphan classification. Because a
        // path-resolution failure reports the identical `.corrupt` case, it inherits
        // that same orphan-exclusion guarantee without requiring a directory-based
        // reproduction of the escape case.
        guard case .corrupt = resolutionFailureStatus, case .corrupt = decodeFailureStatus else {
            Issue.record("expected both failure modes to report .corrupt, got \(resolutionFailureStatus) and \(decodeFailureStatus)")
            return
        }
    }
}

// MARK: - Delete orphans

@Suite("V538 Chart Asset Audit — Delete Orphans")
struct V538DeleteOrphanTests {

    @Test("Deleting orphan PNG permanently removes file from disk")
    func deleteOrphanPNGRemovesFile() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        let orphanPath = "samples/S5/charts/orphan.png"
        try fix.writePNG(relativePath: orphanPath)

        let result = ChartAssetAuditService.deleteOrphanFiles([orphanPath], rootURL: fix.rootURL)

        #expect(result.deletedCount == 1)
        #expect(result.failedPaths.isEmpty)
        #expect(!fix.fileExists(relativePath: orphanPath))
    }

    @Test("Deleting orphan manifest permanently removes file from disk")
    func deleteOrphanManifestRemovesFile() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        let orphanPath = "samples/S5/charts/orphan.manifest.json"
        try fix.writeManifest(relativePath: orphanPath)

        let result = ChartAssetAuditService.deleteOrphanFiles([orphanPath], rootURL: fix.rootURL)

        #expect(result.deletedCount == 1)
        #expect(result.failedPaths.isEmpty)
        #expect(!fix.fileExists(relativePath: orphanPath))
    }

    @Test("Deleting orphan files does not rewrite or touch active results_index.json")
    func deleteOrphanDoesNotTouchActiveIndex() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        let activeImagePath = "samples/S6/charts/active.png"
        let activeManifestPath = "samples/S6/charts/active.manifest.json"
        let orphanPath = "samples/S6/charts/orphan.png"

        let ref = fix.makeRef(imagePath: activeImagePath, manifestPath: activeManifestPath)
        try fix.writeResultsIndex(sampleKey: "S6", references: [ref])
        try fix.writePNG(relativePath: activeImagePath)
        try fix.writeManifest(relativePath: activeManifestPath)
        try fix.writePNG(relativePath: orphanPath)

        ChartAssetAuditService.deleteOrphanFiles([orphanPath], rootURL: fix.rootURL)

        let index = fix.loadResultsIndex(sampleKey: "S6")
        #expect(index?.references.count == 1)
        #expect(index?.references[0].chartIdentityKey == ref.chartIdentityKey)
    }

    @Test("Delete orphan then re-audit: orphan no longer appears")
    func deleteThenReauditClearsOrphan() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        let orphanPath = "samples/S6/charts/old_orphan.png"
        try fix.writePNG(relativePath: orphanPath)
        try fix.writeResultsIndex(sampleKey: "S6", references: [])

        let reportBefore = ChartAssetAuditService.audit(rootURL: fix.rootURL)
        #expect(reportBefore.orphanImages.count == 1)

        ChartAssetAuditService.deleteOrphanFiles([orphanPath], rootURL: fix.rootURL)

        let reportAfter = ChartAssetAuditService.audit(rootURL: fix.rootURL)
        #expect(reportAfter.orphanImages.isEmpty)
    }
}

// MARK: - Clean missing references

@Suite("V538 Chart Asset Audit — Clean Missing References")
struct V538CleanMissingRefsTests {

    @Test("Clean removes ref from results_index.json when PNG is absent")
    func cleanRemovesMissingImageRef() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        let imagePath = "samples/S8/charts/gone.png"
        let manifestPath = "samples/S8/charts/gone.manifest.json"
        let ref = fix.makeRef(imagePath: imagePath, manifestPath: manifestPath)
        try fix.writeResultsIndex(sampleKey: "S8", references: [ref])
        // Neither file exists on disk

        let result = ChartAssetAuditService.cleanMissingReferences(rootURL: fix.rootURL)

        #expect(result.cleanedRefCount == 1)
        #expect(result.failedSampleKeys.isEmpty)

        let index = fix.loadResultsIndex(sampleKey: "S8")
        #expect(index?.references.isEmpty == true)
    }

    @Test("Clean removes chartIdentityKey from measurement_plot_index when ref is missing")
    func cleanRemovesKeyFromPlotIndex() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        let imagePath = "samples/S9/charts/gone.png"
        let manifestPath = "samples/S9/charts/gone.manifest.json"
        let ref = fix.makeRef(imagePath: imagePath, manifestPath: manifestPath)
        try fix.writeResultsIndex(sampleKey: "S9", references: [ref])
        try fix.writePlotIndex(sampleKey: "S9", entries: ["source.lvm": [ref.chartIdentityKey]])

        _ = ChartAssetAuditService.cleanMissingReferences(rootURL: fix.rootURL)

        let plotIndex = fix.loadPlotIndex(sampleKey: "S9")
        #expect(plotIndex?.entries.isEmpty ?? true)
    }

    @Test("Clean preserves active refs whose files exist on disk")
    func cleanPreservesActiveRefs() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        let goodImagePath = "samples/SA/charts/good.png"
        let goodManifestPath = "samples/SA/charts/good.manifest.json"
        let brokenImagePath = "samples/SA/charts/broken.png"
        let brokenManifestPath = "samples/SA/charts/broken.manifest.json"

        let goodRef = fix.makeRef(imagePath: goodImagePath, manifestPath: goodManifestPath)
        let brokenRef = fix.makeRef(imagePath: brokenImagePath, manifestPath: brokenManifestPath)

        try fix.writeResultsIndex(sampleKey: "SA", references: [goodRef, brokenRef])
        try fix.writePNG(relativePath: goodImagePath)
        try fix.writeManifest(relativePath: goodManifestPath)
        // brokenRef files are absent

        let result = ChartAssetAuditService.cleanMissingReferences(rootURL: fix.rootURL)

        #expect(result.cleanedRefCount == 1)
        let index = fix.loadResultsIndex(sampleKey: "SA")
        #expect(index?.references.count == 1)
        #expect(index?.references[0].chartIdentityKey == goodRef.chartIdentityKey)
    }

    @Test("After clean, subsequent audit shows zero missing files")
    func cleanReducesMissingCount() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        let imagePath = "samples/SB/charts/missing.png"
        let manifestPath = "samples/SB/charts/missing.manifest.json"
        let ref = fix.makeRef(imagePath: imagePath, manifestPath: manifestPath)
        try fix.writeResultsIndex(sampleKey: "SB", references: [ref])

        let reportBefore = ChartAssetAuditService.audit(rootURL: fix.rootURL)
        #expect(reportBefore.missingActiveImages.count == 1)
        #expect(reportBefore.missingActiveManifests.count == 1)

        _ = ChartAssetAuditService.cleanMissingReferences(rootURL: fix.rootURL)

        let reportAfter = ChartAssetAuditService.audit(rootURL: fix.rootURL)
        #expect(reportAfter.missingActiveImages.isEmpty)
        #expect(reportAfter.missingActiveManifests.isEmpty)
        #expect(reportAfter.activeChartCount == 0)
    }

    @Test("Clean does not delete any files — only rewrites index JSON")
    func cleanDoesNotDeleteFiles() throws {
        let fix = try AuditFixture()
        defer { fix.cleanup() }

        // Write an orphan PNG alongside a missing-ref setup
        let orphanPath = "samples/SC/charts/orphan.png"
        let brokenImagePath = "samples/SC/charts/broken.png"
        let brokenManifestPath = "samples/SC/charts/broken.manifest.json"
        let brokenRef = fix.makeRef(imagePath: brokenImagePath, manifestPath: brokenManifestPath)

        try fix.writePNG(relativePath: orphanPath)
        try fix.writeResultsIndex(sampleKey: "SC", references: [brokenRef])

        _ = ChartAssetAuditService.cleanMissingReferences(rootURL: fix.rootURL)

        // orphan PNG must still be on disk — clean only touches index files
        #expect(fix.fileExists(relativePath: orphanPath))
    }
}
