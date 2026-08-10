import Testing
import Foundation
@testable import SpinLabApp

// MARK: - Fakes

private final class FakeReader: @unchecked Sendable, LibrarySidecarReaderCapability {
    private(set) var loadAtPathCallCount = 0
    private(set) var loadAtURLCallCount = 0
    var stubbedSidecar: SpinLabFileSidecar?
    var stubbedError: SidecarReadError = .other("no stub configured")

    private var stubbedResult: Result<SpinLabFileSidecar, SidecarReadError> {
        stubbedSidecar.map(Result.success) ?? .failure(stubbedError)
    }

    func loadSidecar(atPath path: String) -> Result<SpinLabFileSidecar, SidecarReadError> {
        loadAtPathCallCount += 1
        return stubbedResult
    }

    func loadSidecar(at url: URL) -> Result<SpinLabFileSidecar, SidecarReadError> {
        loadAtURLCallCount += 1
        return stubbedResult
    }
}

private final class FakeWriter: @unchecked Sendable, LibrarySidecarWriterCapability {
    private(set) var saveSidecarCallCount = 0
    var stubbedResult = true

    @discardableResult
    func saveSidecar(_ sidecar: SpinLabFileSidecar, at url: URL) -> Bool {
        saveSidecarCallCount += 1
        return stubbedResult
    }
}

// MARK: - Fixture

private func makeSidecar() -> SpinLabFileSidecar {
    SpinLabFileSidecar(
        workflow: "General",
        workflowDisplayName: "General",
        channels: [],
        sourceFilePath: "/tmp/test.dat",
        appliedAt: Date(timeIntervalSince1970: 0),
        ruleSnapshot: SidecarRuleSnapshot(
            ruleSetVersion: 1,
            ruleSetFingerprint: "abc",
            appliedAt: Date(timeIntervalSince1970: 0),
            fields: SidecarRuleFields(sampleID: nil, conditions: [:], substrateTags: [])
        )
    )
}

// MARK: - Tests

@Suite("V5.1.14 LibrarySidecarService Reader/Writer Split (INV-10)")
struct V5114SidecarServiceSplitTests {

    @Test("INV-10a: loadSidecar(atPath:) routes through injected reader")
    func loadSidecarRoutesToReader() {
        let fakeReader = FakeReader()
        let fakeWriter = FakeWriter()
        let service = LibrarySidecarService(libraryStore: LibraryStore(), reader: fakeReader, writer: fakeWriter)
        _ = service.loadSidecar(atPath: "/tmp/test.spinlab.json")
        #expect(fakeReader.loadAtPathCallCount == 1, "reader must receive the loadSidecar(atPath:) call")
    }

    @Test("INV-10b: saveConditionOverride reads via reader and writes via writer")
    func saveConditionOverrideUsesReaderAndWriter() {
        let fakeReader = FakeReader()
        let fakeWriter = FakeWriter()
        fakeReader.stubbedSidecar = makeSidecar()
        let service = LibrarySidecarService(libraryStore: LibraryStore(), reader: fakeReader, writer: fakeWriter)
        _ = service.saveConditionOverride(sidecarPath: "/tmp/test.spinlab.json", conditionId: "temperature", value: "300K")
        #expect(fakeReader.loadAtURLCallCount == 1, "reader must be consulted before write")
        #expect(fakeWriter.saveSidecarCallCount == 1, "writer must receive the save call")
    }

    @Test("INV-10c: removeConditionOverride reads via reader and writes via writer")
    func removeConditionOverrideUsesReaderAndWriter() {
        let fakeReader = FakeReader()
        let fakeWriter = FakeWriter()
        var sidecar = makeSidecar()
        sidecar.userOverrides.conditions["temperature"] = ManualValueOverride(value: "300K", reason: "manual", at: Date())
        fakeReader.stubbedSidecar = sidecar
        let service = LibrarySidecarService(libraryStore: LibraryStore(), reader: fakeReader, writer: fakeWriter)
        _ = service.removeConditionOverride(sidecarPath: "/tmp/test.spinlab.json", conditionId: "temperature")
        #expect(fakeReader.loadAtURLCallCount == 1, "reader must be consulted before write")
        #expect(fakeWriter.saveSidecarCallCount == 1, "writer must receive the save call")
    }

    @Test("INV-10d: when reader returns nil, writer is never called")
    func nilReaderPreventsWrite() {
        let fakeReader = FakeReader()
        let fakeWriter = FakeWriter()
        // stubbedSidecar remains nil
        let service = LibrarySidecarService(libraryStore: LibraryStore(), reader: fakeReader, writer: fakeWriter)
        _ = service.saveConditionOverride(sidecarPath: "/tmp/missing.spinlab.json", conditionId: "temperature", value: "300K")
        #expect(fakeReader.loadAtURLCallCount == 1, "reader must still be consulted")
        #expect(fakeWriter.saveSidecarCallCount == 0, "writer must not be called when sidecar load fails")
    }
}
