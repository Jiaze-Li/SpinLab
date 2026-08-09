import Foundation
import Testing
@testable import SpinLabApp

// TestRecord architecture Phase 2: Search becomes a pure TestRecord index.
// Covers regression cases A–F from the Phase 2 implementation spec.
//
// G ("existing search behavior remains unchanged": prefix search, condition
// filtering, aliases, folder exclusion) is intentionally NOT duplicated here —
// it is already covered by the pre-existing, unmodified suites this phase's
// verification pass re-ran: V320WorkflowSearchAcrossDrawersTests,
// SearchExcludeFolderPathTokensTests, V425NumericSearchTests,
// V5114SearchUseCaseCapabilityInjectionTests, V730SecondaryInputSearch*Tests.
// All of those fixtures write legacy sidecars (sampleKey == nil), so their
// continued passing is itself proof the legacy fallback path is unchanged.

@Suite("TestRecord Phase 2 — Search sidecar ownership")
struct TestRecordPhase2SearchOwnershipTests {

    // MARK: - A: new sidecar with sampleKey → Hit.sampleKey == sidecar.sampleKey

    @Test("Hit.sampleKey equals sidecar.sampleKey when present")
    func hitSampleKeyMatchesSidecarSampleKey() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        try fixture.writeSidecar(
            batchID: "PN90",
            folderSampleKey: "PN90|b|STO|111",
            sidecarSampleKey: "PN90|b|STO|111",
            workflowFolder: "ahe",
            measurementFileName: "AHE_PN90.dat",
            workflow: "ahe"
        )

        let hits = try SearchWorkflowMeasurementsUseCase().execute(
            query: WorkflowSearchQuery(rawText: "PN90"),
            libraryRootURL: fixture.rootURL
        )

        #expect(hits.count == 1)
        #expect(hits[0].sampleKey == "PN90|b|STO|111")
    }

    // MARK: - B: sidecar.sampleKey wins even if the filesystem path suggests a different sample

    @Test("sidecar.sampleKey wins over a mismatched filesystem path")
    func sidecarSampleKeyWinsOverMismatchedPath() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        // Folder name deliberately differs from sidecar.sampleKey — simulates a
        // manually-moved file or a stale directory name. Search must trust the sidecar.
        try fixture.writeSidecar(
            batchID: "PN91",
            folderSampleKey: "PN91|WRONG|STO|999",
            sidecarSampleKey: "PN91|b|STO|111",
            workflowFolder: "ahe",
            measurementFileName: "AHE_PN91.dat",
            workflow: "ahe"
        )

        let hits = try SearchWorkflowMeasurementsUseCase().execute(
            query: WorkflowSearchQuery(rawText: "PN91"),
            libraryRootURL: fixture.rootURL
        )

        #expect(hits.count == 1)
        #expect(hits[0].sampleKey == "PN91|b|STO|111")
        #expect(hits[0].sampleKey != "PN91|WRONG|STO|999")
    }

    // MARK: - C: old sidecar with sampleKey == nil still uses the path-derived fallback

    @Test("legacy sidecar without sampleKey falls back to path-derived + normalized value")
    func legacySidecarFallsBackToPathDerivedSampleKey() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        try fixture.writeSidecar(
            batchID: "PN92",
            folderSampleKey: "PN92|b|STO|111",
            sidecarSampleKey: nil,
            workflowFolder: "ahe",
            measurementFileName: "AHE_PN92.dat",
            workflow: "ahe"
        )

        let hits = try SearchWorkflowMeasurementsUseCase().execute(
            query: WorkflowSearchQuery(rawText: "PN92"),
            libraryRootURL: fixture.rootURL
        )

        #expect(hits.count == 1)
        #expect(hits[0].sampleKey == "PN92|b|STO|111")
    }

    // MARK: - D: effectiveConditions — user override reflected without Search re-merging

    @Test("Hit.conditions reflects sidecar.effectiveConditions, including a manual override")
    func hitConditionsReflectsEffectiveConditionsWithOverride() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        try fixture.writeSidecar(
            batchID: "PN93",
            folderSampleKey: "PN93|b|STO|111",
            sidecarSampleKey: "PN93|b|STO|111",
            workflowFolder: "ahe",
            measurementFileName: "AHE_PN93.dat",
            workflow: "ahe",
            ruleConditions: ["temperature": "80K"],
            overrideConditions: ["temperature": "82K"]
        )

        let hits = try SearchWorkflowMeasurementsUseCase().execute(
            query: WorkflowSearchQuery(rawText: "PN93"),
            libraryRootURL: fixture.rootURL
        )

        #expect(hits.count == 1)
        // Overridden value wins — this is sidecar.effectiveConditions, not the raw rule layer.
        #expect(hits[0].conditions["temperature"] == "82K")
    }

    // MARK: - E: channels — Hit.channels exactly equals sidecar.channels

    @Test("Hit.channels exactly equals sidecar.channels, unsorted and unmodified")
    func hitChannelsExactlyMatchesSidecarChannels() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        try fixture.writeSidecar(
            batchID: "PN94",
            folderSampleKey: "PN94|b|STO|111",
            sidecarSampleKey: "PN94|b|STO|111",
            workflowFolder: "ahe",
            measurementFileName: "AHE_PN94.dat",
            workflow: "ahe",
            channels: ["ch3", "ch1", "ch2"]
        )

        let hits = try SearchWorkflowMeasurementsUseCase().execute(
            query: WorkflowSearchQuery(rawText: "PN94"),
            libraryRootURL: fixture.rootURL
        )

        #expect(hits.count == 1)
        #expect(hits[0].channels == ["ch3", "ch1", "ch2"])
    }

    // MARK: - F: sidecar workflow remains authoritative over folder fallback

    @Test("sidecar workflow wins over a mismatched folder name")
    func sidecarWorkflowWinsOverFolderName() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        // Folder is named "General" (a real, valid destination category) while the
        // sidecar itself declares "ahe" — sidecar must be authoritative.
        try fixture.writeSidecar(
            batchID: "PN95",
            folderSampleKey: "PN95|b|STO|111",
            sidecarSampleKey: "PN95|b|STO|111",
            workflowFolder: "General",
            measurementFileName: "AHE_PN95.dat",
            workflow: "ahe"
        )

        let hits = try SearchWorkflowMeasurementsUseCase().execute(
            query: WorkflowSearchQuery(rawText: "PN95"),
            libraryRootURL: fixture.rootURL
        )

        #expect(hits.count == 1)
        #expect(hits[0].workflowID == "ahe")
    }

    // MARK: - Bonus: measurementTimestamp projects verbatim from sidecar, provenance preserved

    @Test("Hit.measurementTimestamp projects verbatim from sidecar, including provenance")
    func hitMeasurementTimestampProjectsVerbatim() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        let timestamp = SidecarMeasurementTimestamp(
            value: Date(timeIntervalSince1970: 1_700_000_000),
            provenance: .instrumentHeader,
            rawText: "3/18/2026,1:24 PM"
        )
        try fixture.writeSidecar(
            batchID: "PN96",
            folderSampleKey: "PN96|b|STO|111",
            sidecarSampleKey: "PN96|b|STO|111",
            workflowFolder: "ahe",
            measurementFileName: "AHE_PN96.dat",
            workflow: "ahe",
            measurementTimestamp: timestamp
        )

        let hits = try SearchWorkflowMeasurementsUseCase().execute(
            query: WorkflowSearchQuery(rawText: "PN96"),
            libraryRootURL: fixture.rootURL
        )

        #expect(hits.count == 1)
        #expect(hits[0].measurementTimestamp == timestamp)
    }
}

