import Testing
import Foundation
@testable import SpinLabApp

// Phase 3f: shared PPMSDATLoader + AHE vertical slice migration.
// Tests A-K from the Phase 3f handoff — loader column/unit fidelity, AHE mapping fidelity
// unchanged, malformed-row compatibility, and architecture guards proving the migration didn't
// leave a second active raw PPMS parser for AHE.

@Suite("Phase 3f PPMSDATLoader Migration")
struct V3fPPMSDATLoaderMigrationTests {

    private static let projectRoot: URL = {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()  // SpinLabAppTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
    }()

    private struct Fixture {
        let rootURL: URL
        private let fm = FileManager.default

        init() throws {
            rootURL = fm.temporaryDirectory.appending(
                path: "spinlab-v3f-ppmsdat-\(UUID().uuidString)", directoryHint: .isDirectory
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
        static let colHeader = "Comment,Time Stamp (sec),Status (code),Temperature (K),Magnetic Field (Oe),Sample Position (deg),Bridge 1 Resistivity (Ohm),Bridge 1 Excitation (uA),Bridge 1 Resistance (Ohms)"

        static let variantA = """
        [Header]
        TITLE, test
        BYAPP, Resistivity, 2.1, 1.0
        [Data]
        \(colHeader)
        ,0,4449,80.0,10000.0,0,1.0,500,1.0
        ,1,4449,80.0,5000.0,0,0.9,500,0.9
        ,2,4449,80.0,-5000.0,0,0.8,500,0.8
        """

        // Row 1 has one too few fields (missing trailing value); row 2 has one too many.
        static let malformed = """
        [Header]
        TITLE, test
        [Data]
        \(colHeader)
        ,0,4449,80.0,10000.0,0,1.0,500,1.0
        ,1,4449,80.0,5000.0,0,0.9,500
        ,2,4449,80.0,-5000.0,0,0.8,500,0.8,extra
        """
    }

    // MARK: A/B — columns and raw labels preserved exactly

    @Test("A/B: PPMSDATLoader returns correct columns with raw labels preserved exactly")
    func loaderReturnsColumnsWithExactRawLabels() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let url = try fixture.write(name: "f.dat", content: Fixtures.variantA)

        let loaded = try PPMSDATLoader().load(fileURL: url)

        #expect(loaded.format == .ppmsDAT)
        #expect(loaded.rowCount == 3)
        #expect(loaded.signals.count == 9)
        #expect(loaded.signals[4].rawLabel == "Magnetic Field (Oe)")
        #expect(loaded.signals[8].rawLabel == "Bridge 1 Resistance (Ohms)")
        #expect(loaded.signals[4].sourceColumnIndex == 4)
        #expect(loaded.signals[4].values == [10000.0, 5000.0, -5000.0])
        #expect(loaded.signals[8].values == [1.0, 0.9, 0.8])
    }

    // MARK: C/D — typed unit assignment

    @Test("C: Temperature (K) column is typed .temperature(.kelvin) with PhysicalQuantityID .temperature")
    func temperatureColumnTypedCorrectly() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let url = try fixture.write(name: "f.dat", content: Fixtures.variantA)

        let loaded = try PPMSDATLoader().load(fileURL: url)
        let temperature = loaded.signals[3]
        #expect(temperature.rawLabel == "Temperature (K)")
        #expect(temperature.sourceUnit == .temperature(.kelvin))
        #expect(temperature.physicalQuantityID == .temperature)
    }

    @Test("D: Magnetic Field (Oe) column is typed .magneticField(.oersted) with PhysicalQuantityID .externalMagneticField")
    func magneticFieldColumnTypedCorrectly() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let url = try fixture.write(name: "f.dat", content: Fixtures.variantA)

