import Foundation
import Testing
@testable import SpinLabApp

/// PR #169 repair pass 6 — final correctness hardening.
///
/// Item 1: `XLSXWorkbookKit.commitTransaction`'s final pre-replace
/// fingerprint re-check (closes the TOCTOU window between validation and
/// the atomic replace, independent of whatever fingerprint check the
/// caller already ran before the transaction's own work started).
///
/// Item 2 (Obsidian claim semantic dedup) is covered in
/// `V545RegistryGrowthImportPlannerTests` alongside the other Existing-row
/// reconciliation tests, following this repository's existing convention of
/// keeping planner-behavior coverage in that suite rather than duplicating
/// its fixture plumbing here.
@Suite("PR169 repair pass 6 — final fingerprint verification")
struct PR169RegistryGrowthCorrectnessRepairPass6Tests {
    private func makeFixtureCopy() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "PR169P6-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "registry.xlsx")
        try RegistryGrowthXLSXFixture.build(to: url)
        return url
    }

    @Test("A. Source fingerprint unchanged since the transaction began → commit succeeds")
    func unchangedFingerprintCommitSucceeds() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let expectedFingerprint = try XLSXWorkbookKit.contentFingerprint(of: url)
        let workDir = try XLSXWorkbookKit.prepareWorkingDirectory(for: url)
        defer { try? FileManager.default.removeItem(at: workDir) }

        #expect(throws: Never.self) {
            _ = try XLSXWorkbookKit.commitTransaction(
                workDir: workDir, sourceURL: url, expectedSourceFingerprint: expectedFingerprint
            ) { _ in }
        }
    }

    @Test("B. Source fingerprint changed before the replace step → commit aborts, live file keeps the newer (unexpected) version")
    func changedFingerprintAbortsCommit() throws {
        let url = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        // Fingerprint + working copy captured at "transaction start" — as if
        // this were the plan-build/validation snapshot.
        let expectedFingerprint = try XLSXWorkbookKit.contentFingerprint(of: url)
        let workDir = try XLSXWorkbookKit.prepareWorkingDirectory(for: url)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // A manual edit / cloud-sync change lands on the live file in the
        // window before the atomic replace actually runs.
        try "manually edited after transaction start".data(using: .utf8)!.write(to: url, options: .atomic)
        let liveBytesAfterManualEdit = try Data(contentsOf: url)

        #expect(throws: XLSXWorkbookKitError.self) {
            _ = try XLSXWorkbookKit.commitTransaction(
                workDir: workDir, sourceURL: url, expectedSourceFingerprint: expectedFingerprint
            ) { _ in }
        }
        #expect(try Data(contentsOf: url) == liveBytesAfterManualEdit, "aborted commit must never replace the live file, even with the version it didn't expect")
    }
}