// MARK: - Fixture

private struct Fixture {
    let rootURL: URL
    private let fileManager = FileManager.default

    init() throws {
        rootURL = fileManager.temporaryDirectory.appending(path: "spinlab-testrecord-p2-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? fileManager.removeItem(at: rootURL)
    }

    func writeSidecar(
        batchID: String,
        folderSampleKey: String,
        sidecarSampleKey: String?,
        workflowFolder: String,
        measurementFileName: String,
        workflow: String,
        ruleConditions: [String: String] = [:],
        overrideConditions: [String: String] = [:],
        channels: [String] = ["ch1"],
        measurementTimestamp: SidecarMeasurementTimestamp? = nil
    ) throws {
        let measurementDirectory = rootURL
            .appending(path: "batches/PN/\(batchID)/samples/\(folderSampleKey)/measurements/\(workflowFolder)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: measurementDirectory, withIntermediateDirectories: true)

        let measurementURL = measurementDirectory.appending(path: measurementFileName)
        try Data("x,y\n1,2\n".utf8).write(to: measurementURL)

        let sidecarURL = measurementDirectory.appending(path: "\(measurementFileName).spinlab.json")
        let ruleConditionFields = ruleConditions.mapValues { v in SourcedValue(value: v, source: "test:fixture") }
        let overrideFields = overrideConditions.mapValues { v in
            ManualValueOverride(value: v, reason: "test", at: Date(timeIntervalSince1970: 1_712_146_500))
        }
        let sidecar = SpinLabFileSidecar(
            workflow: workflow,
            workflowDisplayName: workflow,
            channels: channels,
            sourceFilePath: measurementURL.path,
            appliedAt: Date(timeIntervalSince1970: 1_712_146_400),
            ruleSnapshot: SidecarRuleSnapshot(
                ruleSetVersion: 0,
                ruleSetFingerprint: "test:fixture",
                appliedAt: Date(timeIntervalSince1970: 1_712_146_400),
                fields: SidecarRuleFields(sampleID: nil, conditions: ruleConditionFields, substrateTags: [])
            ),
            userOverrides: SidecarUserOverrides(conditions: overrideFields),
            sampleKey: sidecarSampleKey,
            measurementTimestamp: measurementTimestamp
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(sidecar).write(to: sidecarURL)
    }
}
