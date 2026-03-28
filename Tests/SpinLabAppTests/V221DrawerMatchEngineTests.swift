import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.2.1 Drawer Match Engine")
struct V221DrawerMatchEngineTests {
    @Test("shared semantic descriptor canonicalizes fields consistently")
    func sharedSemanticDescriptorCanonicalizesConsistently() {
        let descriptor = SampleSemanticDescriptor(
            batch: "pn32",
            processingTokens: ["BAKED", "o", "HF"],
            material: "sto",
            orientation: "111"
        )

        #expect(descriptor.canonicalKey == "PN32|HF+b+o|STO|111")
    }

    @Test("exact canonical key match resolves uniquely")
    func exactCanonicalMatchResolvesUniquely() {
        let engine = DrawerMatchEngine()
        let index = engine.makeIndex(from: [
            sample(batch: "PN32", treatment: "HF", material: "STO", orientation: "111", display: "PN32 - HF STO(111)"),
            sample(batch: "PN32", treatment: "b", material: "STO", orientation: "111", display: "PN32 - b STO(111)")
        ])

        let matched = engine.match(sampleInput: "PN32|baked|STO|111", index: index)

        #expect(matched == "PN32 - b STO(111)")
    }

    @Test("fallback token subset match resolves uniquely")
    func fallbackTokenSubsetMatchResolvesUniquely() {
        let engine = DrawerMatchEngine()
        let index = engine.makeIndex(from: [
            sample(batch: "PN32", treatment: "HF", material: "STO", orientation: "111", display: "PN32 - HF STO(111)"),
            sample(batch: "PN32", treatment: "b", material: "STO", orientation: "111", display: "PN32 - b STO(111)")
        ])

        let matched = engine.match(sampleInput: "PN32 baked STO", index: index)

        #expect(matched == "PN32 - b STO(111)")
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

        let matched = engine.match(sampleInput: "PN32 | baked | STO | 111", index: index)

        #expect(matched == "PN32 - b STO(111)")
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

        #expect(matched == "PN50 - HF STO(111)")
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
