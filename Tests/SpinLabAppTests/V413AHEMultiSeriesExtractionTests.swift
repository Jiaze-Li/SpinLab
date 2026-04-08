import Foundation
import Testing
@testable import SpinLabApp

/// V4.1.3 — Multi-series AHE metric extraction.
///
/// Coverage:
///   - Per-series Hc and R_AHE extraction from multiple AHE curves
///   - sampleKey parsing from series labels
///   - Consistency guard: mismatch between sampleKeys and extracted metrics aborts persist
///   - Unparseable label → .failure with failed label list
@Suite("V4.1.3 AHE Multi-Series Extraction")
struct V413AHEMultiSeriesExtractionTests {

    // MARK: - Helpers

    /// Builds a synthetic AHE hysteresis loop for testing.
    /// The loop goes from +hMax → -hMax → +hMax with a step function in y:
    ///   y = +amplitude when H > 0, y = -amplitude when H < 0, plus a yOffset.
    private func makeAHESeries(
        sampleKey: String,
        channel: String = "ch1",
        temperature: String? = nil,
        hMax: Double = 1.0,
        amplitude: Double = 0.5,
        yOffset: Double = 0.0,
        nPoints: Int = 40
    ) -> WorkbenchPlotSeries {
        let halfN = nPoints / 2
        let step = 2.0 * hMax / Double(halfN)
        // Descending: +hMax → -hMax
        let descending = (0...halfN).map { hMax - step * Double($0) }
        // Ascending: -hMax → +hMax (skip duplicate at -hMax)
        let ascending = (1...halfN).map { -hMax + step * Double($0) }
        let xs = descending + ascending
        let ys = xs.map { h -> Double in
            let base = h >= 0 ? amplitude : -amplitude
            return base + yOffset
        }
        let label: String
        if let t = temperature {
            label = "\(sampleKey) | \(channel) | \(t)"
        } else {
            label = "\(sampleKey) | \(channel)"
        }
        return WorkbenchPlotSeries(label: label, x: xs, y: ys)
    }

    // MARK: - parseSampleKey

    @Test("parseSampleKey extracts first segment from standard label")
    func parseSampleKeyStandard() {
        let key = AHEWorkspaceStore.parseSampleKey(from: "PN31 | ch1 | 80K")
        #expect(key == "PN31")
    }

    @Test("parseSampleKey handles label without temperature")
    func parseSampleKeyNoTemp() {
        let key = AHEWorkspaceStore.parseSampleKey(from: "SK-A | ch2")
        #expect(key == "SK-A")
    }

    @Test("parseSampleKey returns nil for empty label")
    func parseSampleKeyEmpty() {
        #expect(AHEWorkspaceStore.parseSampleKey(from: "") == nil)
    }

    @Test("parseSampleKey returns key for label without separator")
    func parseSampleKeyNoSeparator() {
        let key = AHEWorkspaceStore.parseSampleKey(from: "PN31")
        #expect(key == "PN31")
    }

    // MARK: - Single-series extraction (baseline parity)

    @Test("extractSingleSeriesMetrics returns correct Hc and R_AHE for ideal step")
    func singleSeriesIdealStep() {
        let series = makeAHESeries(sampleKey: "SK-A", hMax: 1.0, amplitude: 0.5, yOffset: 10.0)
        let (hc, rAHE) = AHEWorkspaceStore.extractSingleSeriesMetrics(series)
        // Hc should be near 0 for a step function centered at H=0
        #expect(hc < 0.1)
        // R_AHE should be near 0.5 (half the total jump)
        #expect(abs(rAHE - 0.5) < 0.15)
    }

    @Test("extractSingleSeriesMetrics returns (0,0) for single-point series")
    func singlePoint() {
        let series = WorkbenchPlotSeries(label: "SK-A | ch1", x: [0.5], y: [1.0])
        let (hc, rAHE) = AHEWorkspaceStore.extractSingleSeriesMetrics(series)
        #expect(hc == 0.0)
        #expect(rAHE == 0.0)
    }

    // MARK: - Multi-series extraction

