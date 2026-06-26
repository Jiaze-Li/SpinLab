import Testing
import Foundation
@testable import SpinLabApp

// MARK: - Synthetic PPMS .dat helpers

private func makePPMSDatContent(
    extraHeaders: [String] = [],
    extraColumns: [[Double]] = [],
    rows: [(t: Double, b1r: Double, b2r: Double, b3r: Double)] = [
        (10.0, 101.5, 201.5, 301.5),
        (20.0, 110.2, 210.2, 310.2),
        (5.0,  95.1,  195.1, 295.1),
    ]
) -> String {
    let baseHeaders = ["Temperature (K)", "Bridge 1 Resistance (Ohms)", "Bridge 2 Resistance (Ohms)", "Bridge 3 Resistance (Ohms)"]
    let allHeaders = (baseHeaders + extraHeaders).joined(separator: ",")
    let dataRows = rows.map { row -> String in
        let base = "\(row.t),\(row.b1r),\(row.b2r),\(row.b3r)"
        let extras = extraColumns.map { _ in "0.0" }.joined(separator: ",")
        return extras.isEmpty ? base : "\(base),\(extras)"
    }.joined(separator: "\n")
    return "[Header]\nFILEOPENTIME,01/01/2024\n\n[Data]\n\(allHeaders)\n\(dataRows)\n"
}

private func writeTempDat(_ content: String, name: String = "test.dat") -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "\(name)_\(UUID().uuidString).dat")
    try? content.write(to: url, atomically: true, encoding: .utf8)
    return url
}

private func makeDatHit(filePath: String, channels: [String]) -> WorkflowMeasurementSearchHit {
    WorkflowMeasurementSearchHit(
        sidecarPath: filePath + ".spinlab.json",
        measurementFilePath: filePath,
        sourceFilePath: filePath,
        workflowID: "RT",
        workflowDisplayName: "RT",
        workflowCanonicalID: "RT",
        batchID: "PN59",
        sampleKey: "PN59",
        sampleSubstrate: "",
        conditions: [:],
        channels: channels,
        appliedAt: .distantPast
    )
}

// MARK: - Parser Tests

@Suite("V5.5 RTPPMSDatParser")
struct V55RTPPMSDatParserTests {

    let parser = RTPPMSDatParser()

    // MARK: Channel → bridge index mapping

    @Test("ch1 maps to bridge index 1")
    func channelMappingCh1() {
        #expect(RTPPMSDatParser.bridgeIndex(forChannel: "ch1") == 1)
    }

    @Test("ch2 maps to bridge index 2")
    func channelMappingCh2() {
        #expect(RTPPMSDatParser.bridgeIndex(forChannel: "ch2") == 2)
    }

    @Test("ch3 maps to bridge index 3")
    func channelMappingCh3() {
        #expect(RTPPMSDatParser.bridgeIndex(forChannel: "ch3") == 3)
    }

    @Test("unrecognized channel returns nil")
    func channelMappingUnknown() {
        #expect(RTPPMSDatParser.bridgeIndex(forChannel: "ch4") == nil)
        #expect(RTPPMSDatParser.bridgeIndex(forChannel: "") == nil)
    }

    // MARK: Temperature (x axis)

    @Test("x column is Temperature (K); rows are sorted ascending after use case")
    func temperatureColumnExtracted() throws {
        let url = writeTempDat(makePPMSDatContent())
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try parser.parse(fileURL: url, bridgeIndex: 1)
        // Parser returns in file order (unsorted); sorting is use case responsibility
        #expect(result.temperatureK == [10.0, 20.0, 5.0])
    }

    // MARK: Bridge column selection

    @Test("ch1 extracts Bridge 1 Resistance (Ohms)")
    func ch1ExtractsBridge1Resistance() throws {
        let url = writeTempDat(makePPMSDatContent())
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try parser.parse(fileURL: url, bridgeIndex: 1)
        #expect(result.rxx == [101.5, 110.2, 95.1])
        #expect(result.warnings.isEmpty)
    }

    @Test("ch2 extracts Bridge 2 Resistance (Ohms)")
    func ch2ExtractsBridge2Resistance() throws {
        let url = writeTempDat(makePPMSDatContent())
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try parser.parse(fileURL: url, bridgeIndex: 2)
        #expect(result.rxx == [201.5, 210.2, 195.1])
    }

    @Test("ch3 extracts Bridge 3 Resistance (Ohms)")
    func ch3ExtractsBridge3Resistance() throws {
        let url = writeTempDat(makePPMSDatContent())
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try parser.parse(fileURL: url, bridgeIndex: 3)
        #expect(result.rxx == [301.5, 310.2, 295.1])
    }

    @Test("falls back to Resistivity column when Resistance column is absent")
    func resistivityFallback() throws {
        let content = """
        [Header]
        FILEOPENTIME,01/01/2024

        [Data]
        Temperature (K),Bridge 1 Resistivity (Ohm)
        10.0,0.0055
        20.0,0.0062
        """
        let url = writeTempDat(content)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try parser.parse(fileURL: url, bridgeIndex: 1)
        #expect(result.rxx == [0.0055, 0.0062])
    }

    // MARK: Malformed rows

    @Test("malformed rows are skipped with warnings; valid rows still returned")
    func malformedRowsSkipped() throws {
        let content = """
        [Header]

        [Data]
        Temperature (K),Bridge 1 Resistance (Ohms)
        10.0,101.5
        bad_row_here
        20.0,110.2
        """
        let url = writeTempDat(content)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try parser.parse(fileURL: url, bridgeIndex: 1)
        #expect(result.temperatureK == [10.0, 20.0])
        #expect(result.rxx == [101.5, 110.2])
        #expect(!result.warnings.isEmpty)
    }

