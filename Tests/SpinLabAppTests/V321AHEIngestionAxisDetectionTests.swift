import Foundation
import Testing
@testable import SpinLabApp

@Suite("V3.2.1 AHE Ingestion + Axis Detection")
struct V321AHEIngestionAxisDetectionTests {

    // MARK: - Parser format tests

    @Test("parse variant-A dat (with [Header]/[Data]) returns columns and data rows")
    func parseDatVariantA() throws {
        let fixture = try AHEDatFixture()
        defer { fixture.cleanup() }

        let url = try fixture.write(name: "varA.dat", content: Fixtures.variantA_ch1Only)
        let parsed = try AHEDataParser().parse(fileURL: url)

        #expect(parsed.columnNames.contains("Magnetic Field (Oe)"))
        #expect(parsed.columnNames.contains("Bridge 1 Resistance (Ohms)"))
        #expect(parsed.rows.count == 3)
        // Field value at row 0, Magnetic Field column
        let fieldIdx = parsed.columnNames.firstIndex(of: "Magnetic Field (Oe)")!
        #expect(Double(parsed.rows[0][fieldIdx]) == 10000.0)
    }

    @Test("parse legacy variant-B dat (no [Header]) returns columns and data rows")
    func parseDatVariantB() throws {
        let fixture = try AHEDatFixture()
        defer { fixture.cleanup() }

        let url = try fixture.write(name: "varB.dat", content: Fixtures.variantB_ch1Only)
        let parsed = try AHEDataParser().parse(fileURL: url)

        #expect(parsed.columnNames.contains("Magnetic Field (Oe)"))
        #expect(parsed.columnNames.contains("Bridge 1 Resistance (Ohms)"))
        #expect(parsed.rows.count == 3)
    }

    // MARK: - Default axis mapping

    @Test("default x axis is Magnetic Field (Oe)")
    func defaultXAxisIsMagneticField() throws {
        let fixture = try AHEDatFixture()
        defer { fixture.cleanup() }

        let url = try fixture.write(name: "f.dat", content: Fixtures.variantA_ch1Only)
        let result = try IngestAHESelectionsUseCase().execute(
            selections: [.init(sampleKey: "PN31|o|STO|111", sourceFilePath: url.path, channel: .ch1, conditions: ["temperature": "80K"])],
            parseFile: { try AHEDataParser().parse(fileURL: $0) }
        )

        #expect(result.defaultAxisMapping.xField == "Magnetic Field (Oe)")
    }

    @Test("default y axis is Bridge 1 Resistance (Ohms) when Bridge 1 is active")
    func defaultYAxisIsFirstActiveBridgeResistance() throws {
        let fixture = try AHEDatFixture()
        defer { fixture.cleanup() }

        let url = try fixture.write(name: "f.dat", content: Fixtures.variantA_ch1Only)
        let result = try IngestAHESelectionsUseCase().execute(
            selections: [.init(sampleKey: "PN31|o|STO|111", sourceFilePath: url.path, channel: .ch1, conditions: ["temperature": "80K"])],
            parseFile: { try AHEDataParser().parse(fileURL: $0) }
        )

        #expect(result.defaultAxisMapping.yField == "Bridge 1 Resistance (Ohms)")
    }

    // MARK: - Parse-once guarantee

    @Test("same file is parsed exactly once for multiple channel selections")
    func sameFileParsedOnce() throws {
        let fixture = try AHEDatFixture()
        defer { fixture.cleanup() }

        let url = try fixture.write(name: "multi.dat", content: Fixtures.variantA_ch1ch2)
        var parseCount = 0
        let countingParser: (URL) throws -> PPMSParsedFile = { u in
            parseCount += 1
            return try AHEDataParser().parse(fileURL: u)
        }

        _ = try IngestAHESelectionsUseCase().execute(
            selections: [
                .init(sampleKey: "PN31|o|STO|111", sourceFilePath: url.path, channel: .ch1, conditions: ["temperature": "80K"]),
                .init(sampleKey: "PN31|b|STO|111", sourceFilePath: url.path, channel: .ch2, conditions: ["temperature": "80K"]),
            ],
            parseFile: countingParser
        )

        #expect(parseCount == 1)
    }

    // MARK: - Multi-file cross selection

