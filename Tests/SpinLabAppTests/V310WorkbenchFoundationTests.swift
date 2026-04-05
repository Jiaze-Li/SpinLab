import Foundation
import Testing
@testable import SpinLabApp

@Suite("V3.1.0 Workbench Foundation")
struct V310WorkbenchFoundationTests {
    @Test("schema round-trip for V3.1 contracts")
    func schemaRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1_712_146_400)
        let payload = WorkbenchPlotPayload(
            workflowID: "A",
            workflowDisplayName: "AHE",
            title: "AHE PN20 STO001",
            axisMapping: WorkbenchAxisMapping(xField: "field", yField: "rxy"),
            series: [
                WorkbenchPlotSeries(
                    label: "PN20 80K 30deg",
                    x: [0.0, 0.1],
                    y: [1.2, 1.3],
                    sourceRef: "batches/PN20/samples/PN20_STO001/measurements/A/a.dat"
                )
            ],
            semanticParams: ["normalization": "none"],
            styleParams: ["grid": "on", "theme": "default"]
        )
        let metric = WorkbenchMetricRecord(
            recordID: "record-1",
            sampleKey: "sid_7f8c3a",
            displayKey: "PN20||STO|001",
            workflowID: "A",
            metric: "Hc",
            value: 1.0,
            canonicalUnit: "T",
            displayUnitHint: "mT",
            conditions: ["device": "30deg", "temperature": "80K"],
            generatedAt: now,
            runID: "run-1",
            overrideInfo: WorkbenchMetricOverrideInfo(oldValue: 0.95, newValue: 1.0, reason: "manual correction", source: .manual, at: now)
        )
        let manifest = WorkbenchRunManifest(
            manifestID: "manifest-1",
            runID: "run-1",
            workflowID: "A",
            inputFiles: [
                "batches/PN20/samples/PN20_STO001/measurements/A/a.dat",
                "batches/PN20/samples/PN20_STO001/measurements/A/b.lvm"
            ],
            filters: ["sampleID": "sid_7f8c3a", "temperature": "80K"],
            axisMapping: WorkbenchAxisMapping(xField: "field", yField: "rxy"),
            semanticParams: ["normalization": "none"],
            outputImagePath: "analysis/workflows/A/charts/chart.png",
            generatedAt: now,
            appVersion: "3.1.0"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let decodedPayload = try decoder.decode(WorkbenchPlotPayload.self, from: encoder.encode(payload))
        let decodedMetric = try decoder.decode(WorkbenchMetricRecord.self, from: encoder.encode(metric))
        let decodedManifest = try decoder.decode(WorkbenchRunManifest.self, from: encoder.encode(manifest))

        #expect(decodedPayload == payload)
        #expect(decodedMetric == metric)
        #expect(decodedManifest == manifest)
    }

    @Test("chart identity is deterministic and style-independent")
    func chartIdentityDeterministic() {
        let payloadA = WorkbenchPlotPayload(
            workflowID: "A",
            workflowDisplayName: "AHE",
            title: "Chart A",
            axisMapping: WorkbenchAxisMapping(xField: "Field", yField: "Rxy"),
            series: [
                WorkbenchPlotSeries(label: "S1", x: [0], y: [1], sourceRef: "Batches\\PN20\\A.DAT"),
                WorkbenchPlotSeries(label: "S2", x: [0], y: [1], sourceRef: "batches/pn20/a.dat")
            ],
            semanticParams: ["normalization": "none"],
            styleParams: ["grid": "on"]
        )
        var payloadB = payloadA
        payloadB.styleParams = ["grid": "off"]
        payloadB.title = "Chart B"

        let keyA = WorkbenchChartIdentity.makeIdentityKey(from: payloadA)
        let keyB = WorkbenchChartIdentity.makeIdentityKey(from: payloadB)
        #expect(keyA == keyB)
    }

    @Test("metric identity normalizes condition key/value order and case")
    func metricIdentityNormalization() {
        let keyA = WorkbenchMetricIdentity.makeIdentityKey(
            sampleKey: "SID_001",
            workflowID: "A",
            metric: "Hc",
            conditions: ["Temperature": "80K", "Device": "30DEG"]
        )
        let keyB = WorkbenchMetricIdentity.makeIdentityKey(
            sampleKey: "sid_001",
            workflowID: "a",
            metric: "hc",
            conditions: ["device": "30deg", "temperature": "80k"]
        )
        #expect(keyA == keyB)
    }

    @Test("condition alias loader fails on unknown schema version")
    func aliasLoaderFailsOnUnknownSchemaVersion() throws {
        let loader = ConditionAliasConfigLoader(supportedSchemaVersion: 1)
        let raw = """
        {
          "schemaVersion": 2,
          "conditionAliases": {
            "angle": ["device"]
          }
        }
        """.data(using: .utf8)!

        do {
            _ = try loader.load(from: raw)
            Issue.record("Expected schema-version validation failure.")
        } catch let error as AppError {
            guard case .validation = error else {
                Issue.record("Expected AppError.validation, got \(error)")
                return
            }
            #expect(Bool(true))
        }
    }

    @Test("library path resolver round-trip and root escape rejection")
    func libraryPathResolverRoundTrip() throws {
        let fixture = try TempDirFixture()
        defer { fixture.cleanup() }

        let libraryRoot = fixture.rootURL.appending(path: "library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        let resolver = LibraryPathResolver(libraryRootURL: libraryRoot)

        let chartURL = libraryRoot.appending(path: "analysis/workflows/A/charts/chart.png")
        let relative = try resolver.relativePath(for: chartURL)
        #expect(relative == "analysis/workflows/A/charts/chart.png")
        let restored = try resolver.absoluteURL(for: relative)
        #expect(restored == chartURL.standardizedFileURL)

        do {
            _ = try resolver.absoluteURL(for: "../outside.json")
            Issue.record("Expected root-escape rejection.")
        } catch {
            #expect(Bool(true))
        }
    }

    @Test("atomic writer commits and overwrites target content")
    func atomicWriterCommitAndOverwrite() throws {
        let fixture = try TempDirFixture()
        defer { fixture.cleanup() }

        let writer = AtomicFileWriter()
        let targetURL = fixture.rootURL.appending(path: "artifacts/output.json")
        try writer.write(Data("v1".utf8), to: targetURL)
        let v1 = try Data(contentsOf: targetURL)
        #expect(String(decoding: v1, as: UTF8.self) == "v1")

        try writer.write(Data("v2".utf8), to: targetURL)
        let v2 = try Data(contentsOf: targetURL)
        #expect(String(decoding: v2, as: UTF8.self) == "v2")
    }
}

private struct TempDirFixture {
    let rootURL: URL
    private let fileManager: FileManager = .default

    init() throws {
        rootURL = fileManager.temporaryDirectory.appending(path: "spinlab-v310-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? fileManager.removeItem(at: rootURL)
    }
}
