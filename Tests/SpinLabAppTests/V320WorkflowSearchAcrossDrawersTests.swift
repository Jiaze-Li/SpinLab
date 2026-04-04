import Foundation
import Testing
@testable import SpinLabApp

@Suite("V3.2.0 Workflow Search Across Drawers")
struct V320WorkflowSearchAcrossDrawersTests {
    @Test("query AHE returns sidecars stored under workflow folder A")
    func queryAHEFindsWorkflowA() throws {
        let fixture = try WorkflowSearchFixture()
        defer { fixture.cleanup() }

        try fixture.writeSidecar(
            batchID: "PN31",
            sampleKey: "PN31|b|STO|111",
            workflowFolder: "A",
            measurementFileName: "AHE_PN31_80K.dat",
            workflowID: "A",
            workflowDisplayName: "",
            conditions: ["temperature": "80K", "field": "3T"]
        )
        try fixture.writeSidecar(
            batchID: "PN32",
            sampleKey: "PN32|b|STO|111",
            workflowFolder: "RT",
            measurementFileName: "RT_PN32_300K.dat",
            workflowID: "RT",
            workflowDisplayName: "RT",
            conditions: ["temperature": "300K"]
        )

        let useCase = SearchWorkflowMeasurementsUseCase()
        let hits = try useCase.execute(
            query: WorkflowSearchQuery(rawText: "AHE"),
            libraryRootURL: fixture.rootURL
        )

        #expect(hits.count == 1)
        #expect(hits[0].workflowCanonicalID == "ahe")
        #expect(hits[0].workflowDisplayName == "AHE")
        #expect(hits[0].sampleKey == "PN31|b|STO|111")
    }

    @Test("combined query supports workflow plus sample and condition")
    func combinedQueryMatchesWorkflowAndSampleAndCondition() throws {
        let fixture = try WorkflowSearchFixture()
        defer { fixture.cleanup() }

        try fixture.writeSidecar(
            batchID: "PN31",
            sampleKey: "PN31|b|STO|111",
            workflowFolder: "A",
            measurementFileName: "AHE_PN31_80K.dat",
            workflowID: "A",
            workflowDisplayName: "AHE",
            conditions: ["temperature": "80K"]
        )
        try fixture.writeSidecar(
            batchID: "PN31",
            sampleKey: "PN31|b|STO|111",
            workflowFolder: "A",
            measurementFileName: "AHE_PN31_150K.dat",
            workflowID: "A",
            workflowDisplayName: "AHE",
            conditions: ["temperature": "150K"]
        )

        let useCase = SearchWorkflowMeasurementsUseCase()
        let hits = try useCase.execute(
            query: WorkflowSearchQuery(rawText: "AHE PN31 80K"),
            libraryRootURL: fixture.rootURL
        )

        #expect(hits.count == 1)
        #expect(hits[0].conditions["temperature"] == "80K")
    }

    @Test("3w and 3omega query map to same workflow type")
    func threeWOmegaAlias() throws {
        let fixture = try WorkflowSearchFixture()
        defer { fixture.cleanup() }

        try fixture.writeSidecar(
            batchID: "PN40",
            sampleKey: "PN40|HF|STO|111",
            workflowFolder: "3W",
            measurementFileName: "3W_PN40_30K.dat",
            workflowID: "3W",
            workflowDisplayName: "3W",
            conditions: ["temperature": "30K"]
        )

        let useCase = SearchWorkflowMeasurementsUseCase()
        let threeW = try useCase.execute(
            query: WorkflowSearchQuery(rawText: "3W"),
            libraryRootURL: fixture.rootURL
        )
        let threeOmega = try useCase.execute(
            query: WorkflowSearchQuery(rawText: "3ω"),
            libraryRootURL: fixture.rootURL
        )

        #expect(threeW.count == 1)
        #expect(threeOmega.count == 1)
        #expect(threeW[0].id == threeOmega[0].id)
    }

    @Test("search result order is stable and ascending by batch sample file")
    func searchOrderIsAscending() throws {
        let fixture = try WorkflowSearchFixture()
        defer { fixture.cleanup() }

        try fixture.writeSidecar(
            batchID: "PN27",
            sampleKey: "PN27|b|STO|111",
            workflowFolder: "A",
            measurementFileName: "B_file.dat",
            workflowID: "A",
            workflowDisplayName: "AHE",
            conditions: ["temperature": "80K"]
        )
        try fixture.writeSidecar(
            batchID: "PN18",
            sampleKey: "PN18|b|STO|111",
            workflowFolder: "A",
            measurementFileName: "A_file.dat",
            workflowID: "A",
            workflowDisplayName: "AHE",
            conditions: ["temperature": "80K"]
        )

        let useCase = SearchWorkflowMeasurementsUseCase()
        let hits = try useCase.execute(
            query: WorkflowSearchQuery(rawText: "AHE"),
            libraryRootURL: fixture.rootURL
        )

        #expect(hits.count == 2)
        #expect(hits.map(\.batchID) == ["PN18", "PN27"])
    }