    @Test("selections from different files produce one series each")
    func multiFileMixedSelectionProducesMultipleSeries() throws {
        let fixture = try AHEDatFixture()
        defer { fixture.cleanup() }

        let fileA = try fixture.write(name: "fileA.dat", content: Fixtures.variantA_ch1Only)
        let fileB = try fixture.write(name: "fileB.dat", content: Fixtures.variantB_ch1Only)

        let result = try IngestAHESelectionsUseCase().execute(
            selections: [
                .init(sampleKey: "PN31|o|STO|111",  sourceFilePath: fileA.path, channel: .ch1, conditions: ["temperature": "80K"]),
                .init(sampleKey: "PN31|HF|STO|111", sourceFilePath: fileB.path, channel: .ch1, conditions: ["temperature": "80K"]),
            ],
            parseFile: { try AHEDataParser().parse(fileURL: $0) }
        )

        #expect(result.series.count == 2)
        #expect(result.sourceFiles.count == 2)
    }

    // MARK: - Same file, different channels

    @Test("same file different channels produce separate labeled series")
    func sameFileDifferentChannelsProduceSeparateSeries() throws {
        let fixture = try AHEDatFixture()
        defer { fixture.cleanup() }

        let url = try fixture.write(name: "multi.dat", content: Fixtures.variantA_ch1ch2)
        let result = try IngestAHESelectionsUseCase().execute(
            selections: [
                .init(sampleKey: "PN31|o|STO|111", sourceFilePath: url.path, channel: .ch1, conditions: ["temperature": "80K"]),
                .init(sampleKey: "PN31|b|STO|111", sourceFilePath: url.path, channel: .ch2, conditions: ["temperature": "80K"]),
            ],
            parseFile: { try AHEDataParser().parse(fileURL: $0) }
        )

        #expect(result.series.count == 2)
        let labels = Set(result.series.map(\.label))
        #expect(labels.contains("PN31|o|STO|111 | ch1 | 80K"))
        #expect(labels.contains("PN31|b|STO|111 | ch2 | 80K"))
    }

    // MARK: - Empty bridge column

    @Test("selection for inactive bridge is skipped with warning and no crash")
    func emptyBridgeSkippedWithWarning() throws {
        let fixture = try AHEDatFixture()
        defer { fixture.cleanup() }

        // File only has Bridge 1 data; ch3 (Bridge 3) is empty
        let url = try fixture.write(name: "ch1only.dat", content: Fixtures.variantA_ch1Only)
        let result = try IngestAHESelectionsUseCase().execute(
            selections: [
                .init(sampleKey: "PN31|o|STO|111", sourceFilePath: url.path, channel: .ch3, conditions: ["temperature": "80K"]),
            ],
            parseFile: { try AHEDataParser().parse(fileURL: $0) }
        )

        #expect(result.series.isEmpty)
        #expect(!result.warnings.isEmpty)
    }

    // MARK: - Stable ordering

    @Test("default axis mapping and candidate fields are stable regardless of selection order")
    func defaultAxisMappingIsStable() throws {
        let fixture = try AHEDatFixture()
        defer { fixture.cleanup() }

        let fileA = try fixture.write(name: "fA.dat", content: Fixtures.variantA_ch1Only)
        let fileB = try fixture.write(name: "fB.dat", content: Fixtures.variantA_ch1Only)
        let parser: (URL) throws -> PPMSParsedFile = { try AHEDataParser().parse(fileURL: $0) }

        let resultAB = try IngestAHESelectionsUseCase().execute(
            selections: [
                .init(sampleKey: "S1", sourceFilePath: fileA.path, channel: .ch1),
                .init(sampleKey: "S2", sourceFilePath: fileB.path, channel: .ch1),
            ],
            parseFile: parser
        )
        let resultBA = try IngestAHESelectionsUseCase().execute(
            selections: [
                .init(sampleKey: "S2", sourceFilePath: fileB.path, channel: .ch1),
                .init(sampleKey: "S1", sourceFilePath: fileA.path, channel: .ch1),
            ],
            parseFile: parser
        )

        #expect(resultAB.defaultAxisMapping == resultBA.defaultAxisMapping)
        #expect(resultAB.candidateAxisFields == resultBA.candidateAxisFields)
    }

    // MARK: - Candidate axis fields completeness

    @Test("candidate axis fields include all active bridge resistance columns")
    func candidateAxisFieldsIncludeActiveBridges() throws {
        let fixture = try AHEDatFixture()
        defer { fixture.cleanup() }

        let url = try fixture.write(name: "multi.dat", content: Fixtures.variantA_ch1ch2)
        let result = try IngestAHESelectionsUseCase().execute(
            selections: [
                .init(sampleKey: "PN31|o|STO|111", sourceFilePath: url.path, channel: .ch1),
                .init(sampleKey: "PN31|b|STO|111", sourceFilePath: url.path, channel: .ch2),
            ],
            parseFile: { try AHEDataParser().parse(fileURL: $0) }
        )

        #expect(result.candidateAxisFields.contains("Magnetic Field (Oe)"))
        #expect(result.candidateAxisFields.contains("Bridge 1 Resistance (Ohms)"))
        #expect(result.candidateAxisFields.contains("Bridge 2 Resistance (Ohms)"))
    }
}

