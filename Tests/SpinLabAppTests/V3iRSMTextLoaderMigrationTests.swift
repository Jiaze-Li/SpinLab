import Testing
import Foundation
@testable import SpinLabApp

// Phase 3i: RSM migration to LoadedMeasurement / RSMTextLoader — the last raw-format vertical
// slice. Tests A-L from the Phase 3i handoff — loader H/K/L/detector fidelity unchanged,
// PhysicalQuantity typing, sourceUnit, malformed-row abort parity, recommendedView/
// isViewCompatible parity, and architecture guards proving the migration left exactly one active
// RSM grammar parser.

@Suite("Phase 3i RSMTextLoader Migration")
struct V3iRSMTextLoaderMigrationTests {

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
                path: "spinlab-v3i-rsmtext-\(UUID().uuidString)", directoryHint: .isDirectory
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
        static let basic = """
        # comment line, should be skipped
        ; another comment style
        H K L Detector
        0.0 0.0 1.0 100
        0.0 0.0 2.0 200
        0.0 0.0 3.0 300
        """

        static let synonymHeader = """
        h	k	l	Intensity
        1.0 0.0 2.0 10
        1.0 0.0 2.5 20
        """

        static let malformed = """
        H K L Counts
        0.0 0.0 1.0 100
        0.0 0.0 2.0
        0.0 0.0 3.0 300
        """
    }

    // MARK: A/B/C — H/K/L/detector values and header synonyms unchanged

    @Test("A/B/C: RSMTextLoader reproduces H/K/L/detector values and accepts header synonyms")
    func loaderValuesMatchLegacyParser() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let url = try fixture.write(name: "basic.rsm", content: Fixtures.basic)

        let measurement = try RSMTextLoader().load(fileURL: url)
        #expect(measurement.format == .rsmText)
        #expect(measurement.rowCount == 3)

        let legacy = try RSMDataParser.parse(text: Fixtures.basic, title: "t", sourceRef: url.path)
        #expect(legacy.points.map(\.h) == measurement.signals.first { $0.stableSourceKey == "H" }!.values)
        #expect(legacy.points.map(\.k) == measurement.signals.first { $0.stableSourceKey == "K" }!.values)
        #expect(legacy.points.map(\.l) == measurement.signals.first { $0.stableSourceKey == "L" }!.values)
        #expect(legacy.points.map(\.detector) == measurement.signals.first { $0.stableSourceKey == "detector" }!.values)
    }

    @Test("C: detector/intensity synonym resolution (Intensity, tab-separated) unchanged")
    func detectorSynonymResolved() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let url = try fixture.write(name: "synonym.rsm", content: Fixtures.synonymHeader)

        let measurement = try RSMTextLoader().load(fileURL: url)
        let detector = measurement.signals.first { $0.stableSourceKey == "detector" }!
        #expect(detector.values == [10, 20])
        #expect(detector.rawLabel == "Intensity")
    }

    // MARK: D/E — PhysicalQuantity typing

    @Test("D: H/K/L columns are typed .reciprocalH/.reciprocalK/.reciprocalL")
    func hklTypedAsReciprocal() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let url = try fixture.write(name: "basic.rsm", content: Fixtures.basic)

        let measurement = try RSMTextLoader().load(fileURL: url)
        #expect(measurement.signals.first { $0.stableSourceKey == "H" }!.physicalQuantityID == .reciprocalH)
        #expect(measurement.signals.first { $0.stableSourceKey == "K" }!.physicalQuantityID == .reciprocalK)
        #expect(measurement.signals.first { $0.stableSourceKey == "L" }!.physicalQuantityID == .reciprocalL)
    }

    @Test("E: detector column remains untyped (physicalQuantityID nil)")
    func detectorRemainsUntyped() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let url = try fixture.write(name: "basic.rsm", content: Fixtures.basic)

        let measurement = try RSMTextLoader().load(fileURL: url)
        #expect(measurement.signals.first { $0.stableSourceKey == "detector" }!.physicalQuantityID == nil)
    }

    // MARK: F — sourceUnit stays undeclared

    @Test("F: sourceUnit is .undeclared for H/K/L and detector — no fabricated r.l.u. unit")
    func sourceUnitUndeclared() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let url = try fixture.write(name: "basic.rsm", content: Fixtures.basic)

        let measurement = try RSMTextLoader().load(fileURL: url)
        for signal in measurement.signals {
            #expect(signal.sourceUnit == .undeclared)
        }
    }

    // MARK: G — malformed-row behavior unchanged (hard abort, not diagnostic-and-continue)

    @Test("G: malformed row aborts the whole load, matching pre-migration RSMDataParser behavior")
    func malformedRowAborts() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let url = try fixture.write(name: "malformed.rsm", content: Fixtures.malformed)

        #expect(throws: RSMTextLoader.LoadError.self) {
            try RSMTextLoader().load(fileURL: url)
        }
        #expect(throws: RSMDataParser.ParseError.self) {
            try RSMDataParser.parse(text: Fixtures.malformed)
        }
    }

    // MARK: H/I — recommendedView / isViewCompatible unchanged

    @Test("H/I: recommendedView and isViewCompatible unchanged for a fixed-L (HK) scan")
    func recommendedViewAndCompatibilityUnchanged() throws {
        let text = """
        H K L Detector
        0.0 0.0 1.0 10
        1.0 0.0 1.0 20
        1.0 1.0 1.0 30
        """
        let dataset = try RSMDataParser.parse(text: text)
        #expect(dataset.recommendedView == .hk)
        #expect(dataset.isViewCompatible(.hk) == true)
        #expect(dataset.isViewCompatible(.hl) == false)
        #expect(dataset.isViewCompatible(.kl) == false)
    }

    // MARK: K/L — architecture guards

    @Test("K: raw RSM file I/O occurs only in RSMTextLoader")
    func rawFileIOOnlyInSharedLoader() throws {
        let useCasesDir = Self.projectRoot.appendingPathComponent("Sources/SpinLabApp/UseCases", isDirectory: true)
        let ioSites = try swiftFilesContaining(pattern: "String(contentsOf", under: useCasesDir)
        #expect(!ioSites.contains("RSMDataParser.swift"),
                "RSMDataParser must no longer perform raw file I/O directly — it must delegate to RSMTextLoader")
        #expect(ioSites.contains("RSMTextLoader.swift"),
                "RSMTextLoader must own raw file I/O for the RSM text grammar")

        let workbenchDir = Self.projectRoot.appendingPathComponent("Sources/SpinLabApp/Features/Workbench", isDirectory: true)
        let workbenchIOSites = try swiftFilesContaining(pattern: "String(contentsOfFile", under: workbenchDir)
        #expect(!workbenchIOSites.contains("RSMWorkspaceStore.swift"),
                "RSMWorkspaceStore must no longer perform raw file I/O directly")
    }

    @Test("K: RSMTextLoader owns the single H/K/L header co-occurrence detection for this grammar")
    func loaderOwnsHeaderDetection() throws {
        let loaderURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/RSMTextLoader.swift")
        let loaderContents = try String(contentsOf: loaderURL, encoding: .utf8)
        #expect(loaderContents.contains("t.contains(\"H\") && t.contains(\"K\") && t.contains(\"L\")"),
                "RSMTextLoader must own the single H/K/L co-occurrence header detection for this grammar")

        let parserURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/RSMDataParser.swift")
        let parserContents = try String(contentsOf: parserURL, encoding: .utf8)
        #expect(!parserContents.contains("t.contains(\"H\")"),
                "RSMDataParser must not contain a second, duplicate header-detection implementation")
    }

    @Test("K: only one active RSM grammar parser remains (RSMDataParser delegates to RSMTextLoader)")
    func onlyOneActiveGrammarParser() throws {
        let parserURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/RSMDataParser.swift")
        let contents = try String(contentsOf: parserURL, encoding: .utf8)
        #expect(contents.contains("RSMTextLoader.parseMeasurement"),
                "RSMDataParser must delegate grammar parsing to RSMTextLoader, not reimplement it")
    }

    @Test("L: recommendedView/isViewCompatible logic does not live in RSMTextLoader (raw loader)")
    func viewLogicNotInRawLoader() throws {
        let loaderURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/RSMTextLoader.swift")
        let contents = try codeOnly(loaderURL)
        #expect(!contents.contains("recommendedView"),
                "RSMTextLoader must not know about view selection")
        #expect(!contents.contains("isViewCompatible"),
                "RSMTextLoader must not know about view compatibility")
        #expect(!contents.contains("RSMView"),
                "RSMTextLoader must not depend on RSMView — it owns text grammar only")
    }

    @Test("L: RSMTextLoader has no Workbench/heatmap dependency")
    func loaderHasNoWorkbenchDependency() throws {
        let loaderURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/RSMTextLoader.swift")
        let contents = try codeOnly(loaderURL)
        let forbidden = ["RSMWorkspaceStore", "RSMHeatmapPayloadBuilder", "HeatmapRenderPipeline", "CanonicalRSMDataset"]
        for name in forbidden {
            #expect(!contents.contains(name),
                    "RSMTextLoader must not reference \(name) — it is a shared, format-only loader")
        }
    }

    @Test("L: view interpretation (recommendedView/isViewCompatible) lives in RSMViewClassifier, not duplicated")
    func viewInterpretationLivesInClassifier() throws {
        let classifierURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/Workbench/V3/Heatmap/RSM/RSMViewClassifier.swift")
        #expect(FileManager.default.fileExists(atPath: classifierURL.path))
        let classifierContents = try String(contentsOf: classifierURL, encoding: .utf8)
        #expect(classifierContents.contains("static func recommendedView"))
        #expect(classifierContents.contains("static func isViewCompatible"))

        let datasetURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/Workbench/V3/Heatmap/RSM/CanonicalRSMDataset.swift")
        let datasetContents = try String(contentsOf: datasetURL, encoding: .utf8)
        #expect(!datasetContents.contains("allSatisfy"),
                "CanonicalRSMDataset must delegate axis-fixed logic to RSMViewClassifier, not reimplement it")
    }

    // MARK: - Helpers

    /// Reads a Swift source file and strips `//` line comments, so guard checks assert against
    /// actual code dependencies rather than false-positive matches inside doc comments that
    /// *explain* what the type does not depend on.
    private func codeOnly(_ url: URL) throws -> String {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return contents
            .components(separatedBy: "\n")
            .map { line -> String in
                guard let range = line.range(of: "//") else { return line }
                return String(line[line.startIndex..<range.lowerBound])
            }
            .joined(separator: "\n")
    }

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
