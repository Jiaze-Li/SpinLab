import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.2.1 Drawer Match Engine")
struct V221DrawerMatchEngineTests {
    @Test("shared semantic descriptor canonicalizes fields consistently")
    func sharedSemanticDescriptorCanonicalizesConsistently() {
        let bundledDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SpinLabApp/config")
        let savedPaths = RuleLoader.currentBookPaths
        RuleLoader.configure(bookPaths: RulesConfigPaths(configDirectoryURL: bundledDir), internalPaths: AppInternalPaths())
        defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }

        let descriptor = SampleSemanticDescriptor(
            batch: "pn32",
            processingTokens: ["BAKED", "o", "HF"],
            material: "sto",
            orientation: "111"
        )
        // v4 substrate schema: "BAKED" canonicalizes to short code "b"
        #expect(descriptor.canonicalKey == "PN32|HF+b+o|STO|111")
    }

    @Test("exact canonical key match resolves uniquely")
    func exactCanonicalMatchResolvesUniquely() {
        let engine = DrawerMatchEngine()
        let index = engine.makeIndex(from: [
            sample(batch: "PN32", treatment: "HF", material: "STO", orientation: "111", display: "PN32 - HF STO(111)"),
            sample(batch: "PN32", treatment: "b", material: "STO", orientation: "111", display: "PN32 - b STO(111)")
        ])

        let matched = engine.match(sampleInput: "PN32|b|STO|111", index: index)

        #expect(matched == "PN32|b|STO|111")
    }

    @Test("fallback token subset match resolves uniquely")
    func fallbackTokenSubsetMatchResolvesUniquely() {
        let engine = DrawerMatchEngine()
        let index = engine.makeIndex(from: [
            sample(batch: "PN32", treatment: "HF", material: "STO", orientation: "111", display: "PN32 - HF STO(111)"),
            sample(batch: "PN32", treatment: "b", material: "STO", orientation: "111", display: "PN32 - b STO(111)")
        ])

        let matched = engine.match(sampleInput: "PN32 b STO", index: index)

        #expect(matched == "PN32|b|STO|111")
    }

    @Test("fallback token subset returns nil when candidates are ambiguous")
    func fallbackTokenSubsetReturnsNilWhenAmbiguous() {
        let engine = DrawerMatchEngine()
        let index = engine.makeIndex(from: [
            sample(batch: "PN32", treatment: "HF", material: "STO", orientation: "111", display: "PN32 - HF STO(111)"),
            sample(batch: "PN32", treatment: "b", material: "STO", orientation: "111", display: "PN32 - b STO(111)")
        ])

        let matched = engine.match(sampleInput: "PN32 STO", index: index)

        #expect(matched == nil)
    }

    @Test("exact canonical match is preferred before ambiguous fallback")
    func exactMatchIsPreferredBeforeAmbiguousFallback() {
        let engine = DrawerMatchEngine()
        let index = engine.makeIndex(from: [
            sample(batch: "PN32", treatment: "HF", material: "STO", orientation: "111", display: "PN32 - HF STO(111)"),
            sample(batch: "PN32", treatment: "b", material: "STO", orientation: "111", display: "PN32 - b STO(111)")
        ])

        let matched = engine.match(sampleInput: "PN32 | b | STO | 111", index: index)

        #expect(matched == "PN32|b|STO|111")
    }

    @Test("legacy non-canonical sample ids can still be resolved through fallback")
    func legacyNonCanonicalSampleIDsCanStillResolveViaFallback() {
        let engine = DrawerMatchEngine()
        let index = engine.makeIndex(from: [
            LibrarySample(
                id: "legacy-pn50-hf-sto111",
                displayName: "PN50 - HF STO(111)",
                batchId: "PN50",
                substrateRaw: "HF STO(111)",
                substrateDisplay: "HF STO(111)",
                substrateTokens: ["HF", "STO", "111"],
                substrateTags: ["HF STO(111)"],
                metadata: [:],
                numericTags: [:],
                numericDisplay: [:],
                updatedAt: .now
            )
        ])

        let matched = engine.match(sampleInput: "PN50 HF STO", index: index)

        #expect(matched == "legacy-pn50-hf-sto111")
    }

    @Test("legacy display-style sample ids can be resolved by canonical sample input")
    func legacyDisplayStyleSampleIDResolvesFromCanonicalInput() {
        let engine = DrawerMatchEngine()
        let index = engine.makeIndex(from: [
            LibrarySample(
                id: "PN50 - HF STO(111)",
                displayName: "PN50 - HF STO(111)",
                batchId: "PN50",
                substrateRaw: "HF STO(111)",
                substrateDisplay: "HF STO(111)",
                substrateTokens: ["HF", "STO", "111"],
                substrateTags: ["HF STO(111)"],
                metadata: [:],
                numericTags: [:],
                numericDisplay: [:],
                updatedAt: .now
            )
        ])

        let matched = engine.match(sampleInput: "PN50|HF|STO|111", index: index)

        #expect(matched == "PN50 - HF STO(111)")
    }

    @Test("explicit Library batchId outranks a misleading inferred batch on a legacy sample id")
    func explicitBatchIDOutranksMisleadingInferredBatch() {
        let bundledDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SpinLabApp/config")
        let savedPaths = RuleLoader.currentBookPaths
        RuleLoader.configure(bookPaths: RulesConfigPaths(configDirectoryURL: bundledDir), internalPaths: AppInternalPaths())
        defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }

        let engine = DrawerMatchEngine()
        // "legacy-pn50-hf-sto111" semantically parses to an inferred batch of
        // "LEGACY" (the text before the first hyphen) even though the sample's
        // real batch, from explicit Library metadata, is "PN50". The candidate's
        // batch-conflict check must not reject the true PN50 match because of
        // that misleading inferred token.
        let index = engine.makeIndex(from: [
            LibrarySample(
                id: "legacy-pn50-hf-sto111",
                displayName: "PN50 - HF STO(111)",
                batchId: "PN50",
                substrateRaw: "HF STO(111)",
                substrateDisplay: "HF STO(111)",
                substrateTokens: ["HF", "STO", "111"],
                substrateTags: ["HF STO(111)"],
                metadata: [:],
                numericTags: [:],
                numericDisplay: [:],
                updatedAt: .now
            )
        ])

        let matched = engine.match(sampleInput: "PN50 HF STO 111", index: index)

        #expect(matched == "legacy-pn50-hf-sto111")
    }

    @Test("empty sample input returns nil immediately")
    func emptyInputReturnsNil() {
        let engine = DrawerMatchEngine()
        let index = engine.makeIndex(from: [
            sample(batch: "PN32", treatment: "HF", material: "STO", orientation: "111", display: "PN32 - HF STO(111)")
        ])

        #expect(engine.match(sampleInput: "   ", index: index) == nil)
    }

    @Test("exact canonical key returns nil when canonical candidates are not unique")
    func exactCanonicalReturnsNilWhenDuplicateCanonicalCandidatesExist() {
        let engine = DrawerMatchEngine()
        let index = engine.makeIndex(from: [
            sample(batch: "PN32", treatment: "HF", material: "STO", orientation: "111", display: "PN32 - HF STO(111) A"),
            sample(batch: "PN32", treatment: "HF", material: "STO", orientation: "111", display: "PN32 - HF STO(111) B")
        ])

        let matched = engine.match(sampleInput: "PN32|HF|STO|111", index: index)
        #expect(matched == nil)
    }

    @Test("batch number matching an orientation value no longer causes a false ambiguous match")
    func batchNumberCollidingWithOrientationResolvesUniquely() {
        let bundledDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SpinLabApp/config")
        let savedPaths = RuleLoader.currentBookPaths
        RuleLoader.configure(bookPaths: RulesConfigPaths(configDirectoryURL: bundledDir), internalPaths: AppInternalPaths())
        defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }

        let engine = DrawerMatchEngine()
        let index = engine.makeIndex(from: [
            sample(batch: "PN110/SRO5", treatment: "o", material: "STO", orientation: "001", display: "PN110/SRO5 - o STO(001)"),
            sample(batch: "PN110/SRO5", treatment: "o", material: "STO", orientation: "110", display: "PN110/SRO5 - o STO(110)")
        ])

        // "PN110" is itself a valid subset match for BOTH candidates (its embedded
        // "110" used to satisfy the STO(110) orientation requirement even when the
        // measurement filename never mentions "SRO5"). Only the candidate whose
        // orientation is genuinely "110" should resolve.
        let matched = engine.match(sampleInput: "PN110 110", index: index)

        #expect(matched == "PN110/SRO5|o|STO|110")
    }

    @Test("batch number matching an orientation value still returns nil without a disambiguating digit")
    func batchNumberCollidingWithOrientationStillAmbiguousWithoutOrientationDigit() {
        let engine = DrawerMatchEngine()
        let index = engine.makeIndex(from: [
            sample(batch: "PN110/SRO5", treatment: "o", material: "STO", orientation: "001", display: "PN110/SRO5 - o STO(001)"),
            sample(batch: "PN110/SRO5", treatment: "o", material: "STO", orientation: "110", display: "PN110/SRO5 - o STO(110)")
        ])

        let matched = engine.match(sampleInput: "PN110", index: index)

        #expect(matched == nil)
    }

    private func sample(
        batch: String,
        treatment: String,
        material: String,
        orientation: String,
        display: String
    ) -> LibrarySample {
        LibrarySample(
            id: "\(batch)|\(treatment)|\(material)|\(orientation)",
            displayName: display,
            batchId: batch,
            substrateRaw: "\(treatment) \(material)(\(orientation))",
            substrateDisplay: "\(treatment) \(material)(\(orientation))",
            substrateTokens: [treatment, material, orientation].filter { !$0.isEmpty && $0 != "UNKNOWN" },
            substrateTags: ["\(treatment) \(material)(\(orientation))"],
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            updatedAt: .now
        )
    }
}
