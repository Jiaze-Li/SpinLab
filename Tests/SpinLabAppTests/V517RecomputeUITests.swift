import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.1.7 Recompute UI — stale count + diff + override write")
struct V517RecomputeUITests {

    // MARK: - Stale count

    @Test("staleCount counts sidecars whose fingerprint differs from current")
    func staleCountCountsMismatch() throws {
        let dir = makeTempDir(suffix: "stale")
        defer { cleanup(dir) }

        writeSidecar(fingerprint: "v4:aaa", to: dir.appending(path: "a.csv.spinlab.json"))
        writeSidecar(fingerprint: "v4:bbb", to: dir.appending(path: "b.csv.spinlab.json"))
        writeSidecar(fingerprint: "v4:aaa", to: dir.appending(path: "c.csv.spinlab.json"))

        let svc = LibrarySidecarService(libraryStore: LibraryStore())
        let count = svc.computeStaleCount(rootURL: dir, currentFingerprint: "v4:aaa")
        #expect(count == 1)
    }

    @Test("staleCount returns 0 when all fingerprints match")
    func staleCountZeroWhenAllMatch() throws {
        let dir = makeTempDir(suffix: "stale0")
        defer { cleanup(dir) }

        writeSidecar(fingerprint: "v4:aaa", to: dir.appending(path: "a.csv.spinlab.json"))
        writeSidecar(fingerprint: "v4:aaa", to: dir.appending(path: "b.csv.spinlab.json"))

        let svc = LibrarySidecarService(libraryStore: LibraryStore())
        #expect(svc.computeStaleCount(rootURL: dir, currentFingerprint: "v4:aaa") == 0)
    }

    // MARK: - Condition override write-back

    @Test("saveConditionOverride writes userOverrides to sidecar file")
    func saveConditionOverride() throws {
        let dir = makeTempDir(suffix: "override")
        defer { cleanup(dir) }

        let sidecarURL = dir.appending(path: "test.csv.spinlab.json")
        writeSidecar(fingerprint: "v4:xxx", conditions: ["temperature": ("300K", "rule:condition.temperature.unitSuffix#0")], to: sidecarURL)

        let svc = LibrarySidecarService(libraryStore: LibraryStore())
        let ok = svc.saveConditionOverride(sidecarPath: sidecarURL.path, conditionId: "temperature", value: "295K")
        #expect(ok)

        let reloaded = try loadSidecar(at: sidecarURL)
        #expect(reloaded.userOverrides.conditions["temperature"]?.value == "295K")
        #expect(reloaded.userOverrides.conditions["temperature"]?.reason == "manual")
        // rule snapshot untouched
        #expect(reloaded.ruleSnapshot.fields.conditions["temperature"]?.value == "300K")
    }

    @Test("saveConditionOverride deletes override when value matches rule snapshot")
    func saveConditionOverrideNoopWhenMatchesRule() throws {
        let dir = makeTempDir(suffix: "noop")
        defer { cleanup(dir) }

        let sidecarURL = dir.appending(path: "test.csv.spinlab.json")
        var sidecar = makeSidecar(fingerprint: "v4:xxx")
        sidecar.ruleSnapshot.fields.conditions["temperature"] = SourcedValue(value: "300K", source: "rule:condition.temperature.unitSuffix#0")
        sidecar.userOverrides.conditions["temperature"] = ManualValueOverride(value: "295K", reason: "manual", at: .now)
        writeSidecarDirect(sidecar, to: sidecarURL)

        let svc = LibrarySidecarService(libraryStore: LibraryStore())
        // Set value back to rule value → override should be removed
        _ = svc.saveConditionOverride(sidecarPath: sidecarURL.path, conditionId: "temperature", value: "300K")

        let reloaded = try loadSidecar(at: sidecarURL)
        #expect(reloaded.userOverrides.conditions["temperature"] == nil)
    }

    @Test("removeConditionOverride deletes the override entry")
    func removeConditionOverride() throws {
        let dir = makeTempDir(suffix: "remove")
        defer { cleanup(dir) }

        let sidecarURL = dir.appending(path: "test.csv.spinlab.json")
        var sidecar = makeSidecar(fingerprint: "v4:xxx")
        sidecar.userOverrides.conditions["voltage"] = ManualValueOverride(value: "5kV", reason: "manual", at: .now)
        writeSidecarDirect(sidecar, to: sidecarURL)

        let svc = LibrarySidecarService(libraryStore: LibraryStore())
        _ = svc.removeConditionOverride(sidecarPath: sidecarURL.path, conditionId: "voltage")

        let reloaded = try loadSidecar(at: sidecarURL)
        #expect(reloaded.userOverrides.conditions["voltage"] == nil)
    }

    // MARK: - Diff status grouping

    @Test("RecomputeDiffStatus groupIndex assigns correct groups")
    func diffStatusGroupIndex() {
        #expect(RecomputeDiffStatus.willUpdate.groupIndex == 0)
        #expect(RecomputeDiffStatus.migration.groupIndex == 0)
        #expect(RecomputeDiffStatus.added.groupIndex == 0)
        #expect(RecomputeDiffStatus.ruleRemoved.groupIndex == 0)
        #expect(RecomputeDiffStatus.manualOverride.groupIndex == 1)
        #expect(RecomputeDiffStatus.noChange.groupIndex == 2)
    }

    // MARK: - Fixture helpers

    private func makeTempDir(suffix: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "spinlab-v517-\(suffix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func makeSidecar(fingerprint: String) -> SpinLabFileSidecar {
        SpinLabFileSidecar(
            workflow: "ahe",
            workflowDisplayName: "AHE",
            channels: [],
            sourceFilePath: "/tmp/test.csv",
            appliedAt: .now,
            ruleSnapshot: SidecarRuleSnapshot(
                ruleSetVersion: 1,
                ruleSetFingerprint: fingerprint,
                appliedAt: .now,
                fields: SidecarRuleFields(sampleID: nil, conditions: [:], substrateTags: [])
            )
        )
    }

    private func writeSidecar(
        fingerprint: String,
        conditions: [String: (value: String, source: String)] = [:],
        to url: URL
    ) {
        var sidecar = makeSidecar(fingerprint: fingerprint)
        sidecar.ruleSnapshot.fields.conditions = conditions.reduce(into: [:]) { acc, pair in
            acc[pair.key] = SourcedValue(value: pair.value.value, source: pair.value.source)
        }
        writeSidecarDirect(sidecar, to: url)
    }

    private func writeSidecarDirect(_ sidecar: SpinLabFileSidecar, to url: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(sidecar) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadSidecar(at url: URL) throws -> SpinLabFileSidecar {
        let data = try Data(contentsOf: url)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(SpinLabFileSidecar.self, from: data)
    }
}