    @Test("extractAHEMetricsPerSeries returns one metric per distinct sampleKey")
    func multiSeriesDistinctKeys() throws {
        let s1 = makeAHESeries(sampleKey: "SK-A", hMax: 1.0, amplitude: 0.5, yOffset: 5.0)
        let s2 = makeAHESeries(sampleKey: "SK-B", hMax: 1.0, amplitude: 1.0, yOffset: 8.0)
        let metrics = try AHEWorkspaceStore.extractAHEMetricsPerSeries(from: [s1, s2]).get()

        #expect(metrics.count == 2)
        #expect(metrics["SK-A"] != nil)
        #expect(metrics["SK-B"] != nil)
        // SK-B has larger amplitude → larger R_AHE
        #expect(metrics["SK-B"]!.rAHE > metrics["SK-A"]!.rAHE)
    }

    @Test("extractAHEMetricsPerSeries deduplicates same sampleKey (multi-channel)")
    func multiSeriesSameKey() throws {
        let s1 = makeAHESeries(sampleKey: "SK-A", channel: "ch1")
        let s2 = makeAHESeries(sampleKey: "SK-A", channel: "ch2")
        let metrics = try AHEWorkspaceStore.extractAHEMetricsPerSeries(from: [s1, s2]).get()

        #expect(metrics.count == 1)
        #expect(metrics["SK-A"] != nil)
    }

    @Test("extractAHEMetricsPerSeries returns empty dict for empty input")
    func multiSeriesEmpty() throws {
        let metrics = try AHEWorkspaceStore.extractAHEMetricsPerSeries(from: []).get()
        #expect(metrics.isEmpty)
    }

    // MARK: - Unparseable label → failure with label list

    @Test("extractAHEMetricsPerSeries returns failure with unparseable label list")
    func unparseableLabelReturnsFailure() {
        let good = makeAHESeries(sampleKey: "SK-A")
        var bad = makeAHESeries(sampleKey: "SK-B")
        bad.label = ""  // unparseable
        let result = AHEWorkspaceStore.extractAHEMetricsPerSeries(from: [good, bad])

        if case .failure(let error) = result {
            #expect(error == .unparseableLabels(["<empty>"]))
        } else {
            Issue.record("Expected .failure(.unparseableLabels), got .success")
        }
    }

    @Test("extractAHEMetricsPerSeries collects all unparseable labels")
    func multipleUnparseableLabels() {
        var bad1 = makeAHESeries(sampleKey: "X")
        bad1.label = ""
        var bad2 = makeAHESeries(sampleKey: "Y")
        bad2.label = ""
        let result = AHEWorkspaceStore.extractAHEMetricsPerSeries(from: [bad1, bad2])

        if case .failure(let error) = result {
            #expect(error == .unparseableLabels(["<empty>", "<empty>"]))
        } else {
            Issue.record("Expected .failure(.unparseableLabels), got .success")
        }
    }

    // MARK: - Persist consistency guards (migrated to SaveActiveChartToLibraryUseCase)

    @Test("persist fails when metric sampleKey not in sampleKeys")
    func metricSampleKeyMismatchFails() throws {
        let payload = WorkbenchPlotPayload(
            workflowID: "AHE",
            workflowDisplayName: "AHE",
            title: "Test",
            axisMapping: WorkbenchAxisMapping(xField: "H", yField: "R"),
            series: [WorkbenchPlotSeries(label: "f1", x: [], y: [], sourceRef: "/fake/f1.csv")]
        )
        let root = FileManager.default.temporaryDirectory
            .appending(path: "v413-mismatch-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let input = SaveActiveChartInput(
            png: Data([0xFF]),
            payload: payload,
            sampleKeys: ["SK-A"],
            libraryRootPath: root.path,
            metrics: [
                PendingMetricEntry(sampleKey: "SK-B", metric: "Hc", value: 0.05, canonicalUnit: "T", conditions: [:])
            ]
        )
        let outcome = SaveActiveChartToLibraryUseCase().execute(input: input)
        if case .failure(let msg) = outcome {
            #expect(msg.contains("not in sampleKeys"))
        } else {
            Issue.record("Expected .failure with sampleKey mismatch, got \(outcome)")
        }
    }
}