// MARK: - Test fixture helpers

private struct AHEDatFixture {
    let rootURL: URL
    private let fm = FileManager.default

    init() throws {
        rootURL = fm.temporaryDirectory.appending(
            path: "spinlab-v321-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func write(name: String, content: String) throws -> URL {
        let url = rootURL.appending(path: name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func cleanup() {
        try? fm.removeItem(at: rootURL)
    }
}

// MARK: - Inline fixture content

// Column header (23 columns, indices 0–22):
//  0  Comment
//  1  Time Stamp (sec)
//  2  Status (code)
//  3  Temperature (K)
//  4  Magnetic Field (Oe)          ← x axis
//  5  Sample Position (deg)
//  6  Bridge 1 Resistivity (Ohm)
//  7  Bridge 1 Excitation (uA)
//  8  Bridge 2 Resistivity (Ohm)
//  9  Bridge 2 Excitation (uA)
//  10 Bridge 3 Resistivity (Ohm)
//  11 Bridge 3 Excitation (uA)
//  12 Bridge 4 Resistivity (Ohm)
//  13 Bridge 4 Excitation (uA)
//  14 Bridge 1 Std. Dev. (Ohm)
//  15 Bridge 2 Std. Dev. (Ohm)
//  16 Bridge 3 Std. Dev. (Ohm)
//  17 Bridge 4 Std. Dev. (Ohm)
//  18 Number of Readings
//  19 Bridge 1 Resistance (Ohms)   ← y axis (ch1)
//  20 Bridge 2 Resistance (Ohms)   ← y axis (ch2)
//  21 Bridge 3 Resistance (Ohms)   ← y axis (ch3)
//  22 Bridge 4 Resistance (Ohms)
private enum Fixtures {
    static let colHeader = "Comment,Time Stamp (sec),Status (code),Temperature (K),Magnetic Field (Oe),Sample Position (deg),Bridge 1 Resistivity (Ohm),Bridge 1 Excitation (uA),Bridge 2 Resistivity (Ohm),Bridge 2 Excitation (uA),Bridge 3 Resistivity (Ohm),Bridge 3 Excitation (uA),Bridge 4 Resistivity (Ohm),Bridge 4 Excitation (uA),Bridge 1 Std. Dev. (Ohm),Bridge 2 Std. Dev. (Ohm),Bridge 3 Std. Dev. (Ohm),Bridge 4 Std. Dev. (Ohm),Number of Readings,Bridge 1 Resistance (Ohms),Bridge 2 Resistance (Ohms),Bridge 3 Resistance (Ohms),Bridge 4 Resistance (Ohms)"

    // Each data row has 23 fields (22 commas).
    // Cols 8–17 are empty; col 19 carries Bridge 1 Resistance.
    //                0  1  2     3     4        5  6    7   8 9 A B C D E F G H I   J  K L M
    static let row1_ch1 = ",0,4449,80.0,10000.0,0,1.0,500,,,,,,,,,,,25,1.0,,,"
    static let row2_ch1 = ",1,4449,80.0,5000.0,0,0.9,500,,,,,,,,,,,25,0.9,,,"
    static let row3_ch1 = ",2,4449,80.0,-5000.0,0,0.8,500,,,,,,,,,,,25,0.8,,,"

    // Bridge 1 + Bridge 2 active (cols 8–9 populated, cols 10–17 empty)
    static let row1_ch1ch2 = ",0,4449,80.0,10000.0,0,1.0,500,2.0,500,,,,,,,,,25,1.0,2.0,,"
    static let row2_ch1ch2 = ",1,4449,80.0,5000.0,0,0.9,500,1.9,500,,,,,,,,,25,0.9,1.9,,"
    static let row3_ch1ch2 = ",2,4449,80.0,-5000.0,0,0.8,500,1.8,500,,,,,,,,,25,0.8,1.8,,"

    static let variantA_ch1Only = """
    [Header]
    TITLE, test
    BYAPP, Resistivity, 2.1, 1.0
    INFO, Ohm, Sample1 Units
    [Data]
    \(colHeader)
    \(row1_ch1)
    \(row2_ch1)
    \(row3_ch1)
    """

    static let variantA_ch1ch2 = """
    [Header]
    TITLE, test
    BYAPP, Resistivity, 2.1, 1.0
    INFO, Ohm, Sample1 Units
    [Data]
    \(colHeader)
    \(row1_ch1ch2)
    \(row2_ch1ch2)
    \(row3_ch1ch2)
    """

    static let variantB_ch1Only = """
    \(colHeader)
    \(row1_ch1)
    \(row2_ch1)
    \(row3_ch1)
    """
}
