import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.5 RulesBootstrapper", .serialized)
struct V515RulesBootstrapperTests {

    private static let backupExtension = "v515-bootstrapper-backup"

    private struct IsolationContext {
        let paths: RulesConfigPaths
        let backup: URL?
    }

    private func acquireIsolation() throws -> IsolationContext {
        let paths = RulesConfigPaths()
        let fm = FileManager.default
        var backup: URL? = nil
        if fm.fileExists(atPath: paths.configDirectoryURL.path) {
            let candidate = paths.configDirectoryURL
                .appendingPathExtension("\(Self.backupExtension).\(UUID().uuidString)")
            try fm.moveItem(at: paths.configDirectoryURL, to: candidate)
            backup = candidate
        }
        return IsolationContext(paths: paths, backup: backup)
    }

    private func releaseIsolation(_ ctx: IsolationContext) {
        let fm = FileManager.default
        if fm.fileExists(atPath: ctx.paths.configDirectoryURL.path) {
            try? fm.removeItem(at: ctx.paths.configDirectoryURL)
        }
        if let backup = ctx.backup, fm.fileExists(atPath: backup.path) {
            try? fm.moveItem(at: backup, to: ctx.paths.configDirectoryURL)
        }
        _ = RuleLoader.shared.reloadCached()
    }

    @Test("all 5 files missing — all seeded from bundle")
    func seedsAllFilesWhenAllMissing() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }

        RulesBootstrapper.seedMissingRuntimeFilesFromBundleIfNeeded()

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: ctx.paths.importFiltersURL.path))
        #expect(fm.fileExists(atPath: ctx.paths.filenameTokenizationURL.path))
        #expect(fm.fileExists(atPath: ctx.paths.sampleIdentificationURL.path))
        #expect(fm.fileExists(atPath: ctx.paths.workflowURL.path))
        #expect(fm.fileExists(atPath: ctx.paths.measuringConditionURL.path))
    }

    @Test("1 of 5 files missing — only missing file seeded, others untouched")
    func seedsOnlyMissingFile() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }

        RulesBootstrapper.seedMissingRuntimeFilesFromBundleIfNeeded()

        let fm = FileManager.default
        let originalData = try Data(contentsOf: ctx.paths.importFiltersURL)
        try fm.removeItem(at: ctx.paths.workflowURL)

        let mTimeBefore = try fm.attributesOfItem(atPath: ctx.paths.importFiltersURL.path)[.modificationDate] as? Date

        RulesBootstrapper.seedMissingRuntimeFilesFromBundleIfNeeded()

        let mTimeAfter = try fm.attributesOfItem(atPath: ctx.paths.importFiltersURL.path)[.modificationDate] as? Date

        #expect(fm.fileExists(atPath: ctx.paths.workflowURL.path))
        // Existing file not re-written
        #expect(mTimeBefore == mTimeAfter)
        #expect((try? Data(contentsOf: ctx.paths.importFiltersURL)) == originalData)
    }

    @Test("second call is a no-op when all files present")
    func isIdempotentWhenAllPresent() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }

        RulesBootstrapper.seedMissingRuntimeFilesFromBundleIfNeeded()
        let mTime1 = try FileManager.default.attributesOfItem(atPath: ctx.paths.workflowURL.path)[.modificationDate] as? Date

        Thread.sleep(forTimeInterval: 0.05)
        RulesBootstrapper.seedMissingRuntimeFilesFromBundleIfNeeded()
        let mTime2 = try FileManager.default.attributesOfItem(atPath: ctx.paths.workflowURL.path)[.modificationDate] as? Date

        #expect(mTime1 == mTime2)
    }
}
