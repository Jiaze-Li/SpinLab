import Foundation
import Testing
@testable import SpinLabApp

/// Phase 5A real-vault + real-Registry read-only preview (spec §20). Runs
/// `RegistryGrowthImportPlanner` against the actual Obsidian vault and the
/// actual Registry workbook and prints a summary report. Never mutates
/// either — `RegistryGrowthImportPlanner` has no write path at all, and this
/// test additionally fingerprints both before/after to prove it. Skips
/// itself (rather than failing) when either path is absent on this machine.
@Suite("V5.4.5 Registry growth import real-vault/real-Registry preview (read-only)")
struct V545RegistryGrowthRealPreviewTests {
    @Test("read-only import plan preview against the real vault + real Registry, if present on this machine")
    func realPreviewReport() throws {
        let vaultPath = "/Users/jack/Downloads/PhD/03 Experiments"
        let registryPath = "/Users/jack/Library/CloudStorage/OneDrive-NationalUniversityofSingapore/Desktop/Y1 MRAM/实验记录.xlsx"
        guard FileManager.default.fileExists(atPath: vaultPath), FileManager.default.fileExists(atPath: registryPath) else {
            return
        }
        let registryURL = URL(fileURLWithPath: registryPath)

        let registryBefore = try Data(contentsOf: registryURL)
        let vaultBefore = try snapshotVault(at: vaultPath)

        try withBundledRules { provider in
            let obsidian = ObsidianVaultParser.parseVault(at: URL(fileURLWithPath: vaultPath), ruleProvider: provider)
            let library = try LibraryRegistryParser(ruleProvider: provider).parse(
                xlsxURL: registryURL,
                settings: LibrarySettings(
                    rootPath: nil, rootBookmarkData: nil, registryInternalPath: nil,
                    registrySourcePath: registryPath, backupPath: nil, backupLastSyncedAt: nil,
                    allowedBatchPrefixes: [], lastRefreshAt: nil
                )
            ).index
            let dossier = SampleDossierBuilder.build(library: library, obsidian: obsidian)
            let plan = try RegistryGrowthImportPlanner(ruleProvider: provider).build(vault: obsidian, dossier: dossier, registryURL: registryURL)

            var perSheetExecutable: [String: Int] = [:]
            var missingDateBlocked = 0
            var conflictBlocked = 0
            for item in plan.items {
                switch item.action {
                case let .appendNewRow(sheet), let .fillReservedRow(sheet, _):
                    perSheetExecutable[sheet, default: 0] += 1
                case .skipExisting, .blocked:
                    break
                }
                if item.blockingReasons.contains(.missingDate) { missingDateBlocked += 1 }
                if item.blockingReasons.contains(where: {
                    if case .obsidianInternalConflict = $0 { return true }
                    if case .libraryObsidianConflictOnExistingBatch = $0 { return true }
                    return false
                }) { conflictBlocked += 1 }
            }

            let executableBatchIds = plan.items.filter(\.isExecutable).map(\.batchId).sorted()
            let blockedSummaries = plan.items.compactMap { item -> String? in
                guard case let .blocked(reasons) = item.action else { return nil }
                return "\(item.batchId): \(reasons.map { String(describing: $0) }.joined(separator: "; "))"
            }

            // Content-aware routing (§12): report what series each routable
            // sheet's *current* Registry content already exhibits, and how
            // the PN106–115 range resolves under it. Read-only — reuses the
            // same snapshot scan the planner itself performs, never a
            // second parse path.
            let snapshots = try RegistryGrowthImportPlanner.scanRoutableSheets(registryURL: registryURL)
            var observedSeriesBySheet: [String: Set<String>] = [:]
            for sheetName in RegistryGrowthImportPlanner.routableSheetNames {
                guard let snapshot = snapshots[sheetName] else { continue }
                observedSeriesBySheet[sheetName] = Set(snapshot.rows.compactMap { RegistryGrowthRouting.batchSeries(for: $0.batchId) })
            }
            let observedSeriesReport = RegistryGrowthImportPlanner.routableSheetNames
                .map { sheetName -> String in
                    let series = (observedSeriesBySheet[sheetName] ?? []).sorted()
                    return "  \(sheetName) → \(series)"
                }
                .joined(separator: "\n")

            let pnRangeBatchIds = (106...115).map { "PN\($0)" }
            let pnRangeReport = pnRangeBatchIds.map { batchId -> String in
                guard let pnItem = plan.items.first(where: { $0.batchId == batchId }) else {
                    return "  \(batchId): not present in this plan (no Obsidian evidence)"
                }
                let target = RegistryGrowthImportPresentation.targetSheetText(for: pnItem)
                let action = RegistryGrowthImportPresentation.actionBadgeTitle(for: pnItem)
                let reasons = pnItem.blockingReasons.isEmpty ? "" : " — \(RegistryGrowthImportPresentation.blockingReasonsText(for: pnItem))"
                return "  \(batchId): target=\(target) action=\(action)\(reasons)"
            }.joined(separator: "\n")

            print("""
            === Phase 5A Registry Growth Import — Real Vault/Registry Read-Only Preview ===
            vault note total: \(obsidian.noteCount)
            registry batches known (pre-import): \(library.batches.count)
            candidate batches (from Obsidian): \(plan.items.count)
              - appendNewRow: \(plan.appendCount)
              - fillReservedRow: \(plan.fillReservedCount)
              - skipExisting: \(plan.skipExistingCount)
              - blocked: \(plan.blockedCount)
              - missing-date blocked: \(missingDateBlocked)
              - conflict blocked: \(conflictBlocked)
            per-sheet executable counts: \(perSheetExecutable.sorted { $0.key < $1.key })
            executable batch ids: \(executableBatchIds)
            plan-level diagnostics (unattached, e.g. unresolved batch identity): \(plan.diagnostics.count)
            blocked batch reasons:
            \(blockedSummaries.joined(separator: "\n"))
            --- Content-aware routing: observed series per routable sheet ---
            \(observedSeriesReport)
            --- PN106–PN115 under content-aware routing ---
            \(pnRangeReport)
            === End Report — Registry and Obsidian vault were NOT modified ===
            """)
        }

        let registryAfter = try Data(contentsOf: registryURL)
        let vaultAfter = try snapshotVault(at: vaultPath)
        #expect(registryBefore == registryAfter, "planner preview must never modify the real Registry")
        #expect(vaultBefore == vaultAfter, "planner preview must never modify the real Obsidian vault")
    }

    private struct FileFingerprint: Equatable {
        var size: Int
        var modifiedAt: Date
    }

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
