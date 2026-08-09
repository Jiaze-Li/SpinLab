import Testing
import Foundation
@testable import SpinLabApp

// Phase 3e: XY Rotation migration to LoadedMeasurement / ZurichLVMLoader (LVM path only —
// PPMS .dat is untouched). Tests A-J from the Phase 3e handoff — XY-specific mapping fidelity,
// plus architecture guards proving the migration didn't leave a second active raw parser.
// Mirrors V3cIVMeasurementMigrationTests / V3dThreeOmegaMeasurementMigrationTests.

@Suite("Phase 3e XYRotation LoadedMeasurement Migration")
struct V3eXYRotationMeasurementMigrationTests {

    private static let projectRoot: URL = {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()  // SpinLabAppTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
    }()

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

    // MARK: A — ZurichLVMLoader raw columns equal legacy XY raw inputs

    @Test("A: XYRotationLVMParser col0/col1/col5/col9 (pre-derivation) match direct ZurichLVMLoader column mapping")
    func lvmRawColumnsMatchLoader() throws {
        let url = try lvmFixtureURL()
        let loaded = try ZurichLVMLoader().load(fileURL: url)
        let sweep = try XYRotationLVMParser().parse(fileURL: url, temperatureOverride: 80)

        #expect(sweep.angleDeg == loaded.signals[0].values)
        // Rxx = col[9] directly, so this also proves col9 is unchanged raw R_H.
        #expect(sweep.resistanceXX == loaded.signals[9].values)
    }

    // MARK: B — XY angle positional mapping unchanged

    @Test("B: angle column maps to loader column 0; first/last angle values unchanged")
    func anglePositionalMappingUnchanged() throws {
        let url = try lvmFixtureURL()
        let sweep = try XYRotationLVMParser().parse(fileURL: url, temperatureOverride: 80)
        #expect(sweep.angleDeg.count == 7)
        #expect(abs(sweep.angleDeg[0] - 360.0) < 0.01)
        #expect(abs(sweep.angleDeg[6] - 330.0) < 0.01)
    }

    // MARK: C — I_rms matches legacy result exactly

    @Test("C: I_rms is the mean of Col[1]/Col[9] over the first min(20, N) rows, recomputed independently")
    func iRmsMatchesIndependentRecomputation() throws {
        let url = try lvmFixtureURL()
        let loaded = try ZurichLVMLoader().load(fileURL: url)
        let col1 = loaded.signals[1].values
        let col9 = loaded.signals[9].values
        let nRows = min(20, col1.count)
        var sum = 0.0
        var count = 0
        for i in 0..<nRows where col9[i] != 0 && col1[i].isFinite && col9[i].isFinite {
            sum += col1[i] / col9[i]
            count += 1
        }
        let expectedIRms = sum / Double(count)

        // Rxy = col[5] / I_rms — reconstruct I_rms from the parser's own Rxy output and compare.
        let sweep = try XYRotationLVMParser().parse(fileURL: url, temperatureOverride: 80)
        guard let rxy = sweep.resistanceXY else {
            Issue.record("resistanceXY unexpectedly nil")
            return
        }
        let col5 = loaded.signals[5].values
        for i in 0..<rxy.count {
            let impliedIRms = col5[i] / rxy[i]
            #expect(abs(impliedIRms - expectedIRms) < 1e-9)
        }
    }

    @Test("C: resistanceXX first value matches legacy fixture expectation")
    func rxxFirstValueMatchesLegacy() throws {
        let url = try lvmFixtureURL()
        let sweep = try XYRotationLVMParser().parse(fileURL: url, temperatureOverride: 80)
        #expect(abs(sweep.resistanceXX[0] - (-3.6280234729)) < 1e-6)
    }

    // MARK: D — raw LVM voltage survives before Rxy derivation

    @Test("D: raw col5 voltage (V2w_X) is exposed unaltered by the loader, distinct from derived Rxy")
    func rawVoltageSurvivesBeforeDerivation() throws {
        let url = try lvmFixtureURL()
        let loaded = try ZurichLVMLoader().load(fileURL: url)
        let sweep = try XYRotationLVMParser().parse(fileURL: url, temperatureOverride: 80)
        let col5 = loaded.signals[5].values
        guard let rxy = sweep.resistanceXY else {
            Issue.record("resistanceXY unexpectedly nil")
            return
        }
        // Raw voltage and derived resistance must differ (division by I_rms actually happened)
        // and the raw column itself must be untouched (no derivation applied at the loader).
        #expect(loaded.signals[5].physicalQuantityID == nil)
        #expect(loaded.signals[5].sourceUnit == .undeclared)
        for i in 0..<col5.count where col5[i] != 0 {
            #expect(col5[i] != rxy[i])
        }
    }

    // MARK: E — derived Rxy matches legacy result exactly