    @Test("HF query matches structural fields only and ignores filename/source-path text")
    func hfQueryIgnoresFilenameAndSourcePathText() throws {
        let fixture = try WorkflowSearchFixture()
        defer { fixture.cleanup() }

        try fixture.writeSidecar(
            batchID: "PN27",
            sampleKey: "PN27|b|STO|111",
            workflowFolder: "A",
            measurementFileName: "contains_HF_in_filename_only.dat",
            workflowID: "A",
            workflowDisplayName: "AHE",
            conditions: ["temperature": "80K"],
            channels: ["ch1"]
        )

        let useCase = SearchWorkflowMeasurementsUseCase()
        let hits = try useCase.execute(
            query: WorkflowSearchQuery(rawText: "HF"),
            libraryRootURL: fixture.rootURL
        )

        #expect(hits.isEmpty)
    }

    @Test("space-separated tokens match independently for o sto query")
    func singleCharacterTokenOAndStoMatchIndependently() throws {
        let fixture = try WorkflowSearchFixture()
        defer { fixture.cleanup() }

        try fixture.writeSidecar(
            batchID: "PN31",
            sampleKey: "PN31|o|STO|111",
            workflowFolder: "A",
            measurementFileName: "AHE_PN31_80K.dat",
            workflowID: "A",
            workflowDisplayName: "AHE",
            conditions: ["temperature": "80K"]
        )
        try fixture.writeSidecar(
            batchID: "PN32",
            sampleKey: "PN32|b|STO|111",
            workflowFolder: "A",
            measurementFileName: "AHE_PN32_80K.dat",
            workflowID: "A",
            workflowDisplayName: "AHE",
            conditions: ["temperature": "80K"]
        )

        let useCase = SearchWorkflowMeasurementsUseCase()
        let hits = try useCase.execute(
            query: WorkflowSearchQuery(rawText: "o sto"),
            libraryRootURL: fixture.rootURL
        )

        #expect(hits.count == 1)
        #expect(hits[0].sampleKey == "PN31|o|STO|111")
    }

    @Test("single-character token b is matched as an independent token")
    func singleCharacterTokenBMatchesIndependently() throws {
        let fixture = try WorkflowSearchFixture()
        defer { fixture.cleanup() }

        try fixture.writeSidecar(
            batchID: "PN31",
            sampleKey: "PN31|o|STO|111",
            workflowFolder: "A",
            measurementFileName: "AHE_PN31_80K.dat",
            workflowID: "A",
            workflowDisplayName: "AHE",
            conditions: ["temperature": "80K"]
        )
        try fixture.writeSidecar(
            batchID: "PN32",
            sampleKey: "PN32|b|STO|111",
            workflowFolder: "A",
            measurementFileName: "AHE_PN32_80K.dat",
            workflowID: "A",
            workflowDisplayName: "AHE",
            conditions: ["temperature": "80K"]
        )

        let useCase = SearchWorkflowMeasurementsUseCase()
        let hits = try useCase.execute(
            query: WorkflowSearchQuery(rawText: "b"),
            libraryRootURL: fixture.rootURL
        )

        #expect(hits.count == 1)
        #expect(hits[0].sampleKey == "PN32|b|STO|111")
    }

    @Test("legacy sample-key directory formats are normalized to canonical key")
    func legacySampleKeyPathFormatsAreNormalized() throws {
        let fixture = try WorkflowSearchFixture()
        defer { fixture.cleanup() }

        try fixture.writeSidecar(
            batchID: "PN31",
            sampleKey: "PN31 - o STO(111)",
            workflowFolder: "A",
            measurementFileName: "AHE_PN31_80K.dat",
            workflowID: "A",
            workflowDisplayName: "AHE",
            conditions: ["temperature": "80K"]
        )

        let useCase = SearchWorkflowMeasurementsUseCase()
        let hits = try useCase.execute(
            query: WorkflowSearchQuery(rawText: "ahe pn31 o sto111"),
            libraryRootURL: fixture.rootURL
        )

        #expect(hits.count == 1)
        #expect(hits[0].sampleKey == "PN31|o|STO|111")
        #expect(hits[0].sampleBatchAndSubstrate == "PN31 o STO111")
    }
}

private struct WorkflowSearchFixture {
    let rootURL: URL
    private let fileManager = FileManager.default

    init() throws {
        rootURL = fileManager.temporaryDirectory.appending(path: "spinlab-v320-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func writeSidecar(
        batchID: String,
        sampleKey: String,
        workflowFolder: String,
        measurementFileName: String,
        workflowID: String,
        workflowDisplayName: String,
        conditions: [String: String],
        channels: [String] = ["ch1"]
    ) throws {
        let measurementDirectory = rootURL
            .appending(path: "batches/PN/\(batchID)/samples/\(sampleKey)/measurements/\(workflowFolder)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: measurementDirectory, withIntermediateDirectories: true)

        let measurementURL = measurementDirectory.appending(path: measurementFileName)
        try Data("x,y\n1,2\n".utf8).write(to: measurementURL)

        let sidecarURL = measurementDirectory.appending(path: "\(measurementFileName).spinlab.json")
        let sidecar = SpinLabFileSidecar(
            workflow: workflowID,
            workflowDisplayName: workflowDisplayName,
            conditions: conditions,
            channels: channels,
            sourceFilePath: measurementURL.path,
            appliedAt: Date(timeIntervalSince1970: 1_712_146_400)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(sidecar).write(to: sidecarURL)
    }

    func cleanup() {
        try? fileManager.removeItem(at: rootURL)
    }
}