    @Test("all-malformed rows throws noValidDataRows")
    func allMalformedThrows() throws {
        let content = """
        [Header]

        [Data]
        Temperature (K),Bridge 1 Resistance (Ohms)
        not_a_number,also_not
        """
        let url = writeTempDat(content)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: RTPPMSDatParser.ParseError.self) {
            try parser.parse(fileURL: url, bridgeIndex: 1)
        }
    }

    // MARK: Missing section / column errors

    @Test("missing [Data] section throws dataSectionNotFound")
    func missingDataSection() throws {
        let content = "Temperature (K),Bridge 1 Resistance (Ohms)\n10.0,101.5\n"
        let url = writeTempDat(content)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: RTPPMSDatParser.ParseError.self) {
            try parser.parse(fileURL: url, bridgeIndex: 1)
        }
    }

    @Test("missing Temperature column throws temperatureColumnNotFound")
    func missingTemperatureColumn() throws {
        let content = "[Data]\nBridge 1 Resistance (Ohms)\n101.5\n"
        let url = writeTempDat(content)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: RTPPMSDatParser.ParseError.self) {
            try parser.parse(fileURL: url, bridgeIndex: 1)
        }
    }

    @Test("missing bridge column throws bridgeColumnNotFound")
    func missingBridgeColumn() throws {
        let content = "[Data]\nTemperature (K)\n10.0\n"
        let url = writeTempDat(content)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: RTPPMSDatParser.ParseError.self) {
            try parser.parse(fileURL: url, bridgeIndex: 1)
        }
    }
}

// MARK: - Use Case Dispatch Tests

@Suite("V5.5 AnalyzeRTWorkflowUseCase dispatch")
struct V55AnalyzeRTUseCaseDispatchTests {

    // MARK: Missing channel metadata

    @Test("PPMS .dat with empty channels returns empty result with clear warning")
    func emptyChannelsMissingMetadata() throws {
        let content = makePPMSDatContent()
        let url = writeTempDat(content)
        defer { try? FileManager.default.removeItem(at: url) }

        let hit = makeDatHit(filePath: url.path, channels: [])
        let result = AnalyzeRTWorkflowUseCase().execute(hit: hit, workflowID: "RT")

        #expect(result.temperatureK.isEmpty)
        #expect(result.rxx.isEmpty)
        #expect(result.format == .ppmsDat)
        #expect(result.bridgeIndex == nil)
        #expect(!result.warnings.isEmpty)
        // Warning must mention channel metadata, not silently fail
        #expect(result.warnings.first?.contains("channel") == true)
    }

    // MARK: Valid PPMS dispatch

    @Test("PPMS .dat with ch1 produces non-empty RTAnalysisResult sorted ascending")
    func ppmsDatCh1Succeeds() throws {
        let content = makePPMSDatContent()
        let url = writeTempDat(content)
        defer { try? FileManager.default.removeItem(at: url) }

        let hit = makeDatHit(filePath: url.path, channels: ["ch1"])
        let result = AnalyzeRTWorkflowUseCase().execute(hit: hit, workflowID: "RT")

        #expect(result.format == .ppmsDat)
        #expect(result.channelID == "ch1")
        #expect(result.bridgeIndex == 1)
        #expect(result.temperatureK == [5.0, 10.0, 20.0])
        #expect(result.rxx == [95.1, 101.5, 110.2])
        #expect(result.workflowID == "RT")
    }

    @Test("PPMS .dat with ch2 extracts Bridge 2 data")
    func ppmsDatCh2Succeeds() throws {
        let content = makePPMSDatContent()
        let url = writeTempDat(content)
        defer { try? FileManager.default.removeItem(at: url) }

        let hit = makeDatHit(filePath: url.path, channels: ["ch2"])
        let result = AnalyzeRTWorkflowUseCase().execute(hit: hit, workflowID: "RT")

        #expect(result.bridgeIndex == 2)
        #expect(result.rxx == [195.1, 201.5, 210.2])
    }

    @Test("PPMS .dat with ch3 extracts Bridge 3 data")
    func ppmsDatCh3Succeeds() throws {
        let content = makePPMSDatContent()
        let url = writeTempDat(content)
        defer { try? FileManager.default.removeItem(at: url) }

        let hit = makeDatHit(filePath: url.path, channels: ["ch3"])
        let result = AnalyzeRTWorkflowUseCase().execute(hit: hit, workflowID: "RT")

        #expect(result.bridgeIndex == 3)
        #expect(result.rxx == [295.1, 301.5, 310.2])
    }

    // MARK: LVM path preserved

    @Test(".lvm extension routes to LVM parser and produces format = .lvm")
    func lvmPathPreserved() throws {
        guard let url = Bundle.module.url(
            forResource: "RT_0deg_H_-0.029814 Oe_Iac_0.000200 A",
            withExtension: "lvm",
            subdirectory: "TestData/ThreeOmega"
        ) else {
            Issue.record("RT LVM fixture not found")
            return
        }

        let hit = WorkflowMeasurementSearchHit(
            sidecarPath: url.path + ".spinlab.json",
            measurementFilePath: url.path,
            sourceFilePath: url.path,
            workflowID: "RT",
            workflowDisplayName: "RT",
            workflowCanonicalID: "RT",
            batchID: "PN99",
            sampleKey: "PN99",
            sampleSubstrate: "",
            conditions: [:],
            channels: [],
            appliedAt: .distantPast
        )

        let result = AnalyzeRTWorkflowUseCase().execute(hit: hit, workflowID: "RT")
        #expect(result.format == .lvm)
        // LVM RT fixture has data rows
        #expect(!result.temperatureK.isEmpty)
    }
}
