import Testing
import Foundation
@testable import SpinLabApp

@Suite("V5.1.4 RegistryFeatureStore")
struct V514RegistryFeatureStoreTests {

    @Test("initial state has nil registry and empty prefix entries")
    func initialState() {
        let store = RegistryFeatureStore()
        #expect(store.registryFileName == nil)
        #expect(store.registrySourceFilePath == nil)
        #expect(store.registryPrefixEntries.isEmpty)
    }

    @Test("applyPresentation populates all fields from presentation state")
    func applyPresentation() {
        var store = RegistryFeatureStore()
        let entries = [
            RegistryPrefixEntry(prefix: "STO", sheetName: "STO sheet"),
            RegistryPrefixEntry(prefix: "FMR", sheetName: "FMR sheet"),
        ]
        let presentation = RegistryPresentationState(
            registrySourceFilePath: "/path/to/registry.xlsx",
            registryFileName: "registry.xlsx",
            registryPrefixEntries: entries
        )
        store.applyPresentation(presentation)
        #expect(store.registryFileName == "registry.xlsx")
        #expect(store.registrySourceFilePath == "/path/to/registry.xlsx")
        #expect(store.registryPrefixEntries.count == 2)
        #expect(store.registryPrefixEntries[0].prefix == "STO")
        #expect(store.registryPrefixEntries[1].prefix == "FMR")
    }

    @Test("applyPresentation with nil source path clears previous values")
    func applyPresentation_nilSource() {
        var store = RegistryFeatureStore()
        let initial = RegistryPresentationState(
            registrySourceFilePath: "/old/path.xlsx",
            registryFileName: "old.xlsx",
            registryPrefixEntries: [RegistryPrefixEntry(prefix: "X", sheetName: "X")]
        )
        store.applyPresentation(initial)
        #expect(store.registryFileName == "old.xlsx")

        let cleared = RegistryPresentationState(
            registrySourceFilePath: nil,
            registryFileName: nil,
            registryPrefixEntries: []
        )
        store.applyPresentation(cleared)
        #expect(store.registryFileName == nil)
        #expect(store.registrySourceFilePath == nil)
        #expect(store.registryPrefixEntries.isEmpty)
    }
}
