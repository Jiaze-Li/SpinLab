import Testing
import Foundation
@testable import SpinLabApp

// Phase 3h: XY Rotation PPMS .dat migration to the shared PPMSDATLoader (mirrors Phase 3f's AHE
// and Phase 3g's RT migrations). XYRotationDATParser no longer reaches PPMS data through
// AHEDataParser/PPMSParsedFile — both types were dead-code-removed once this was their last
// consumer. Tests A-K from the Phase 3h handoff: fidelity of angle/Rxx/Rxy/temperature/shift
// behavior, plus architecture guards proving exactly one active PPMS DAT raw parser remains
// repo-wide.

@Suite("Phase 3h XYRotation PPMSDATLoader Migration")
struct V3hXYRotationDATMigrationTests {

    private static let projectRoot: URL = {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()  // SpinLabAppTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
    }()

    private func datFixtureURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "xy_rotation_170K_sample", withExtension: "dat", subdirectory: "TestData/XYRotation") else {
            let bundleURL = Bundle.module.bundleURL
                .appendingPathComponent("TestData/XYRotation/xy_rotation_170K_sample.dat")
            guard FileManager.default.fileExists(atPath: bundleURL.path) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: bundleURL.path])
            }
            return bundleURL
        }
        return url
    }

    private func lvmFixtureURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "xy_rotation_80K_sample", withExtension: "lvm", subdirectory: "TestData/XYRotation") else {
            let bundleURL = Bundle.module.bundleURL
                .appendingPathComponent("TestData/XYRotation/xy_rotation_80K_sample.lvm")
            guard FileManager.default.fileExists(atPath: bundleURL.path) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: bundleURL.path])
            }
            return bundleURL
        }
        return url
    }

    // MARK: A — angle values unchanged

    @Test("A: angle values unchanged after migration")
    func angleValuesUnchanged() throws {
        let sweep = try XYRotationDATParser().parse(fileURL: try datFixtureURL())
        #expect(sweep.angleDeg.count > 5)
        #expect(abs(sweep.angleDeg[0] - 360.0) < 1.0)
    }

    // MARK: B — Rxx values unchanged

    @Test("B: Rxx (Bridge 2) values unchanged after migration")
    func rxxValuesUnchanged() throws {
        let sweep = try XYRotationDATParser().parse(fileURL: try datFixtureURL())
        #expect(abs(sweep.resistanceXX[0] - 150.3597) < 0.01)
        #expect(sweep.resistanceXX.count == sweep.angleDeg.count)
    }

    // MARK: C — Rxy values unchanged

    @Test("C: Rxy (Bridge 3) values unchanged after migration")
    func rxyValuesUnchanged() throws {
        let sweep = try XYRotationDATParser().parse(fileURL: try datFixtureURL())
        #expect(sweep.resistanceXY != nil)
        #expect(abs(sweep.resistanceXY![0] - (-1.8389)) < 0.01)
    }

    // MARK: D — Resistance-only (Phase 4a)

    @Test("D: Phase 4a — Bridge 2/3 Resistance (not Resistivity) is used for Rxx/Rxy")
    func resistanceOnlyUsedForRxxRxy() throws {
        // xy_rotation_170K_sample.dat declares both "Bridge 2 Resistivity (Ohm)" and
        // "Bridge 2 Resistance (Ohms)" (same for Bridge 3). This fixture's Resistance and
        // Resistivity columns happen to carry the same numeric value (150.3597 / -1.8389) — the
        // exact geometry-dependent coincidence Phase 4a says SpinLab must not rely on. This test
        // pins that XYRotationDATParser now reads the Resistance column specifically (verified via
        // the Resistivity-only-file rejection test below, which cannot coincidentally pass).
        let table = try PPMSDATLoader().loadRawTable(fileURL: try datFixtureURL())
        #expect(table.columnNames.contains("Bridge 2 Resistance (Ohms)"))
        #expect(table.columnNames.contains("Bridge 3 Resistance (Ohms)"))
        let sweep = try XYRotationDATParser().parse(fileURL: try datFixtureURL())
        #expect(abs(sweep.resistanceXX[0] - 150.3597) < 0.01)
        #expect(abs(sweep.resistanceXY![0] - (-1.8389)) < 0.01)
    }

    @Test("Phase 4a: Bridge 2 Resistivity-only file (no Resistance column) is rejected, not silently used")
    func resistivityOnlyFileRejectedForRxx() throws {
        let content = """
        [Header]
        FILEOPENTIME,01/01/2024

        [Data]
        Comment,Sample Position (deg),Bridge 2 Resistivity (Ohm)
        ,0.0,10.5
        ,90.0,11.5
        """
        let url = _writeTempDat(content)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: XYRotationDATParser.ParseError.self) {
            try XYRotationDATParser().parse(fileURL: url, temperatureOverride: 10)
        }
    }

    @Test("Phase 4a: Bridge 3 Resistivity-only (Resistance absent) leaves Rxy nil, not silently populated")
    func resistivityOnlyBridge3NotUsedForRxy() throws {
        let content = """
        [Header]
        FILEOPENTIME,01/01/2024

        [Data]
        Comment,Sample Position (deg),Bridge 2 Resistance (Ohms),Bridge 3 Resistivity (Ohm)
        ,0.0,10.5,99.0
        ,90.0,11.5,98.0
        """
        let url = _writeTempDat(content)
        defer { try? FileManager.default.removeItem(at: url) }

        let sweep = try XYRotationDATParser().parse(fileURL: url, temperatureOverride: 10)
        #expect(sweep.resistanceXX == [10.5, 11.5])
        #expect(sweep.resistanceXY == nil)
    }

    @Test("Phase 4a: PPMSDATLoader row diagnostics reach IngestXYRotationSelectionsUseCase's warnings output")
    func loaderDiagnosticsReachXYRotationWarnings() throws {
        let content = """
        [Header]

        [Data]
        Comment,Sample Position (deg),Bridge 2 Resistance (Ohms)
        ,0.0,10.5
        ,90.0
        """
        let url = _writeTempDat(content)
        defer { try? FileManager.default.removeItem(at: url) }

        let hit = WorkflowMeasurementSearchHit(
            sidecarPath: url.path + ".spinlab.json",
            measurementFilePath: url.path,
            sourceFilePath: url.path,
            workflowID: "XY Rotation",
            workflowDisplayName: "XY Rotation",
            workflowCanonicalID: "XY Rotation",
            batchID: "PN59",
            sampleKey: "PN59",
            sampleSubstrate: "",
            conditions: ["temperature": "10"],
            channels: [],
            appliedAt: .distantPast
        )
        let result = IngestXYRotationSelectionsUseCase().execute(hits: [hit])
        #expect(result.warnings.contains { $0.contains("expected") })
    }

    @Test("D: Rxy (Bridge 3) is optional — sweep succeeds without it, and resistanceXY stays nil")
    func rxyOptionalWhenAbsent() throws {
        let content = """
        [Header]
        FILEOPENTIME,01/01/2024

        [Data]
        Comment,Sample Position (deg),Bridge 2 Resistance (Ohms)
        ,0.0,10.5
        ,90.0,11.5
        """
        let url = _writeTempDat(content)
        defer { try? FileManager.default.removeItem(at: url) }

        let sweep = try XYRotationDATParser().parse(fileURL: url, temperatureOverride: 10)
        #expect(sweep.resistanceXY == nil)
    }

    // MARK: E — temperature resolution unchanged

    @Test("E: temperature override takes precedence over data column and filename")
    func temperatureOverridePrecedence() throws {
        let sweep = try XYRotationDATParser().parse(fileURL: try datFixtureURL(), temperatureOverride: 42.0)
        #expect(abs(sweep.temperatureK - 42.0) < 0.01)
    }

    @Test("E: temperature falls back to mean of Temperature (K) data column when no override given")
    func temperatureFallsBackToDataColumnMean() throws {
        let sweep = try XYRotationDATParser().parse(fileURL: try datFixtureURL())
        #expect(abs(sweep.temperatureK - 170.0) < 1.0)
    }

    @Test("E: temperature falls back to filename regex when no override and no data column present")
    func temperatureFallsBackToFilename() throws {
        let content = """
        [Header]

        [Data]
        Comment,Sample Position (deg),Bridge 2 Resistance (Ohms)
        ,0.0,10.5
        ,90.0,11.5
        """
        let url = _writeTempDat(content, name: "sample_55K_run1")
        defer { try? FileManager.default.removeItem(at: url) }

        let sweep = try XYRotationDATParser().parse(fileURL: url)
        #expect(abs(sweep.temperatureK - 55.0) < 0.01)
    }

    // MARK: F — sourceKind remains .dat

    @Test("F: sourceKind remains .dat for the PPMS direct-read path")
    func sourceKindRemainsDat() throws {
        let sweep = try XYRotationDATParser().parse(fileURL: try datFixtureURL())
        #expect(sweep.sourceKind == .dat)
    }

    // MARK: G — shift/phi behavior unchanged

    @Test("G: defaultPhiOffset is 0 from the parser; shift/phi stays IngestXYRotationSelectionsUseCase-owned")
    func phiOffsetOwnershipUnchanged() throws {
        let sweep = try XYRotationDATParser().parse(fileURL: try datFixtureURL())
        #expect(sweep.defaultPhiOffset == 0)
        // "shift" appears in XYRotationDATParser's doc comment (explaining ownership), which is
        // fine — the guard is that defaultPhiOffset is never assigned a non-zero/computed value.
        let parserURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/XYRotationDATParser.swift")
        let contents = try String(contentsOf: parserURL, encoding: .utf8)
        #expect(contents.contains("defaultPhiOffset: 0"),
                "XYRotationDATParser must hard-code defaultPhiOffset to 0 — shift application remains IngestXYRotationSelectionsUseCase-owned")
    }

    // MARK: H — DAT and LVM still produce the same public XYRotationAngleSweep contract

    @Test("H: DAT and LVM sweeps both populate the shared XYRotationAngleSweep contract with matching sourceKind provenance")
    func datAndLvmShareContract() throws {
        let datSweep = try XYRotationDATParser().parse(fileURL: try datFixtureURL())
        let lvmSweep = try XYRotationLVMParser().parse(fileURL: try lvmFixtureURL(), temperatureOverride: 80)

        #expect(datSweep.sourceKind == .dat)
        #expect(lvmSweep.sourceKind == .lvm)
        #expect(!datSweep.angleDeg.isEmpty)
        #expect(!lvmSweep.angleDeg.isEmpty)
        #expect(datSweep.resistanceXX.count == datSweep.angleDeg.count)
        #expect(lvmSweep.resistanceXX.count == lvmSweep.angleDeg.count)
    }

    // MARK: I — no AHEDataParser dependency remains

    @Test("I: XYRotationDATParser has no AHEDataParser dependency; AHEDataParser.swift no longer exists")
    func noAHEDataParserDependency() throws {
        let parserURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/XYRotationDATParser.swift")
        let contents = try String(contentsOf: parserURL, encoding: .utf8)
        // "AHEDataParser" appears in the file's doc comment (recording migration history), which
        // is fine — the guard is that no code actually constructs/calls it.
        #expect(!contents.contains("AHEDataParser()"),
                "XYRotationDATParser must not construct/call AHEDataParser")

        let adapterURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/AHEDataParser.swift")
        #expect(!FileManager.default.fileExists(atPath: adapterURL.path),
                "AHEDataParser.swift should have been deleted once XY Rotation was its last consumer")
    }

    // MARK: J — no PPMSParsedFile dependency remains

    @Test("J: XYRotationDATParser has no PPMSParsedFile dependency; PPMSParsedFile.swift no longer exists")
    func noPPMSParsedFileDependency() throws {
        let parserURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/XYRotationDATParser.swift")
        let contents = try String(contentsOf: parserURL, encoding: .utf8)
        // "PPMSParsedFile" appears in the file's doc comment (recording migration history), which
        // is fine — the guard is that no code actually declares/uses the type.
        #expect(!contents.contains("-> PPMSParsedFile") && !contents.contains(": PPMSParsedFile"),
                "XYRotationDATParser must not declare or use the PPMSParsedFile type")

        let structURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/Domain/PPMSParsedFile.swift")
        #expect(!FileManager.default.fileExists(atPath: structURL.path),
                "PPMSParsedFile.swift should have been deleted once it became dead code")
    }

    // MARK: K — only one active PPMS DAT raw parser remains repo-wide

    @Test("K: raw PPMS file I/O for XY Rotation occurs only through PPMSDATLoader")
    func rawFileIOOnlyInSharedLoaderForXYRotation() throws {
        let useCasesDir = Self.projectRoot.appendingPathComponent("Sources/SpinLabApp/UseCases", isDirectory: true)
        let ioSites = try _swiftFilesContaining(pattern: "String(contentsOf:", under: useCasesDir)
        #expect(!ioSites.contains("XYRotationDATParser.swift"),
                "XYRotationDATParser must no longer perform raw file I/O directly — it must delegate to PPMSDATLoader")
        #expect(ioSites.contains("PPMSDATLoader.swift"),
                "PPMSDATLoader must own raw file I/O for the shared PPMS .dat grammar")
    }

    @Test("K: XYRotationDATParser no longer performs [Header]/[Data] grammar detection itself")
    func noDuplicateHeaderScanForXYRotation() throws {
        let parserURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/XYRotationDATParser.swift")
        let contents = try String(contentsOf: parserURL, encoding: .utf8)
        #expect(!contents.contains("firstIndex(of: \"[Data]\")"),
                "XYRotationDATParser must not re-implement [Header]/[Data] detection — that belongs to PPMSDATLoader only")
        #expect(contents.contains("PPMSDATLoader"),
                "XYRotationDATParser must delegate raw parsing to PPMSDATLoader")
        #expect(contents.contains("PPMSDATLoader().loadRawTable"),
                "XYRotationDATParser is expected to consume PPMSDATLoader.loadRawTable directly")
    }

    @Test("K: PPMSDATLoader does not depend on XY Rotation workflow types (Bridge 2/3 -> Rxx/Rxy interpretation stays out)")
    func loaderHasNoXYRotationDependency() throws {
        let loaderURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/PPMSDATLoader.swift")
        let contents = try String(contentsOf: loaderURL, encoding: .utf8)
        let forbidden = ["XYRotationDATParser", "XYRotationAngleSweep", "IngestXYRotationSelectionsUseCase"]
        for name in forbidden {
            #expect(!contents.contains(name),
                    "PPMSDATLoader must not reference \(name) — Bridge 2/3 -> Rxx/Rxy interpretation is XY Rotation workflow-owned")
        }
    }

    @Test("K: exactly one active PPMS DAT grammar parser exists repo-wide")
    func exactlyOnePPMSDATGrammarParser() throws {
        let sourcesDir = Self.projectRoot.appendingPathComponent("Sources/SpinLabApp", isDirectory: true)
        let grammarSites = try _swiftFilesContaining(pattern: "firstIndex(of: \"[Data]\")", under: sourcesDir)
        #expect(grammarSites == ["PPMSDATLoader.swift"],
                "Exactly one active PPMS [Header]/[Data] grammar implementation should exist, in PPMSDATLoader — found in: \(grammarSites)")
    }

    // MARK: - Helpers

    private func _writeTempDat(_ content: String, name: String = "test") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(name)_\(UUID().uuidString).dat")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func _swiftFilesContaining(pattern: String, under dir: URL) throws -> [String] {
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
        return matches.sorted()
    }
}