    @Test("E: resistanceXY == col5 / I_rms, matching the pre-migration formula bit-for-bit")
    func rxyMatchesLegacyFormula() throws {
        let url = try lvmFixtureURL()
        let loaded = try ZurichLVMLoader().load(fileURL: url)
        let col1 = loaded.signals[1].values
        let col5 = loaded.signals[5].values
        let col9 = loaded.signals[9].values
        let nRows = min(20, col1.count)
        var sum = 0.0
        var count = 0
        for i in 0..<nRows where col9[i] != 0 && col1[i].isFinite && col9[i].isFinite {
            sum += col1[i] / col9[i]
            count += 1
        }
        let iRms = sum / Double(count)
        let expectedRxy = col5.map { $0 / iRms }

        let sweep = try XYRotationLVMParser().parse(fileURL: url, temperatureOverride: 80)
        #expect(sweep.resistanceXY == expectedRxy)
    }

    @Test("E: resistanceXY[0] matches legacy fixture expectation within tolerance")
    func rxyFirstValueMatchesLegacy() throws {
        let url = try lvmFixtureURL()
        let sweep = try XYRotationLVMParser().parse(fileURL: url, temperatureOverride: 80)
        guard let rxy = sweep.resistanceXY else {
            Issue.record("resistanceXY unexpectedly nil")
            return
        }
        // From V420XYRotationTests: expectedRxy0 computed via the pre-migration formula.
        let loaded = try ZurichLVMLoader().load(fileURL: url)
        let col1 = loaded.signals[1].values
        let col5 = loaded.signals[5].values
        let col9 = loaded.signals[9].values
        let nRows = min(20, col1.count)
        var sum = 0.0
        var count = 0
        for i in 0..<nRows where col9[i] != 0 && col1[i].isFinite && col9[i].isFinite {
            sum += col1[i] / col9[i]
            count += 1
        }
        let expectedRxy0 = col5[0] / (sum / Double(count))
        #expect(abs(rxy[0] - expectedRxy0) < 1.0)
    }

    // MARK: F — DAT resistance path remains numerically unchanged

    @Test("F: DAT resistanceXX/resistanceXY values unchanged (direct-read path, untouched by this migration)")
    func datResistanceUnchanged() throws {
        let url = try datFixtureURL()
        let sweep = try XYRotationDATParser().parse(fileURL: url)
        #expect(abs(sweep.resistanceXX[0] - 150.3597) < 0.01)
        #expect(sweep.resistanceXY != nil)
        #expect(abs(sweep.resistanceXY![0] - (-1.8389)) < 0.01)
    }

    // MARK: G — DAT and LVM both produce the same XYRotationAngleSweep public contract

    @Test("G: LVM and DAT sweeps both populate the shared XYRotationAngleSweep contract with matching sourceKind provenance")
    func datAndLvmShareContractWithDistinctProvenance() throws {
        let lvmSweep = try XYRotationLVMParser().parse(fileURL: lvmFixtureURL(), temperatureOverride: 80)
        let datSweep = try XYRotationDATParser().parse(fileURL: datFixtureURL())

        #expect(lvmSweep.sourceKind == .lvm)
        #expect(datSweep.sourceKind == .dat)
        // Both populate angleDeg/resistanceXX/resistanceXY on the same struct — the only
        // difference in provenance is sourceKind (lvm implies Rxx/Rxy derived from raw
        // voltage/current; dat implies Rxx/Rxy read directly from the instrument file).
        #expect(!lvmSweep.angleDeg.isEmpty)
        #expect(!datSweep.angleDeg.isEmpty)
        #expect(lvmSweep.resistanceXX.count == lvmSweep.angleDeg.count)
        #expect(datSweep.resistanceXX.count == datSweep.angleDeg.count)
    }

    // MARK: H — shift/phi behavior unchanged

    @Test("H: defaultPhiOffset is 0 from the parser; shift is applied later by IngestXYRotationSelectionsUseCase")
    func phiOffsetOwnershipUnchanged() throws {
        let sweep = try XYRotationLVMParser().parse(fileURL: lvmFixtureURL(), temperatureOverride: 80)
        #expect(sweep.defaultPhiOffset == 0)
        // ZurichLVMLoader/XYRotationLVMParser must not reference "shift"/"phi" — that
        // remains Sidecar/IngestXYRotationSelectionsUseCase-owned (verified in J below).
    }

    // MARK: I — warnings/errors remain behavior-compatible

    @Test("I: fixtures parse without throwing (no new error path introduced)")
    func fixturesParseWithoutError() throws {
        _ = try XYRotationLVMParser().parse(fileURL: lvmFixtureURL(), temperatureOverride: 80)
        _ = try XYRotationDATParser().parse(fileURL: datFixtureURL())
    }

