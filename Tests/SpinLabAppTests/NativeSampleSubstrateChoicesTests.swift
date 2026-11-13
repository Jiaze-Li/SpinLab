import Foundation
import Testing
@testable import SpinLabApp

@Suite("Native Sample Substrate Choices")
struct NativeSampleSubstrateChoicesTests {
    private func entry(_ name: String) -> FilenameRuleSet.CompiledSubstrateEntry {
        .init(displayName: name, equalsKeysNormalized: [], containsNeedlesNormalized: [])
    }

    private func choices() -> NativeSampleSubstrateChoices {
        var compiled = FilenameRuleSet.CompiledRules()
        compiled.substrateMaterialEntries = [entry("STO"), entry("MgO"), entry("MGO"), entry("MAO"), entry("STO")]
        compiled.substrateOrientationEntries = [entry("001"), entry("110"), entry("111")]
        compiled.substrateTreatmentEntries = [entry("HF"), entry("b"), entry("o")]
        compiled.originTreatmentDisplayNames = ["o"]
        return NativeSampleSubstrateChoices(compiled: compiled)
    }

    @Test("Lists keep the rule spelling, keep MgO and MGO distinct, and drop exact duplicates")
    func listsAreCaseExactAndUnique() {
        let c = choices()
        #expect(c.materials == ["STO", "MgO", "MGO", "MAO"])
        #expect(c.orientations == ["001", "110", "111"])
        #expect(c.treatments == ["HF", "b", "o"])
    }

    @Test("No treatment chosen means the original / untreated entry")
    func defaultTreatmentIsOrigin() {
        let c = choices()
        #expect(c.defaultTreatment == "o")
        #expect(c.composeDescription(material: "STO", orientation: "001", treatment: "") == "o STO(001)")
        #expect(c.composeDescription(material: "MgO", orientation: "110", treatment: "HF") == "HF MgO(110)")
    }

    @Test("Material and orientation are both required; typed values are trimmed")
    func requiresMaterialAndOrientation() {
        let c = choices()
        #expect(c.composeDescription(material: "", orientation: "001", treatment: "") == nil)
        #expect(c.composeDescription(material: "STO", orientation: "  ", treatment: "") == nil)
        #expect(c.composeDescription(material: " LAO ", orientation: " 110 ", treatment: " b ") == "b LAO(110)")
    }

    @Test("A composed description flows into the created sample and its default display name")
    func composedDescriptionRoundTripsThroughCreation() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "spinlab-substrate-choices-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)

        let description = try #require(choices().composeDescription(material: "STO", orientation: "001", treatment: ""))
        let draft = CreateNativeSampleDraft(batchId: "PN1", substrateDescription: description)
        guard case let .success(sample, _, _) = NativeSampleCreationService().createSample(
            draft: draft, rootURL: root, libraryStore: store, settings: .default
        ) else {
            Issue.record("Creation should succeed")
            return
        }
        #expect(sample.substrateRaw == description)
        #expect(sample.displayName == "PN1 - o STO(001)")
    }
}
