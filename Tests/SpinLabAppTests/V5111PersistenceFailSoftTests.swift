import XCTest
@testable import SpinLabApp

final class StderrCapture {
    private let pipe = Pipe()
    private let originalFD: Int32

    init() {
        originalFD = dup(STDERR_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
    }

    func stop() -> String {
        fflush(stderr)
        pipe.fileHandleForWriting.closeFile()
        dup2(originalFD, STDERR_FILENO)
        close(originalFD)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}

final class V5111PersistenceFailSoftTests: XCTestCase {
    private func tmpDir(_ tag: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("v5111-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeRecord(sampleKey: String = "sk") -> WorkbenchMetricRecord {
        WorkbenchMetricRecord(
            recordID: UUID().uuidString,
            sampleKey: sampleKey,
            displayKey: sampleKey,
            workflowID: "3w",
            metric: "Hc",
            value: 0.05,
            canonicalUnit: "T",
            conditions: ["temperature": "80K"],
            generatedAt: Date(),
            runID: UUID().uuidString
        )
    }

    private func makePayload() -> WorkbenchPlotPayload {
        WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: "Test Chart",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [WorkbenchPlotSeries(label: "S", x: [1.0], y: [2.0], sourceRef: "runA.dat")]
        )
    }

    func testCorruptMeasurementDataThrowsAndDoesNotOverwrite() throws {
        let root = try tmpDir("measurement-corrupt")
        defer { try? FileManager.default.removeItem(at: root) }

        let corruptURL = root.appendingPathComponent("samples/sk/_spinlab/measurement_data.json")
        try FileManager.default.createDirectory(at: corruptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not valid json".utf8).write(to: corruptURL)

        let useCase = PersistMeasurementDataUseCase(
            writer: AtomicFileWriter(),
            pathResolver: LibraryPathResolver(libraryRootURL: root)
        )
        let capture = StderrCapture()
        XCTAssertThrowsError(try useCase.execute(sampleKey: "sk", record: makeRecord())) { error in
            XCTAssertTrue(error is AppError, "expected AppError, got \(error)")
        }
        let captured = capture.stop()

        // Log tag centralized into LibraryMeasurementDataStore (Debt #3 storage boundary) —
        // was "[PersistMeasurementData]" when this decode/log lived in the UseCase directly.
        XCTAssertTrue(captured.contains("LibraryMeasurementDataStore"), "stderr: \(captured)")
        let remaining = try Data(contentsOf: corruptURL)
        XCTAssertEqual(String(decoding: remaining, as: UTF8.self), "not valid json")
    }

    func testMissingMeasurementDataInitializesWithoutLog() throws {
        let root = try tmpDir("measurement-missing")
        defer { try? FileManager.default.removeItem(at: root) }

        let useCase = PersistMeasurementDataUseCase(
            writer: AtomicFileWriter(),
            pathResolver: LibraryPathResolver(libraryRootURL: root)
        )
        let capture = StderrCapture()
        XCTAssertNoThrow(try useCase.execute(sampleKey: "sk", record: makeRecord()))
        let captured = capture.stop()

        XCTAssertTrue(captured.isEmpty, "stderr: \(captured)")
        let written = root.appendingPathComponent("samples/sk/_spinlab/measurement_data.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: written.path))
    }

    func testSaveActiveChartReturnsPartialForCorruptMeasurementData() throws {
        let root = try tmpDir("save-partial")
        defer { try? FileManager.default.removeItem(at: root) }

        let corruptURL = root.appendingPathComponent("samples/sk/_spinlab/measurement_data.json")
        try FileManager.default.createDirectory(at: corruptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not valid json".utf8).write(to: corruptURL)

        let input = SaveActiveChartInput(
            png: Data([0x89, 0x50, 0x4E, 0x47]),
            payload: makePayload(),
            sampleKeys: ["sk"],
            libraryRootPath: root.path,
            metrics: [
                PendingMetricEntry(
                    sampleKey: "sk",
                    metric: "Hc",
                    value: 0.05,
                    canonicalUnit: "T",
                    conditions: ["temperature": "80K"]
                )
            ]
        )

        let capture = StderrCapture()
        let outcome = SaveActiveChartToLibraryUseCase().execute(input: input)
        let captured = capture.stop()

        guard case .partial(let trace, let metricError) = outcome else {
            return XCTFail("expected partial, got \(outcome)")
        }
        XCTAssertNotNil(trace)
        XCTAssertTrue(metricError.contains("measurement_data corrupt"))
        XCTAssertTrue(captured.contains("LibraryMeasurementDataStore"), "stderr: \(captured)")
    }

    func testCorruptResultsIndexRebuildsWithLog() throws {
        let root = try tmpDir("index-corrupt")
        defer { try? FileManager.default.removeItem(at: root) }

        let indexURL = root.appendingPathComponent("samples/sk/_spinlab/results_index.json")
        try FileManager.default.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("bad json".utf8).write(to: indexURL)

        let useCase = PersistChartArtifactUseCase(
            writer: AtomicFileWriter(),
            pathResolver: LibraryPathResolver(libraryRootURL: root)
        )
        let capture = StderrCapture()
        XCTAssertNoThrow(try useCase.execute(sampleKey: "sk", payload: makePayload(), imageData: Data("png".utf8)))
        let captured = capture.stop()

        // Log tag centralized into LibraryChartIndexStore (Debt #3 storage boundary) —
        // was "[PersistChartArtifact]" when this decode/log lived in the UseCase directly.
        XCTAssertTrue(captured.contains("LibraryChartIndexStore"), "stderr: \(captured)")
        XCTAssertTrue(captured.contains("corrupt"), "stderr: \(captured)")
    }

    func testCorruptLatestChartIndexReturnsNilWithLog() throws {
        let root = try tmpDir("load-corrupt")
        defer { try? FileManager.default.removeItem(at: root) }

        let indexURL = root.appendingPathComponent("samples/sk/_spinlab/results_index.json")
        try FileManager.default.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: indexURL)

        let useCase = LoadLatestChartArtifactUseCase(pathResolver: LibraryPathResolver(libraryRootURL: root))
        let capture = StderrCapture()
        let result = useCase.execute(sampleKey: "sk")
        let captured = capture.stop()

        // Log tag centralized into LibraryChartIndexStore (Debt #3 closeout) —
        // was "[LoadLatestChartArtifact]" when this decode/log lived in the UseCase directly.
        XCTAssertNil(result)
        XCTAssertTrue(captured.contains("LibraryChartIndexStore"), "stderr: \(captured)")
        XCTAssertTrue(captured.contains("decode failed"), "stderr: \(captured)")
    }

    func testMissingLatestChartIndexReturnsNilSilently() throws {
        let root = try tmpDir("load-missing")
        defer { try? FileManager.default.removeItem(at: root) }

        let useCase = LoadLatestChartArtifactUseCase(pathResolver: LibraryPathResolver(libraryRootURL: root))
        let capture = StderrCapture()
        let result = useCase.execute(sampleKey: "sk")
        let captured = capture.stop()

        XCTAssertNil(result)
        XCTAssertTrue(captured.isEmpty, "stderr: \(captured)")
    }

    func testUnsupportedSchemaVersionLatestChartIndexReturnsNilWithLog() throws {
        let root = try tmpDir("load-unsupported-schema")
        defer { try? FileManager.default.removeItem(at: root) }

        let indexURL = root.appendingPathComponent("samples/sk/_spinlab/results_index.json")
        try FileManager.default.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let index = WorkbenchResultsIndex(schemaVersion: 2, sampleKey: "sk", updatedAt: Date(), references: [
            WorkbenchResultReference(
                chartIdentityKey: "k1",
                chartImagePath: "samples/sk/_spinlab/chart.png",
                manifestPath: "samples/sk/_spinlab/manifest.json",
                workflowID: "3w",
                generatedAt: Date()
            )
        ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(index).write(to: indexURL)

        let useCase = LoadLatestChartArtifactUseCase(pathResolver: LibraryPathResolver(libraryRootURL: root))
        let capture = StderrCapture()
        let result = useCase.execute(sampleKey: "sk")
        let captured = capture.stop()

        XCTAssertNil(result)
        XCTAssertTrue(captured.contains("LibraryChartIndexStore"), "stderr: \(captured)")
        XCTAssertTrue(captured.contains("unsupported results_index schema"), "stderr: \(captured)")
    }
}
