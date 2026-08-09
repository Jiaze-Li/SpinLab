import Testing
import Foundation
@testable import SpinLabApp

// Phase 3c: LoadedMeasurement foundation + IV vertical slice.
// Tests E, F, G, H, J from the Phase 3c handoff — IV-specific mapping fidelity, plus
// architecture guards proving the migration didn't leave a second active raw parser.

@Suite("Phase 3c IV LoadedMeasurement Migration")
struct V3cIVMeasurementMigrationTests {

    private static let projectRoot: URL = {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()  // SpinLabAppTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
    }()

    private func ivXFixtureURL() -> URL? {
        Bundle.module.url(forResource: "iv_x_dominant_293K", withExtension: "lvm", subdirectory: "TestData/IV")
    }

    // MARK: E — IV mapping reconstructs exactly the old IVSweep arrays

    @Test("E: IVLVMParser output matches direct ZurichLVMLoader column mapping")
    func ivMappingMatchesLoadedMeasurementColumns() throws {
        guard let url = ivXFixtureURL() else {
            Issue.record("IV fixture not found at TestData/IV/iv_x_dominant_293K.lvm")
            return
        }
        let loaded = try ZurichLVMLoader().load(fileURL: url)
        let sweep = try IVLVMParser().parse(fileURL: url, temperatureOverride: 293)

        #expect(sweep.current == loaded.signals[0].values)
        #expect(sweep.ch1X == loaded.signals[1].values)
        #expect(sweep.ch1Y == loaded.signals[2].values)
        #expect(sweep.ch2X == loaded.signals[5].values)
        #expect(sweep.ch2Y == loaded.signals[6].values)
    }

    @Test("E: IV workflow tags col0 as .current in Amperes; generic loader does not")
    func ivWorkflowTagsCurrentUnit() throws {
        guard let url = ivXFixtureURL() else { return }
        let loaded = try ZurichLVMLoader().load(fileURL: url)
        #expect(loaded.signals[0].physicalQuantityID == nil)
        #expect(loaded.signals[0].sourceUnit == .undeclared)
        // IVCurrentBasis (peak/RMS) stays entirely separate from this unit tag — untouched here.
    }

    // MARK: F — optional audit columns remain equivalent

    @Test("F: optional audit arrays (firstR/firstTheta/secondR/secondTheta/firstRH/frequencyAfter) match loader columns 3,4,7,8,9,10")
    func auditColumnsMatchLoader() throws {
        guard let url = ivXFixtureURL() else { return }
        let loaded = try ZurichLVMLoader().load(fileURL: url)
        let sweep = try IVLVMParser().parse(fileURL: url, temperatureOverride: 293)

        #expect(sweep.firstR == loaded.signals[3].values)
        #expect(sweep.firstTheta == loaded.signals[4].values)
        #expect(sweep.secondR == loaded.signals[7].values)
        #expect(sweep.secondTheta == loaded.signals[8].values)
        #expect(sweep.firstRH == loaded.signals[9].values)
        #expect(sweep.frequencyAfter == loaded.signals[10].values)
    }

    // MARK: G — channel-dominance behavior unchanged (regression via existing use case entry point)

    @Test("G: channel-dominance computation is unaffected by the migration")
    func channelDominanceUnaffected() throws {
        guard let url = ivXFixtureURL() else { return }
        let sweep = try IVLVMParser().parse(fileURL: url, temperatureOverride: 293)
        let state = IngestIVSelectionsUseCase()._computeChannelState(x: sweep.ch1X, y: sweep.ch1Y)
        #expect(state.autoComponent == .x)
        #expect(state.confidence > 1.0)
    }

    // MARK: H — IVCurrentBasis behavior unchanged

    @Test("H: IVCurrentBasis scale factors and axis labels are untouched by this migration")
    func currentBasisUnchanged() {
        #expect(IVCurrentBasis.peak.scaleFactor == 1000.0)
        #expect(abs(IVCurrentBasis.rms.scaleFactor - 1000.0 / sqrt(2.0)) < 1e-12)
        #expect(IVCurrentBasis.peak.displayName == "Peak")
        #expect(IVCurrentBasis.rms.displayName == "RMS")
    }

    // MARK: J — no duplicate IV raw-file parser remains

    @Test("J: LoadedMeasurement/MeasurementColumn are defined in Domain/Measurement")
    func domainTypesLiveInDomain() throws {
        let domainDir = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/Domain/Measurement", isDirectory: true)
        let loadedMeasurement = try swiftFilesContaining(pattern: "struct LoadedMeasurement", under: domainDir)
        #expect(!loadedMeasurement.isEmpty,
                "LoadedMeasurement must be defined in Sources/SpinLabApp/Domain/Measurement/")
        let measurementColumn = try swiftFilesContaining(pattern: "struct MeasurementColumn", under: domainDir)
        #expect(!measurementColumn.isEmpty,
                "MeasurementColumn must be defined in Sources/SpinLabApp/Domain/Measurement/")
    }

    @Test("J: raw file I/O for the Zurich LVM grammar occurs only in ZurichLVMLoader")
    func rawFileIOOnlyInSharedLoader() throws {
        let useCasesDir = Self.projectRoot.appendingPathComponent("Sources/SpinLabApp/UseCases", isDirectory: true)
        let ioSites = try swiftFilesContaining(pattern: "String(contentsOf:", under: useCasesDir)
        #expect(!ioSites.contains("IVLVMParser.swift"),
                "IVLVMParser must no longer perform raw file I/O directly — found String(contentsOf:) in it")
        #expect(ioSites.contains("ZurichLVMLoader.swift"),
                "ZurichLVMLoader must own raw file I/O for the shared Zurich LVM grammar")
    }

    @Test("J: no second Tableau-marker scan exists for IV")
    func noDuplicateTableauScanForIV() throws {
        // IVLVMParser legitimately keeps a `marker: String = "Tableau:"` default it threads
        // through to ZurichLVMLoader (API compatibility) — that is configuration, not detection
        // logic. What must NOT exist a second time is the actual scan: iterating lines looking
        // for `hasPrefix(marker)` / the numeric-first-field fallback scan.
        let ivParserURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/IVLVMParser.swift")
        let contents = try String(contentsOf: ivParserURL, encoding: .utf8)
        #expect(!contents.contains("hasPrefix(marker)"),
                "IVLVMParser must not re-implement Tableau-marker scanning — that belongs to ZurichLVMLoader only")
        #expect(!contents.contains("String(contentsOf:"),
                "IVLVMParser must not open the raw file itself — that belongs to ZurichLVMLoader only")

        let loaderURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/ZurichLVMLoader.swift")
        let loaderContents = try String(contentsOf: loaderURL, encoding: .utf8)
        #expect(loaderContents.contains("hasPrefix(marker)"),
                "ZurichLVMLoader must own the single Tableau-marker detection for this grammar")
    }

    @Test("J: ZurichLVMLoader does not depend on IV/ThreeOmega/XYRotation workflow types")
    func genericLoaderHasNoWorkflowDependency() throws {
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

    @Test("J: IV workflow layer may depend on LoadedMeasurement")
    func ivWorkflowMayDependOnLoadedMeasurement() throws {
        let ivParserURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/IVLVMParser.swift")
        let contents = try String(contentsOf: ivParserURL, encoding: .utf8)
        #expect(contents.contains("LoadedMeasurement"),
                "IVLVMParser is expected to consume LoadedMeasurement from the shared loader")
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
