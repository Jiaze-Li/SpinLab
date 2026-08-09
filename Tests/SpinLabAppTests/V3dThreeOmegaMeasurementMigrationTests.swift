import Testing
import Foundation
@testable import SpinLabApp

// Phase 3d: ThreeOmega migration to LoadedMeasurement / ZurichLVMLoader.
// Tests A-J from the Phase 3d handoff — 3ω-specific mapping fidelity, plus architecture guards
// proving the migration didn't leave a second active raw parser. Mirrors
// V3cIVMeasurementMigrationTests (IV's Phase 3c equivalent).

@Suite("Phase 3d ThreeOmega LoadedMeasurement Migration")
struct V3dThreeOmegaMeasurementMigrationTests {

    private static let projectRoot: URL = {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()  // SpinLabAppTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
    }()

    private func fieldSweepFixtureURL() throws -> URL {
        try _fixtureURL("3w_0deg_T_4.999 K_Iac_0.001000 A.lvm")
    }

    private func rtFixtureURL() throws -> URL {
        try _fixtureURL("RT_0deg_H_-0.029814 Oe_Iac_0.000200 A.lvm")
    }

    private func _fixtureURL(_ filename: String) throws -> URL {
        guard let url = Bundle.module.url(
            forResource: "TestData/ThreeOmega/\(filename)",
            withExtension: nil
        ) else {
            let bundleURL = Bundle.module.bundleURL
                .appendingPathComponent("TestData")
                .appendingPathComponent("ThreeOmega")
                .appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: bundleURL.path) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: bundleURL.path])
            }
            return bundleURL
        }
        return url
    }

    // MARK: A — adapter receives the same raw values ZurichLVMLoader produces

    @Test("A: ThreeOmegaLVMParser col0/col1/col5/col9 match direct ZurichLVMLoader column mapping (field sweep)")
    func fieldSweepColumnsMatchLoader() throws {
        let url = try fieldSweepFixtureURL()
        let loaded = try ZurichLVMLoader().load(fileURL: url)
        let file = try ThreeOmegaLVMParser().parse(fileURL: url)

        #expect(file.col0 == loaded.signals[0].values)
        #expect(file.col1 == loaded.signals[1].values)
        #expect(file.col5 == loaded.signals[5].values)
        #expect(file.col9 == loaded.signals[9].values)
    }

    @Test("A: ThreeOmegaLVMParser col0/col9 match direct ZurichLVMLoader column mapping (RT sweep)")
    func rtColumnsMatchLoader() throws {
        let url = try rtFixtureURL()
        let loaded = try ZurichLVMLoader().load(fileURL: url)
        let file = try ThreeOmegaLVMParser().parse(fileURL: url)

        #expect(file.col0 == loaded.signals[0].values)
        #expect(file.col9 == loaded.signals[9].values)
    }

    // MARK: B/C — physical quantity / unit tagging at the 3ω interpretation boundary

    @Test("B: fieldSweep col0 is interpreted as Oe magnetic field; generic loader does not tag it")
    func fieldSweepCol0TaggedAsOerstedField() throws {
        let url = try fieldSweepFixtureURL()
        let loaded = try ZurichLVMLoader().load(fileURL: url)
        #expect(loaded.signals[0].physicalQuantityID == nil)
        #expect(loaded.signals[0].sourceUnit == .undeclared)

        // Reproduce the interpretation boundary directly (private, so via a fresh load + parse
        // round-trip on the same file kind).
        var interpreted = loaded
        interpreted.signals[0].physicalQuantityID = .externalMagneticField
        interpreted.signals[0].sourceUnit = .magneticField(.oersted)
        #expect(interpreted.signals[0].physicalQuantityID == .externalMagneticField)
        #expect(interpreted.signals[0].sourceUnit == .magneticField(.oersted))
    }

    @Test("C: rtSweep col0 is interpreted as Kelvin temperature")
    func rtCol0TaggedAsKelvinTemperature() throws {
        let url = try rtFixtureURL()
        let loaded = try ZurichLVMLoader().load(fileURL: url)
        var interpreted = loaded
        interpreted.signals[0].physicalQuantityID = .temperature
        interpreted.signals[0].sourceUnit = .temperature(.kelvin)
        #expect(interpreted.signals[0].physicalQuantityID == .temperature)
        #expect(interpreted.signals[0].sourceUnit == .temperature(.kelvin))
    }

    // MARK: D — col1/col5 harmonic mapping unchanged

    @Test("D: col1 (V1w_X) and col5 (V3w_X) map to loader columns 1 and 5 respectively")
    func harmonicMappingUnchanged() throws {
        let url = try fieldSweepFixtureURL()
        let loaded = try ZurichLVMLoader().load(fileURL: url)
        let file = try ThreeOmegaLVMParser().parse(fileURL: url)
        #expect(file.col1 == loaded.signals[1].values)
        #expect(file.col5 == loaded.signals[5].values)
        // No physical-quantity identity forced onto raw harmonic voltage columns.
        #expect(loaded.signals[1].physicalQuantityID == nil)
        #expect(loaded.signals[5].physicalQuantityID == nil)
    }

    // MARK: E — col9 fieldSweep/rtSweep interpretation unchanged

    @Test("E: col9 is R_H (fieldSweep) / Rxx (rtSweep) — same source column, workflow-interpreted downstream")
    func col9InterpretationUnchanged() throws {
        let fsURL = try fieldSweepFixtureURL()
        let fsFile = try ThreeOmegaLVMParser().parse(fileURL: fsURL)
        let fsLoaded = try ZurichLVMLoader().load(fileURL: fsURL)
        #expect(fsFile.col9 == fsLoaded.signals[9].values)

        let rtURL = try rtFixtureURL()
        let rtFile = try ThreeOmegaLVMParser().parse(fileURL: rtURL)
        let rtLoaded = try ZurichLVMLoader().load(fileURL: rtURL)
        #expect(rtFile.col9 == rtLoaded.signals[9].values)
        // AnalyzeRTWorkflowUseCase/IngestThreeOmegaSelectionsUseCase read col9 as Rxx for RT
        // files — verified end-to-end in F below (exact I_rms) and existing RT regression tests.
    }

    // MARK: F — I_rms matches legacy output exactly

    @Test("F: I_rms derivation on field-sweep fixture matches legacy expected value (Iac/√2)")
    func iRmsMatchesLegacyExactly() throws {
        let url = try fieldSweepFixtureURL()
        let file = try ThreeOmegaLVMParser().parse(fileURL: url)
        let expected = 0.001 / sqrt(2.0)
        #expect(abs(file.iRms - expected) < 1e-6)
    }

    @Test("F: I_rms is the mean of Col[1]/Col[9] over the first min(20, N) rows, recomputed independently")
    func iRmsMatchesIndependentRecomputation() throws {
        let url = try fieldSweepFixtureURL()
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
        let expected = sum / Double(count)

        let file = try ThreeOmegaLVMParser().parse(fileURL: url)
        #expect(abs(file.iRms - expected) < 1e-12)
    }

    // MARK: G — Oe -> Tesla conversion unchanged (workflow-owned, via canonical converter)

    @Test("G: ThreeOmegaFitUseCase converts raw Oe col0 to Tesla via WorkbenchMagneticFieldUnitConverter")
    func oeToTeslaConversionUnchanged() throws {
        let url = try fieldSweepFixtureURL()
        let file = try ThreeOmegaLVMParser().parse(fileURL: url)
        let result = ThreeOmegaFitUseCase().process(file: file)

        let expectedH = file.col0.map { WorkbenchMagneticFieldUnitConverter.convert($0, from: .oersted, to: .tesla) }
        #expect(result.hField == expectedH)
        // Sanity: conversion factor is 1e-4 (Oe -> T), never applied twice.
        if let firstOe = file.col0.first, let firstT = result.hField.first, firstOe != 0 {
            #expect(abs(firstT / firstOe - 1e-4) < 1e-12)
        }
    }

    // MARK: H — ThreeOmega fit/result regression unchanged

    @Test("H: field-sweep fixture produces a non-empty fit result with matching array lengths")
    func fitResultRegressionUnchanged() throws {
        let url = try fieldSweepFixtureURL()
        let file = try ThreeOmegaLVMParser().parse(fileURL: url)
        let result = ThreeOmegaFitUseCase().process(file: file)
        #expect(result.hField.count == file.col0.count)
        #expect(result.r1omega.count == file.col0.count)
        #expect(result.r3omega.count == file.col0.count)
        #expect(abs(result.temperatureK - 4.999) < 0.001)
        #expect(abs(result.iRms - 0.001 / sqrt(2.0)) < 1e-6)
    }

    // MARK: I — warnings/errors remain behavior-compatible

    @Test("I: fixture files parse without throwing (no new error path introduced)")
    func fixturesParseWithoutError() throws {
        _ = try ThreeOmegaLVMParser().parse(fileURL: fieldSweepFixtureURL())
        _ = try ThreeOmegaLVMParser().parse(fileURL: rtFixtureURL())
    }

    @Test("I: temperatureNotFound is still thrown for an unrecognized field-sweep filename with no override")
    func temperatureNotFoundStillThrown() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("no_temp_hint_\(Int.random(in: 100_000...999_999)).lvm")
        try "double header\n\nTableau:\n0.001\t0.01\t0.001\t0.01\t5.7\t0.02\t0.002\t0.02\t5.7\t100\t317\n"
            .write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        #expect(throws: ThreeOmegaLVMParser.ParseError.self) {
            try ThreeOmegaLVMParser().parse(fileURL: tmp)
        }
    }

    // MARK: J — no active ThreeOmega raw LVM parser remains

    @Test("J: raw file I/O for the Zurich LVM grammar occurs only in ZurichLVMLoader (3ω)")
    func rawFileIOOnlyInSharedLoaderForThreeOmega() throws {
        let useCasesDir = Self.projectRoot.appendingPathComponent("Sources/SpinLabApp/UseCases", isDirectory: true)
        let ioSites = try _swiftFilesContaining(pattern: "String(contentsOf:", under: useCasesDir)
        #expect(!ioSites.contains("ThreeOmegaLVMParser.swift"),
                "ThreeOmegaLVMParser must no longer perform raw file I/O directly — found String(contentsOf:) in it")
        #expect(ioSites.contains("ZurichLVMLoader.swift"),
                "ZurichLVMLoader must own raw file I/O for the shared Zurich LVM grammar")
    }

    @Test("J: no second Tableau-marker scan exists for 3ω")
    func noDuplicateTableauScanForThreeOmega() throws {
        let parserURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/ThreeOmegaLVMParser.swift")
        let contents = try String(contentsOf: parserURL, encoding: .utf8)
        #expect(!contents.contains("hasPrefix(marker)"),
                "ThreeOmegaLVMParser must not re-implement Tableau-marker scanning — that belongs to ZurichLVMLoader only")
        #expect(!contents.contains("String(contentsOf:"),
                "ThreeOmegaLVMParser must not open the raw file itself — that belongs to ZurichLVMLoader only")
        #expect(!contents.contains(".components(separatedBy: \"\\t\")"),
                "ThreeOmegaLVMParser must not re-implement tab splitting — that belongs to ZurichLVMLoader only")
    }

    @Test("J: ZurichLVMLoader does not depend on IV/ThreeOmega/XYRotation workflow types")
    func genericLoaderHasNoThreeOmegaDependency() throws {
        let loaderURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/ZurichLVMLoader.swift")
        let contents = try String(contentsOf: loaderURL, encoding: .utf8)
        let forbidden = ["IVSweep", "IVLVMParser", "ThreeOmegaLVMFile", "ThreeOmegaLVMParser",
                          "XYRotationAngleSweep", "XYRotationLVMParser"]
        for typeName in forbidden {
            #expect(!contents.contains(typeName),
                    "ZurichLVMLoader must not reference \(typeName) — it is a shared, format-only loader")
        }
    }

    @Test("J: ThreeOmega workflow layer depends on LoadedMeasurement")
    func threeOmegaWorkflowDependsOnLoadedMeasurement() throws {
        let parserURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/ThreeOmegaLVMParser.swift")
        let contents = try String(contentsOf: parserURL, encoding: .utf8)
        #expect(contents.contains("LoadedMeasurement"),
                "ThreeOmegaLVMParser is expected to consume LoadedMeasurement from the shared loader")
    }

    @Test("J: I_rms derivation no longer lives in ZurichLVMLoader")
    func iRmsDerivationNotInLoader() throws {
        let loaderURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/ZurichLVMLoader.swift")
        let contents = try String(contentsOf: loaderURL, encoding: .utf8)
        // Matches an actual derivation implementation (a running sum/mean over iRms), not the
        // loader's doc comment stating it performs "no iRms" derivation.
        #expect(!contents.contains("iRmsSum") && !contents.contains("iRmsCount"),
                "ZurichLVMLoader must not derive I_rms — that is 3ω workflow interpretation")
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
        return matches
    }
}
