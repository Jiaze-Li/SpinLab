import Foundation
import Testing
@testable import SpinLabApp

// MARK: - v4.1.5 — MeasurementSet model + persistence tests

@Suite("MeasurementSet model")
struct MeasurementSetModelTests {

    @Test("round-trip encode/decode preserves all fields")
    func roundTrip() throws {
        let original = MeasurementSet(
            id: "set-001",
            name: "Temperature Sweep",
            workflow: "ahe",
            memberFileNames: ["file_5K.xlsx", "file_10K.xlsx"],
            createdAt: Date(timeIntervalSinceReferenceDate: 700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MeasurementSet.self, from: data)
        #expect(decoded == original)
    }

    @Test("empty memberFileNames round-trips correctly")
    func emptyMembers() throws {
        let original = MeasurementSet(
            id: "set-002",
            name: "Empty Set",
            workflow: "3w",
            memberFileNames: [],
            createdAt: Date(timeIntervalSinceReferenceDate: 700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MeasurementSet.self, from: data)
        #expect(decoded == original)
        #expect(decoded.memberFileNames.isEmpty)
    }

    @Test("Hashable conformance: sets with same id are equal")
    func hashableEquality() {
        let a = MeasurementSet(id: "x", name: "A", workflow: "ahe", memberFileNames: ["f1"], createdAt: .distantPast)
        let b = MeasurementSet(id: "x", name: "A", workflow: "ahe", memberFileNames: ["f1"], createdAt: .distantPast)
        #expect(a == b)
    }
}

@Suite("MeasurementSet persistence via LibraryStore")
struct MeasurementSetPersistenceTests {

    private func makeTempSampleDir() throws -> (rootURL: URL, sample: LibrarySample) {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "spinlab_test_\(UUID().uuidString)", directoryHint: .isDirectory)
        let sampleDir = tmp
            .appending(path: "Batches/PN001/samples/S1", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sampleDir, withIntermediateDirectories: true)
        // LibraryStore expects Batches/{batchId}/samples/{sampleKey}/
        let sample = LibrarySample(
            id: "S1",
            displayName: "S1",
            batchId: "PN001",
            substrateRaw: "",
            substrateDisplay: "",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            updatedAt: .now
        )
        return (rootURL: tmp, sample: sample)
    }

    @Test("save and load round-trips measurement sets")
    func saveAndLoad() throws {
        let (rootURL, sample) = try makeTempSampleDir()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = LibraryStore()
        let sets = [
            MeasurementSet(id: "s1", name: "Sweep A", workflow: "ahe", memberFileNames: ["f1.xlsx", "f2.xlsx"], createdAt: .now),
            MeasurementSet(id: "s2", name: "Sweep B", workflow: "3w", memberFileNames: [], createdAt: .now),
        ]

        try store.saveMeasurementSets(sets, for: sample, rootURL: rootURL)
        let loaded = store.loadMeasurementSets(for: sample, rootURL: rootURL)

        #expect(loaded.count == 2)
        #expect(loaded[0].id == "s1")
        #expect(loaded[0].name == "Sweep A")
        #expect(loaded[0].memberFileNames == ["f1.xlsx", "f2.xlsx"])
        #expect(loaded[1].id == "s2")
        #expect(loaded[1].memberFileNames.isEmpty)
    }

    @Test("load returns empty array when no file exists")
    func loadMissing() throws {
        let (rootURL, sample) = try makeTempSampleDir()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = LibraryStore()
        let loaded = store.loadMeasurementSets(for: sample, rootURL: rootURL)
        #expect(loaded.isEmpty)
    }

    @Test("saving empty array removes the file")
    func saveEmptyRemovesFile() throws {
        let (rootURL, sample) = try makeTempSampleDir()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = LibraryStore()
        let sets = [MeasurementSet(id: "s1", name: "X", workflow: "ahe", memberFileNames: [], createdAt: .now)]
        try store.saveMeasurementSets(sets, for: sample, rootURL: rootURL)

        // Verify file exists
        let loaded1 = store.loadMeasurementSets(for: sample, rootURL: rootURL)
        #expect(loaded1.count == 1)

        // Save empty → file removed
        try store.saveMeasurementSets([], for: sample, rootURL: rootURL)
        let loaded2 = store.loadMeasurementSets(for: sample, rootURL: rootURL)
        #expect(loaded2.isEmpty)
    }
}
