import Foundation
import Testing
@testable import SpinLabApp

/// v5.5.7 — AHE series metadata now flows through the shared
/// `WorkbenchSeriesMetadataBuilder` (same path as RT/IV/XY Rotation/3ω) instead of a
/// hand-rolled dictionary in `IngestAHESelectionsUseCase`. Locks down that AHE emits the
/// same common contract keys (including batchID, previously missing) as its siblings, and
/// that AHE-specific metadata values (substrate, numeric-tag mapping) are unchanged.
@Suite("v5.5.7 - AHE shared series metadata builder")
struct V557AHESeriesMetadataBuilderTests {

    private struct Fixture {
        let rootURL: URL
        let fm = FileManager.default

        init() throws {
            rootURL = fm.temporaryDirectory.appending(
                path: "spinlab-v557-ahe-metadata-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        func write(name: String, content: String) throws -> URL {
            let url = rootURL.appending(path: name)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        func cleanup() { try? fm.removeItem(at: rootURL) }
    }

    private enum Fixtures {
        static let colHeader = "Comment,Time Stamp (sec),Status (code),Temperature (K),Magnetic Field (Oe),Sample Position (deg),Bridge 1 Resistivity (Ohm),Bridge 1 Excitation (uA),Bridge 2 Resistivity (Ohm),Bridge 2 Excitation (uA),Bridge 3 Resistivity (Ohm),Bridge 3 Excitation (uA),Bridge 4 Resistivity (Ohm),Bridge 4 Excitation (uA),Bridge 1 Std. Dev. (Ohm),Bridge 2 Std. Dev. (Ohm),Bridge 3 Std. Dev. (Ohm),Bridge 4 Std. Dev. (Ohm),Number of Readings,Bridge 1 Resistance (Ohms),Bridge 2 Resistance (Ohms),Bridge 3 Resistance (Ohms),Bridge 4 Resistance (Ohms)"

        static let ch1Only = """
        [Header]
        TITLE, test
        [Data]
        \(colHeader)
        ,0,4449,80.0,10000.0,0,1.0,500,,,,,,,,,,,25,1.0,,,
        ,1,4449,80.0,5000.0,0,0.9,500,,,,,,,,,,,25,0.9,,,
        ,2,4449,80.0,-5000.0,0,0.8,500,,,,,,,,,,,25,0.8,,,
        """
    }

    private func ingest(
        sampleKey: String = "PN31|o|STO|111",
        batchID: String = "PN31",
        conditions: [String: String] = ["temperature": "80K"],
        numericDisplayBySample: [String: [String: String]] = [:]
    ) throws -> AHEIngestionResult {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let url = try fixture.write(name: "ahe.dat", content: Fixtures.ch1Only)

        return try IngestAHESelectionsUseCase().execute(
            selections: [
                AHEPlotSelectionItem(
                    sampleKey: sampleKey,
                    sourceFilePath: url.path,
                    channel: .ch1,
                    conditions: conditions,
                    sampleSubstrate: "STO111",
                    batchID: batchID
                )
            ],
            numericDisplayBySample: numericDisplayBySample,
            parseFile: { try PPMSDATLoader().load(fileURL: $0) }
        )
    }

    // MARK: - Common contract parity with RT/IV/XY Rotation/3ω

    @Test("AHE series metadata carries batchID, matching sibling workflows")
    func metadataIncludesBatchID() throws {
        let result = try ingest()
        let meta = try #require(result.series.first?.metadata)
        #expect(meta["batchID"] == "PN31")
    }

    @Test("AHE series metadata includes the same common contract keys as other Cartesian workflows")
    func metadataIncludesCommonContractKeys() throws {
        let result = try ingest()
        let meta = try #require(result.series.first?.metadata)

        // These keys are the resolver-facing contract WorkbenchSeriesMetadataBuilder
        // guarantees for every workflow that calls it (RT, IV, XY Rotation, 3ω, and now AHE).
        for key in ["sampleKey", "batchID", "substrate", "temperature"] {
            #expect(meta[key] != nil, "expected AHE metadata to include shared-contract key '\(key)'")
        }
    }

    @Test("AHE metadata matches WorkbenchSeriesMetadataBuilder output built directly from an equivalent hit")
    func metadataMatchesBuilderOutputForEquivalentHit() throws {
        let result = try ingest(numericDisplayBySample: ["PN31|o|STO|111": ["厚度": "30"]])
        let meta = try #require(result.series.first?.metadata)

        let equivalentHit = WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/PN31|o|STO|111.spinlab.json",
            measurementFilePath: "/tmp/ahe.dat",
            sourceFilePath: "/tmp/ahe.dat",
            workflowID: "AHE",
            workflowDisplayName: "AHE",
            workflowCanonicalID: "AHE",
            batchID: "PN31",
            sampleKey: "PN31|o|STO|111",
            sampleSubstrate: "STO111",
            conditions: ["temperature": "80K"],
            channels: ["ch1"],
            appliedAt: .distantPast
        )
        let expected = WorkbenchSeriesMetadataBuilder.build(
            from: equivalentHit,
            numericDisplay: ["厚度": "30"]
        )

        for (key, value) in expected {
            #expect(meta[key] == value, "mismatch for key '\(key)'")
        }
    }

    // MARK: - AHE-specific metadata values unchanged

    @Test("AHE substrate metadata is derived from sampleKey processing tokens, unchanged")
    func substrateDerivedFromSampleKey() throws {
        let result = try ingest(sampleKey: "PN31|o|STO|111")
        let meta = try #require(result.series.first?.metadata)
        #expect(meta["substrate"] == "o STO 111")
    }

    @Test("AHE numeric-tag metadata maps Chinese registry keys to resolver keys, unchanged")
    func numericTagsMapToResolverKeys() throws {
        let result = try ingest(
            numericDisplayBySample: [
                "PN31|o|STO|111": [
                    "能量": "60mJ",
                    "氧压": "100mT",
                    "厚度": "30nm",
                    "生长温度": "700C"
                ]
            ]
        )
        let meta = try #require(result.series.first?.metadata)
        #expect(meta["energy"] == "60mJ")
        #expect(meta["pressure"] == "100mT")
        #expect(meta["thickness"] == "30nm")
        #expect(meta["growthTemperature"] == "700C")
    }

    @Test("AHE metadata still carries the series-identity resolver key")
    func metadataIncludesSeriesIdentityKey() throws {
        let result = try ingest()
        let meta = try #require(result.series.first?.metadata)
        #expect(meta[WorkbenchSeriesOrderKeyResolver.seriesIdentityMetadataKey] != nil)
    }

    @Test("AHE sampleKey metadata matches selection sampleKey, unchanged")
    func sampleKeyMetadataUnchanged() throws {
        let result = try ingest(sampleKey: "PN50|b|STO|111", batchID: "PN50")
        let meta = try #require(result.series.first?.metadata)
        #expect(meta["sampleKey"] == "PN50|b|STO|111")
    }
}