        let loaded = try PPMSDATLoader().load(fileURL: url)
        let field = loaded.signals[4]
        #expect(field.rawLabel == "Magnetic Field (Oe)")
        #expect(field.sourceUnit == .magneticField(.oersted))
        #expect(field.physicalQuantityID == .externalMagneticField)
    }

    // MARK: E — Bridge columns remain physically unassigned

    @Test("E: Bridge Resistance/Resistivity columns preserve literal unit text but get no PhysicalQuantityID")
    func bridgeColumnsRemainUnassigned() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let url = try fixture.write(name: "f.dat", content: Fixtures.variantA)

        let loaded = try PPMSDATLoader().load(fileURL: url)
        let resistivity = loaded.signals[6]
        let resistance = loaded.signals[8]

        #expect(resistivity.rawLabel == "Bridge 1 Resistivity (Ohm)")
        #expect(resistivity.sourceUnit == .raw("Ohm"))
        #expect(resistivity.physicalQuantityID == nil)

        #expect(resistance.rawLabel == "Bridge 1 Resistance (Ohms)")
        #expect(resistance.sourceUnit == .raw("Ohms"))
        #expect(resistance.physicalQuantityID == nil)

        // Sample Position (deg) — unsafe per the Phase 3f handoff (ambiguous across workflows).
        let position = loaded.signals[5]
        #expect(position.rawLabel == "Sample Position (deg)")
        #expect(position.sourceUnit == .raw("deg"))
        #expect(position.physicalQuantityID == nil)

        // Comment column has no parenthesized unit at all.
        #expect(loaded.signals[0].rawLabel == "Comment")
        #expect(loaded.signals[0].sourceUnit == .undeclared)
        #expect(loaded.signals[0].physicalQuantityID == nil)
    }

    // MARK: F/G/I — AHE axis/bridge selection, Oe->Tesla; Resistance-only (Phase 4a)

    @Test("F/H: AHE ingestion x axis is Oe->Tesla converted, matching pre-migration behavior")
    func aheXAxisOeToTeslaUnchanged() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let url = try fixture.write(name: "f.dat", content: Fixtures.variantA)

        let result = try IngestAHESelectionsUseCase().execute(
            selections: [.init(sampleKey: "S1", sourceFilePath: url.path, channel: .ch1, conditions: ["temperature": "80K"])]
        )
        #expect(result.series.count == 1)
        #expect(result.series[0].x == [1.0, 0.5, -0.5])
        #expect(result.series[0].y == [1.0, 0.9, 0.8])
    }

    @Test("G: AHEAxisDetector uses Resistance when active; Resistivity is never consulted")
    func resistancePreferredOverResistivity() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let url = try fixture.write(name: "f.dat", content: Fixtures.variantA)

        let loaded = try PPMSDATLoader().load(fileURL: url)
        let column = AHEAxisDetector().yColumnName(from: loaded, bridgeIndex: 1)
        #expect(column == "Bridge 1 Resistance (Ohms)")
    }

    @Test("Phase 4a: AHEAxisDetector returns nil (not Resistivity) when Resistance column is absent")
    func resistivityOnlyFileNotUsedAsResistance() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let noResistanceHeader = "Comment,Magnetic Field (Oe),Bridge 1 Resistivity (Ohm)"
        let content = """
        [Header]
        TITLE, test
        [Data]
        \(noResistanceHeader)
        ,10000.0,1.0
        ,5000.0,0.9
        """
        let url = try fixture.write(name: "f.dat", content: content)

        let loaded = try PPMSDATLoader().load(fileURL: url)
        let column = AHEAxisDetector().yColumnName(from: loaded, bridgeIndex: 1)
        #expect(column == nil)

        // End-to-end: the selection is skipped with a warning, not silently accepted as data.
        let result = try IngestAHESelectionsUseCase().execute(
            selections: [.init(sampleKey: "S1", sourceFilePath: url.path, channel: .ch1, conditions: ["temperature": "80K"])]
        )
        #expect(result.series.isEmpty)
        #expect(!result.warnings.isEmpty)
    }

    @Test("Phase 4a: PPMSDATLoader row diagnostics reach AHE's warnings output")
    func loaderDiagnosticsReachAHEWarnings() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let url = try fixture.write(name: "f.dat", content: Fixtures.malformed)

        let result = try IngestAHESelectionsUseCase().execute(
            selections: [.init(sampleKey: "S1", sourceFilePath: url.path, channel: .ch1, conditions: ["temperature": "80K"])]
        )
        #expect(result.warnings.contains { $0.contains("expected") })
    }

    // MARK: J — malformed-row behavior remains compatible

    @Test("J: malformed rows are padded/truncated to column count, matching pre-migration tolerance, and are diagnosed")
    func malformedRowsRemainTolerant() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let url = try fixture.write(name: "f.dat", content: Fixtures.malformed)

        let loaded = try PPMSDATLoader().load(fileURL: url)
        #expect(loaded.rowCount == 3)
        #expect(loaded.diagnostics.count == 2)
        #expect(loaded.diagnostics.contains { $0.code == "malformedRow.tooFewFields" })
        #expect(loaded.diagnostics.contains { $0.code == "malformedRow.tooManyFields" })

        // Row 1 (index 1) was short by one field — the missing trailing "Bridge 1 Resistance"
        // value pads to "" -> NaN, so pairedValues (which requires both x and y numeric) still
        // drops it, matching the pre-migration AHEAxisDetector.pairedValues behavior exactly.
        let resistance = loaded.signals[8]
        #expect(resistance.values[1].isNaN)
    }

    // MARK: K / architecture guards — no second active AHE raw parser remains

    @Test("K: LoadedMeasurement/MeasurementColumn are defined in Domain/Measurement")
    func domainTypesLiveInDomain() throws {
        let domainDir = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/Domain/Measurement", isDirectory: true)
        #expect(!(try swiftFilesContaining(pattern: "struct LoadedMeasurement", under: domainDir)).isEmpty)
        #expect(!(try swiftFilesContaining(pattern: "struct MeasurementColumn", under: domainDir)).isEmpty)
    }

    @Test("K: raw PPMS file I/O occurs only in PPMSDATLoader")
    func rawFileIOOnlyInSharedLoader() throws {
        let useCasesDir = Self.projectRoot.appendingPathComponent("Sources/SpinLabApp/UseCases", isDirectory: true)
        let ioSites = try swiftFilesContaining(pattern: "String(contentsOf:", under: useCasesDir)
        #expect(!ioSites.contains("AHEDataParser.swift"),
                "AHEDataParser must no longer perform raw file I/O directly — it must delegate to PPMSDATLoader")
        #expect(!ioSites.contains("AHEAxisDetector.swift"),
                "AHEAxisDetector must not perform raw file I/O")
        #expect(!ioSites.contains("IngestAHESelectionsUseCase.swift"),
                "IngestAHESelectionsUseCase must not perform raw file I/O")
        #expect(ioSites.contains("PPMSDATLoader.swift"),
                "PPMSDATLoader must own raw file I/O for the shared PPMS .dat grammar")
    }

    @Test("K: PPMSDATLoader owns the single [Header]/[Data] detection for this grammar")
    func loaderOwnsHeaderDetection() throws {
        let loaderURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/PPMSDATLoader.swift")
        let loaderContents = try String(contentsOf: loaderURL, encoding: .utf8)
        #expect(loaderContents.contains("firstIndex(of: \"[Data]\")"),
                "PPMSDATLoader must own the single [Header]/[Data] detection for this grammar")
    }

    // Phase 3h: AHEDataParser/PPMSParsedFile were the pre-Phase-3f compatibility shim, kept alive
    // only for XYRotationDATParser. Once XY Rotation migrated (Phase 3h) to call PPMSDATLoader
    // directly, both types became dead and were deleted. This guards against reintroduction.
    @Test("K: AHEDataParser/PPMSParsedFile compatibility shim was removed, not reintroduced")
    func aheDataParserCompatibilityShimRemoved() throws {
        let adapterURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/AHEDataParser.swift")
        let structURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/Domain/PPMSParsedFile.swift")
        #expect(!FileManager.default.fileExists(atPath: adapterURL.path),
                "AHEDataParser.swift must not be reintroduced — all PPMS DAT consumers call PPMSDATLoader directly")
        #expect(!FileManager.default.fileExists(atPath: structURL.path),
                "PPMSParsedFile.swift must not be reintroduced — RawTable/LoadedMeasurement replace its role")
    }

    @Test("K: PPMSDATLoader does not depend on AHE/RT/XYRotation workflow types")
    func loaderHasNoWorkflowDependency() throws {
        let loaderURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/PPMSDATLoader.swift")
        let contents = try String(contentsOf: loaderURL, encoding: .utf8)
        let forbidden = ["AHEAxisDetector", "AHEDataParser", "IngestAHESelectionsUseCase",
                          "AHEIngestionResult", "RTPPMSDatParser", "XYRotationDATParser",
                          "XYRotationAngleSweep"]
        for name in forbidden {
            #expect(!contents.contains(name),
                    "PPMSDATLoader must not reference \(name) — it is a shared, format-only loader")
        }
    }

    @Test("K: unit conversion is absent from PPMSDATLoader")
    func loaderPerformsNoUnitConversion() throws {
        let loaderURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/PPMSDATLoader.swift")
        let contents = try String(contentsOf: loaderURL, encoding: .utf8)
        #expect(!contents.contains("WorkbenchMagneticFieldUnitConverter"),
                "PPMSDATLoader must not convert units — it only tags the source unit")
        #expect(!contents.contains("TemperatureUnitConverter"),
                "PPMSDATLoader must not convert units — it only tags the source unit")
    }

    @Test("K: AHE workflow layer may depend on LoadedMeasurement")
    func aheWorkflowMayDependOnLoadedMeasurement() throws {
        let detectorURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/AHEAxisDetector.swift")
        let contents = try String(contentsOf: detectorURL, encoding: .utf8)
        #expect(contents.contains("LoadedMeasurement"),
                "AHEAxisDetector is expected to consume LoadedMeasurement from the shared loader")
    }

    // MARK: - Helpers

    private func swiftFilesContaining(pattern: String, under dir: URL) throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }

        var matches: [String] = []
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if contents.contains(pattern) {
                matches.append(url.lastPathComponent)
            }
        }
        return matches
    }
}