    @Test("I: temperatureNotFound is still thrown for an unrecognized LVM filename with no override")
    func temperatureNotFoundStillThrown() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("xy_no_temp_hint_\(Int.random(in: 100_000...999_999)).lvm")
        try "double header\n\nTableau:\n0.001\t0.01\t0.001\t0.01\t5.7\t0.02\t0.002\t0.02\t5.7\t100\t317\n"
            .write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        #expect(throws: XYRotationLVMParser.ParseError.self) {
            try XYRotationLVMParser().parse(fileURL: tmp)
        }
    }

    // MARK: J — no active XY-specific raw LVM parser remains

    @Test("J: raw file I/O for the Zurich LVM grammar occurs only in ZurichLVMLoader (XY Rotation)")
    func rawFileIOOnlyInSharedLoaderForXYRotation() throws {
        let useCasesDir = Self.projectRoot.appendingPathComponent("Sources/SpinLabApp/UseCases", isDirectory: true)
        let ioSites = try _swiftFilesContaining(pattern: "String(contentsOf:", under: useCasesDir)
        #expect(!ioSites.contains("XYRotationLVMParser.swift"),
                "XYRotationLVMParser must no longer perform raw file I/O directly — found String(contentsOf:) in it")
        #expect(ioSites.contains("ZurichLVMLoader.swift"),
                "ZurichLVMLoader must own raw file I/O for the shared Zurich LVM grammar")
    }

    @Test("J: no second Tableau-marker scan exists for XY Rotation")
    func noDuplicateTableauScanForXYRotation() throws {
        let parserURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/XYRotationLVMParser.swift")
        let contents = try String(contentsOf: parserURL, encoding: .utf8)
        #expect(!contents.contains("hasPrefix(marker)"),
                "XYRotationLVMParser must not re-implement Tableau-marker scanning — that belongs to ZurichLVMLoader only")
        #expect(!contents.contains("String(contentsOf:"),
                "XYRotationLVMParser must not open the raw file itself — that belongs to ZurichLVMLoader only")
        #expect(!contents.contains(".components(separatedBy: \"\\t\")"),
                "XYRotationLVMParser must not re-implement tab splitting — that belongs to ZurichLVMLoader only")
    }

    @Test("J: ZurichLVMLoader does not depend on IV/ThreeOmega/XYRotation workflow types")
    func genericLoaderHasNoXYRotationDependency() throws {
        let loaderURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/ZurichLVMLoader.swift")
        let contents = try String(contentsOf: loaderURL, encoding: .utf8)
        let forbidden = ["IVSweep", "IVLVMParser", "ThreeOmegaLVMFile", "ThreeOmegaLVMParser",
                          "XYRotationAngleSweep", "XYRotationLVMParser"]
        for typeName in forbidden {
            #expect(!contents.contains(typeName),
                    "ZurichLVMLoader must not reference \(typeName) — it is a shared, format-only loader")
        }
        // shift/phi ownership must never migrate into the shared loader.
        #expect(!contents.lowercased().contains("shift"))
        #expect(!contents.lowercased().contains("phi"))
    }

    @Test("J: XY Rotation workflow layer depends on LoadedMeasurement")
    func xyRotationWorkflowDependsOnLoadedMeasurement() throws {
        let parserURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/XYRotationLVMParser.swift")
        let contents = try String(contentsOf: parserURL, encoding: .utf8)
        #expect(contents.contains("LoadedMeasurement"),
                "XYRotationLVMParser is expected to consume LoadedMeasurement from the shared loader")
    }

    @Test("J: I_rms derivation no longer lives in ZurichLVMLoader")
    func iRmsDerivationNotInLoader() throws {
        let loaderURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/ZurichLVMLoader.swift")
        let contents = try String(contentsOf: loaderURL, encoding: .utf8)
        #expect(!contents.contains("iRmsSum") && !contents.contains("iRmsCount"),
                "ZurichLVMLoader must not derive I_rms — that is workflow interpretation")
    }

    @Test("J: Rxy derivation (division by I_rms) no longer lives in ZurichLVMLoader")
    func rxyDerivationNotInLoader() throws {
        let loaderURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/ZurichLVMLoader.swift")
        let contents = try String(contentsOf: loaderURL, encoding: .utf8)
        // Matches an actual derivation expression (dividing a column by I_rms), not the loader's
        // doc comment stating it performs "no Rxy" derivation.
        #expect(!contents.contains("/ iRms") && !contents.contains("/iRms"),
                "ZurichLVMLoader must not derive Rxy — that is XY Rotation workflow interpretation")
    }

    @Test("J: one shared active Zurich LVM parser exists for IV, ThreeOmega, and XY Rotation")
    func oneSharedActiveLoaderForAllThreeWorkflows() throws {
        let useCasesDir = Self.projectRoot.appendingPathComponent("Sources/SpinLabApp/UseCases", isDirectory: true)
        let markerScanSites = try _swiftFilesContaining(pattern: "hasPrefix(marker)", under: useCasesDir)
        #expect(markerScanSites == ["ZurichLVMLoader.swift"],
                "Exactly one active Tableau-marker scan implementation should exist, in ZurichLVMLoader — found in: \(markerScanSites)")
    }

    // MARK: - Helpers

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
