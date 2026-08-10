import Testing
import Foundation
@testable import SpinLabApp

// 5.4.2: LibrarySidecarReader distinguishes why a sidecar failed to load
// instead of collapsing every failure into a bare nil.

@Suite("V5.4.2 Typed Sidecar Read Result")
struct V542TypedSidecarReadResultTests {

    private func tempSidecarURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("v542-sidecar-\(UUID().uuidString).spinlab.json")
    }

    @Test("A valid sidecar decodes to .success")
    func validSidecarSucceeds() throws {
        let reader = LibrarySidecarReader()
        let sidecar = SpinLabFileSidecar(
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let url = tempSidecarURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try encoder.encode(sidecar).write(to: url)

        let result = reader.loadSidecar(at: url)
        guard case .success(let loaded) = result else {
            Issue.record("expected .success, got \(result)")
            return
        }
        #expect(loaded.workflow == "General")
    }

    @Test("Malformed JSON syntax maps to .corrupted")
    func malformedJSONMapsToCorrupted() throws {
        let reader = LibrarySidecarReader()
        let url = tempSidecarURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not-valid-json!!!".utf8).write(to: url)

        #expect(reader.loadSidecar(at: url) == .failure(.corrupted))
    }

    @Test("Well-formed JSON missing required fields maps to .schemaMismatch")
    func missingFieldsMapToSchemaMismatch() throws {
        let reader = LibrarySidecarReader()
        let url = tempSidecarURL()
        defer { try? FileManager.default.removeItem(at: url) }
        // version 2 declares ruleSnapshot as required; omitting it (unlike the
        // fully-lenient legacy v1 shape) triggers a genuine schema mismatch.
        try Data("{\"version\": 2}".utf8).write(to: url)

        #expect(reader.loadSidecar(at: url) == .failure(.schemaMismatch))
    }

    @Test("A missing file maps to .other, distinct from decode failures")
    func missingFileMapsToOther() {
        let reader = LibrarySidecarReader()
        let url = tempSidecarURL() // never written

        let result = reader.loadSidecar(at: url)
        guard case .failure(.other) = result else {
            Issue.record("expected .failure(.other(_)), got \(result)")
            return
        }
    }
}
