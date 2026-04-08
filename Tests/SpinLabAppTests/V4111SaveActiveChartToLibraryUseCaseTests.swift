import Foundation
import Testing
@testable import SpinLabApp

@Suite("SaveActiveChartToLibraryUseCase (v4.1.11)")
struct V4111SaveActiveChartToLibraryUseCaseTests {

    private let sut = SaveActiveChartToLibraryUseCase()

    private func tmpDir(_ tag: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "v4111-\(tag)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func samplePayload(sourceRefs: [String?] = ["/fake/file1.lvm"]) -> WorkbenchPlotPayload {
        WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: "Test",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: sourceRefs.map {
                WorkbenchPlotSeries(label: "s", x: [], y: [], sourceRef: $0)
            },
            semanticParams: ["device": "D1"]
        )
    }

    // MARK: - Validation failures

    @Test func emptyLibraryRootPath_fails() {
        let input = SaveActiveChartInput(
            png: Data([0xFF]),
            payload: samplePayload(),
            sampleKeys: ["SK"],
            libraryRootPath: ""
        )
        if case .failure(let msg) = sut.execute(input: input) {
            #expect(msg.contains("Library root path"))
        } else {
            Issue.record("Expected .failure for empty libraryRootPath")
        }
    }

    @Test func missingSourceRef_fails() {
        let input = SaveActiveChartInput(
            png: Data([0xFF]),
            payload: samplePayload(sourceRefs: [nil]),
            sampleKeys: ["SK"],
            libraryRootPath: "/tmp"
        )
        if case .failure(let msg) = sut.execute(input: input) {
            #expect(msg.contains("sourceRef"))
        } else {
            Issue.record("Expected .failure for missing sourceRef")
        }
    }

    @Test func emptySourceRef_fails() {
        let input = SaveActiveChartInput(
            png: Data([0xFF]),
            payload: samplePayload(sourceRefs: [""]),
            sampleKeys: ["SK"],
            libraryRootPath: "/tmp"
        )
        if case .failure(let msg) = sut.execute(input: input) {
            #expect(msg.contains("sourceRef"))
        } else {
            Issue.record("Expected .failure for empty sourceRef")
        }
    }

    @Test func emptySampleKeys_fails() {
        let input = SaveActiveChartInput(
            png: Data([0xFF]),
            payload: samplePayload(),
            sampleKeys: [],
            libraryRootPath: "/tmp"
        )
        if case .failure(let msg) = sut.execute(input: input) {
            #expect(msg.contains("sample keys"))
        } else {
            Issue.record("Expected .failure for empty sampleKeys")
        }
    }

    @Test func metricSampleKeyNotInSampleKeys_fails() {
        let input = SaveActiveChartInput(
            png: Data([0xFF]),
            payload: samplePayload(),
            sampleKeys: ["SK-A"],
            libraryRootPath: "/tmp",
            metrics: [
                PendingMetricEntry(sampleKey: "SK-B", metric: "Hc", value: 0.1, canonicalUnit: "T", conditions: [:])
            ]
        )
        if case .failure(let msg) = sut.execute(input: input) {
            #expect(msg.contains("not in sampleKeys"))
        } else {
            Issue.record("Expected .failure for metric sampleKey mismatch")
        }
    }

    // MARK: - Success paths

    @Test func chartOnly_succeeds() throws {
        let root = try tmpDir("chartOnly")
        defer { try? FileManager.default.removeItem(at: root) }

        // Create the required sample directory structure
        let sampleDir = root.appending(path: "samples/SK-A/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sampleDir, withIntermediateDirectories: true)
        let chartsDir = root.appending(path: "samples/SK-A/charts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: chartsDir, withIntermediateDirectories: true)

        let input = SaveActiveChartInput(
            png: Data([0xFF, 0xD8]),
            payload: samplePayload(),
            sampleKeys: ["SK-A"],
            libraryRootPath: root.path
        )
        let outcome = sut.execute(input: input)
        if case .success = outcome {
            // OK
        } else {
            Issue.record("Expected .success, got \(outcome)")
        }
    }

    @Test func chartWithMetrics_succeeds() throws {
        let root = try tmpDir("chartMetrics")
        defer { try? FileManager.default.removeItem(at: root) }

        let sampleDir = root.appending(path: "samples/SK-A/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sampleDir, withIntermediateDirectories: true)
        let chartsDir = root.appending(path: "samples/SK-A/charts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: chartsDir, withIntermediateDirectories: true)

        let input = SaveActiveChartInput(
            png: Data([0xFF, 0xD8]),
            payload: samplePayload(),
            sampleKeys: ["SK-A"],
            libraryRootPath: root.path,
            metrics: [
                PendingMetricEntry(sampleKey: "SK-A", metric: "alpha", value: 1.23e-10, canonicalUnit: "Ω·m³/V²", conditions: ["T_lo": "10K", "T_hi": "50K"]),
                PendingMetricEntry(sampleKey: "SK-A", metric: "beta", value: 4.56e-10, canonicalUnit: "Ω·m³/V²", conditions: ["T_lo": "10K", "T_hi": "50K"]),
            ]
        )
        let outcome = sut.execute(input: input)
        if case .success = outcome {
            // OK
        } else {
            Issue.record("Expected .success, got \(outcome)")
        }
    }

    // MARK: - Conditions normalization

    @Test func conditionsAreNormalized() throws {
        let root = try tmpDir("condNorm")
        defer { try? FileManager.default.removeItem(at: root) }

        let sampleDir = root.appending(path: "samples/SK-A/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sampleDir, withIntermediateDirectories: true)
        let chartsDir = root.appending(path: "samples/SK-A/charts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: chartsDir, withIntermediateDirectories: true)

        // Pass conditions with mixed case and whitespace
        let input = SaveActiveChartInput(
            png: Data([0xFF]),
            payload: samplePayload(),
            sampleKeys: ["SK-A"],
            libraryRootPath: root.path,
            metrics: [
                PendingMetricEntry(sampleKey: "SK-A", metric: "Hc", value: 0.05, canonicalUnit: "T",
                                   conditions: ["  T_Lo ": "10K", "V3METHOD": "HFE"])
            ]
        )
        let outcome = sut.execute(input: input)
        // Should succeed — conditions normalized internally
        if case .success = outcome {
            // Verify the metric was written with normalized keys
            let dataURL = root.appending(path: "samples/SK-A/_spinlab/measurement_data.json")
            let data = try Data(contentsOf: dataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(WorkbenchMeasurementDataStore.self, from: data)
            let record = decoded.records.first!
            #expect(record.conditions.keys.contains("t_lo"))
            #expect(record.conditions.keys.contains("v3method"))
            #expect(!record.conditions.keys.contains("T_Lo"))
            #expect(!record.conditions.keys.contains("V3METHOD"))
        } else {
            Issue.record("Expected .success, got \(outcome)")
        }
    }
}
