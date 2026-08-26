import Foundation
import Testing
@testable import SpinLabApp

/// Phase 4: ObsidianVaultParser fixture coverage, built from real frontmatter
/// variation observed in the live vault audit (see handoff for the full
/// report) — scalar substrate, substrate lists, key-case aliases (Core/core),
/// missing date, and unresolved/ambiguous identity, none of which should ever
/// be silently guessed into a fake canonical key.
///
/// Uses `withBundledRules` (an `InlineRuleProvider` built from a fresh
/// `RuleLoader` instance) rather than `RuleLoader.configure(...)` on the
/// process-global singleton — `ObsidianVaultParser.parseVault(ruleProvider:)`
/// accepts an injected provider precisely so these tests never touch shared
/// mutable state that other concurrently-running test suites also mutate.
@Suite("V5.4.4 ObsidianVaultParser")
struct V544ObsidianVaultParserTests {
    private func withVaultFixture<T>(_ files: [String: String], _ body: (URL) throws -> T) throws -> T {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SL-obsidian-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (relativePath, contents) in files {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return try body(root)
    }

    @Test("1. batch-only note with multiple substrates yields one Batch record, no resolved Sample")
    func batchOnlyNoteWithMultipleSubstrates() throws {
        try withBundledRules { provider in
            try withVaultFixture([
                "pn114.md": """
                ---
                date: 2026-08-10
                lab: E3-L4
                material: SRO
                substrate:
                  - STO 111
                  - STO 110
                temperature: 750 C
                energy: 100 mJ
                pressure: 80 mT
                sample height: 83 mm
                pulse: 500/600
                ---
                """
            ]) { root in
                let index = ObsidianVaultParser.parseVault(at: root, ruleProvider: provider)
                #expect(index.batches.count == 1)
                #expect(index.batches.first?.batchId == "PN114")
                #expect(index.samples.isEmpty)
                #expect(index.diagnostics.contains { $0.kind == .ambiguousSampleIdentity })
            }
        }
    }

    @Test("2. sample note with batch + single substrate resolves canonical sampleKey")
    func sampleNoteResolvesCanonicalKey() throws {
        try withBundledRules { provider in
            try withVaultFixture([
                "pn104 110.md": """
                ---
                date: 2026-08-04
                lab: E3-L4
                material:
                substrate:
                  - STO 110
                temperature:
                energy:
                pressure:
                sample height: 85 mm
                pulse:
                test_3w: analyzed
                ---
                """
            ]) { root in
                let index = ObsidianVaultParser.parseVault(at: root, ruleProvider: provider)
                #expect(index.samples.count == 1)
                let expected = SampleSemanticDescriptor.withPrevalidatedTokens(
                    batch: "PN104", processingTokens: [], material: "STO", orientation: "110"
                ).canonicalKey
                #expect(index.samples.first?.sampleKey == expected)
                #expect(index.samples.first?.testStatus["3w"]?.first?.value == "analyzed")
            }
        }
    }

    @Test("3. scalar substrate value (not a list) resolves the same as a single-item list")
    func scalarSubstrateResolves() throws {
        try withBundledRules { provider in
            try withVaultFixture([
                "pn106 SRO1.md": """
                ---
                lab: E3-L4
                material: SRO
                substrate: STO 001
                temperature: 750 C
                Core: 检查
                test_3w: completed
                ---
                """
            ]) { root in
                let index = ObsidianVaultParser.parseVault(at: root, ruleProvider: provider)
                #expect(index.samples.count == 1)
                #expect(index.samples.first?.sampleKey.contains("|STO|001") == true)
            }
        }
    }

    @Test("4. substrate list with a filename orientation hint disambiguates the matching entry")
    func substrateListDisambiguatedByFilenameHint() throws {
        try withBundledRules { provider in
            try withVaultFixture([
                "pn113 110.md": """
                ---
                lab: E3-L4
                material: SRO
                substrate:
                  - STO 110
                  - STO 111
                temperature: 700 C
                core: 尝试高能量
                test_3w: planned
                ---
                """
            ]) { root in
                let index = ObsidianVaultParser.parseVault(at: root, ruleProvider: provider)
                #expect(index.samples.count == 1)
                #expect(index.samples.first?.sampleKey.contains("|STO|110") == true)
            }
        }
    }

    @Test("5. key aliases: Core/core, 'sample height', temperature/pressure/energy/pulse all normalize")
    func keyAliasesNormalize() throws {
        try withBundledRules { provider in
            try withVaultFixture([
                "lno17.md": """
                ---
                date: 2026-08-18
                lab: E3-L4
                material: LNO
                substrate:
                  - STO 001
                temperature: 750 C
                energy: 95 mJ
                pressure: 120 mT
                sample height: 83 mm
                pulse: 1000/3000
                ---
                """
            ]) { root in
                let index = ObsidianVaultParser.parseVault(at: root, ruleProvider: provider)
                let batch = try #require(index.batches.first)
                #expect(batch.growthClaims[.growthTemperature]?.first?.value == "750 C")
                #expect(batch.growthClaims[.oxygenPressure]?.first?.value == "120 mT")
                #expect(batch.growthClaims[.laserEnergy]?.first?.value == "95 mJ")
                #expect(batch.growthClaims[.pulseCount]?.first?.value == "1000/3000")
                #expect(batch.growthClaims[.targetSubstrateDistance]?.first?.value == "83 mm")
                #expect(batch.growthClaims[.growthDate]?.first?.value == "2026-08-18")
            }
        }
    }

    @Test("6. missing date is preserved with a diagnostic, never guessed")
    func missingDateProducesDiagnostic() throws {
        try withBundledRules { provider in
            try withVaultFixture([
                "nno1.md": """
                ---
                lab: E3-L4
                material: NNO
                substrate:
                  - STO 001
                temperature: 750 C
                ---
                """
            ]) { root in
                let index = ObsidianVaultParser.parseVault(at: root, ruleProvider: provider)
                #expect(index.batches.first?.growthClaims[.growthDate] == nil)
                #expect(index.diagnostics.contains { $0.kind == .missingGrowthDate })
            }
        }
    }

    @Test("7. note with no substrate signal at all is left as unresolved Sample identity, not UNKNOWN")
    func unresolvedSampleIdentityIsNotGuessed() throws {
        try withBundledRules { provider in
            try withVaultFixture([
                "nco9.md": """
                ---
                date: 2026-08-02
                lab: E3-L4
                material: NCO
                substrate:
                temperature: 400 C
                test_3w: invalid
                ---
                """
            ]) { root in
                let index = ObsidianVaultParser.parseVault(at: root, ruleProvider: provider)
                #expect(index.samples.isEmpty)
                #expect(index.batches.first?.batchId == "NCO9")
                let note = try #require(index.notes.first)
                if case .unresolvedSample = note.identity {
                    // expected
                } else {
                    Issue.record("expected unresolvedSample, got \(note.identity)")
                }
                #expect(index.diagnostics.contains { $0.kind == .unresolvedSampleIdentity })
            }
        }
    }

    @Test("note with no frontmatter block at all is skipped, not treated as a record")
    func noFrontmatterIsSkipped() throws {
        try withBundledRules { provider in
            try withVaultFixture([
                "RT.md": "- [ ] LNO3\n- [ ] LNO4\n"
            ]) { root in
                let index = ObsidianVaultParser.parseVault(at: root, ruleProvider: provider)
                #expect(index.notes.isEmpty)
                #expect(index.batches.isEmpty)
                #expect(index.samples.isEmpty)
            }
        }
    }

    @Test("note with no batch-shaped filename token is unresolved at the batch level")
    func unresolvedBatchIdentity() throws {
        try withBundledRules { provider in
            try withVaultFixture([
                "untitled.md": """
                ---
                date: 2026-08-01
                material: SRO
                substrate:
                  - STO 001
                ---
                """
            ]) { root in
                let index = ObsidianVaultParser.parseVault(at: root, ruleProvider: provider)
                #expect(index.batches.isEmpty)
                #expect(index.samples.isEmpty)
                #expect(index.diagnostics.contains { $0.kind == .unresolvedBatchIdentity })
            }
        }
    }

    @Test("processing/treatment 'b' evidence in the substrate segment yields a distinct canonical key from 'o'")
    func processingTokenBYieldsDistinctKeyFromO() throws {
        try withBundledRules { provider in
            try withVaultFixture([
                "pn67.md": """
                ---
                date: 2026-08-01
                material: SRO
                substrate: b STO 111
                ---
                """
            ]) { root in
                let index = ObsidianVaultParser.parseVault(at: root, ruleProvider: provider)
                let expected = SampleSemanticDescriptor.withPrevalidatedTokens(
                    batch: "PN67", processingTokens: ["b"], material: "STO", orientation: "111"
                ).canonicalKey
                #expect(index.samples.first?.sampleKey == expected)
            }
        }
    }

    @Test("processing/treatment 'o' evidence yields a different canonical key from 'b' for the same batch+substrate")
    func processingTokenOYieldsDistinctKeyFromB() throws {
        try withBundledRules { provider in
            let keyB = try withVaultFixture([
                "pn67.md": """
                ---
                date: 2026-08-01
                material: SRO
                substrate: b STO 111
                ---
                """
            ]) { root in
                ObsidianVaultParser.parseVault(at: root, ruleProvider: provider).samples.first?.sampleKey
            }
            let keyO = try withVaultFixture([
                "pn67.md": """
                ---
                date: 2026-08-01
                material: SRO
                substrate: o STO 111
                ---
                """
            ]) { root in
                ObsidianVaultParser.parseVault(at: root, ruleProvider: provider).samples.first?.sampleKey
            }
            #expect(keyB != nil)
            #expect(keyO != nil)
            #expect(keyB != keyO)
        }
    }

    @Test("core and note claims coexist without being collapsed into one field, each keeping its own rawKey")
    func coreAndNoteCoexistWithDistinctRawKeys() throws {
        try withBundledRules { provider in
            try withVaultFixture([
                "nno7.md": """
                ---
                date: 2026-08-01
                material: NNO
                substrate:
                  - STO 001
                core: 开始摸nno
                note: 长着长着分子泵不对劲了
                ---
                """
            ]) { root in
                let index = ObsidianVaultParser.parseVault(at: root, ruleProvider: provider)
                let note = try #require(index.notes.first)
                #expect(note.sampleObservations.count == 2)
                let rawKeys = Set(note.sampleObservations.map { $0.provenance.rawKey })
                #expect(rawKeys == Set(["core", "note"]))
                #expect(note.sampleObservations.first { $0.provenance.rawKey == "core" }?.value == "开始摸nno")
                #expect(note.sampleObservations.first { $0.provenance.rawKey == "note" }?.value == "长着长着分子泵不对劲了")
            }
        }
    }
}
