import Foundation
import Testing
@testable import SpinLabApp

/// Phase 4 real-vault read-only validation (spec §22). Runs the parser
/// against the actual Obsidian vault and prints a summary report. Read-only —
/// never writes to the vault. Skips itself (rather than failing) when the
/// vault path does not exist, so this stays safe to run on any machine/CI.
@Suite("V5.4.4 Obsidian real-vault validation (read-only)", .serialized)
struct V544ObsidianRealVaultValidationTests {
    private func withBundledSingleton<T>(_ body: () throws -> T) rethrows -> T {
        let bundledDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SpinLabApp/config")
        let savedPaths = RuleLoader.currentBookPaths
        RuleLoader.configure(bookPaths: RulesConfigPaths(configDirectoryURL: bundledDir), internalPaths: AppInternalPaths())
        defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }
        return try body()
    }

    @Test("read-only parse report against the real vault, if present on this machine")
    func realVaultReport() throws {
        let vaultPath = "/Users/jack/Downloads/PhD/03 Experiments"
        guard FileManager.default.fileExists(atPath: vaultPath) else {
            return
        }

        try withBundledSingleton {
            let before = try snapshotVault(at: vaultPath)
            let index = ObsidianVaultParser.parseVault(at: URL(fileURLWithPath: vaultPath))
            let after = try snapshotVault(at: vaultPath)
            #expect(before == after, "read-only parse must never modify the vault")

            var duplicateBatchGroups = 0
            for batch in index.batches where batch.notePaths.count > 1 { duplicateBatchGroups += 1 }
            var duplicateSampleKeyGroups = 0
            for sample in index.samples where sample.notePaths.count > 1 { duplicateSampleKeyGroups += 1 }

            var conflictCount = 0
            for batch in index.batches {
                for (_, claims) in batch.growthClaims where claims.count > 1 {
                    let distinct = Set(claims.map { $0.value.trimmingCharacters(in: .whitespaces).lowercased() })
                    if distinct.count > 1 { conflictCount += 1 }
                }
            }

            print("""
            === Phase 4 Obsidian Vault Read-Only Validation ===
            note total: \(index.noteCount)
            resolved batches: \(index.batches.count)
            resolved samples: \(index.samples.count)
            unresolved/ambiguous diagnostics: \(index.diagnostics.count)
              - unresolvedSampleIdentity: \(index.diagnostics.filter { $0.kind == .unresolvedSampleIdentity }.count)
              - unresolvedBatchIdentity: \(index.diagnostics.filter { $0.kind == .unresolvedBatchIdentity }.count)
              - ambiguousSampleIdentity: \(index.diagnostics.filter { $0.kind == .ambiguousSampleIdentity }.count)
              - ambiguousBatchIdentity: \(index.diagnostics.filter { $0.kind == .ambiguousBatchIdentity }.count)
              - missingGrowthDate: \(index.diagnostics.filter { $0.kind == .missingGrowthDate }.count)
            duplicate batch note-groups (>1 note per batch): \(duplicateBatchGroups)
            duplicate sampleKey note-groups (>1 note per sample): \(duplicateSampleKeyGroups)
            in-vault growth-field conflicts across notes of the same batch: \(conflictCount)
            example canonical sampleKeys: \(index.samples.prefix(5).map(\.sampleKey))
            === End Report ===
            """)

            #expect(index.noteCount > 0)
        }
    }

    private struct FileFingerprint: Equatable {
        var size: Int
        var modifiedAt: Date
    }

    /// Cheap read-only fingerprint (path + size + mtime per file) to prove the
    /// parse pass didn't touch the vault.
    private func snapshotVault(at path: String) throws -> [String: FileFingerprint] {
        var result: [String: FileFingerprint] = [:]
        let root = URL(fileURLWithPath: path)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return result
        }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            result[url.path] = FileFingerprint(
                size: values.fileSize ?? -1,
                modifiedAt: values.contentModificationDate ?? Date.distantPast
            )
        }
        return result
    }
}
