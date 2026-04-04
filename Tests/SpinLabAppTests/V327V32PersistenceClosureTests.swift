import Foundation
import Testing
@testable import SpinLabApp

@Suite("V3.2.7 Persistence Closure")
struct V327V32PersistenceClosureTests {

    // MARK: - Relative path round-trip

    @Test("relative path round-trip: absoluteURL then relativePath returns original")
    func relativePathRoundTrip() throws {
        let fixture = try Fixture327()
        defer { fixture.cleanup() }

        let relative = "samples/S1/charts/chart_abc.png"
        let absolute = try fixture.resolver.absoluteURL(for: relative)
        let back = try fixture.resolver.relativePath(for: absolute)

        #expect(back == relative)
    }

    @Test("root-escape path is rejected")
    func rootEscapePathRejected() throws {
        let fixture = try Fixture327()
        defer { fixture.cleanup() }

        #expect(throws: (any Error).self) {
            _ = try fixture.resolver.absoluteURL(for: "../escaped/path.png")
        }
    }

    @Test("absolute path in relative-path slot is rejected")
    func absolutePathInRelativeSlotRejected() throws {
        let fixture = try Fixture327()
        defer { fixture.cleanup() }

        #expect(throws: (any Error).self) {
            _ = try fixture.resolver.absoluteURL(for: "/absolute/path.png")
        }
    }

    // MARK: - End-to-end: artifact files exist on disk after persist

    @Test("persist writes PNG to expected relative path")
    func persistWritesPNGToDisk() throws {
        let fixture = try Fixture327()
        defer { fixture.cleanup() }

        let payload = makePayload(sourceRef: "run1.dat")
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let result = try fixture.makePersistUseCase().execute(
            sampleKey: "S1", payload: payload, imageData: pngData
        )

        let imageURL = try fixture.resolver.absoluteURL(for: result.imagePath)
        #expect(FileManager.default.fileExists(atPath: imageURL.path))
        #expect((try? Data(contentsOf: imageURL)) == pngData)
    }

    @Test("persist writes manifest JSON to expected relative path")
    func persistWritesManifestToDisk() throws {
        let fixture = try Fixture327()
        defer { fixture.cleanup() }

        let payload = makePayload(sourceRef: "run1.dat")
        let result = try fixture.makePersistUseCase().execute(
            sampleKey: "S1", payload: payload, imageData: Data([0x00])
        )

        let manifestURL = try fixture.resolver.absoluteURL(for: result.manifestPath)
        #expect(FileManager.default.fileExists(atPath: manifestURL.path))
    }

    @Test("persist writes results_index.json under _spinlab directory")
    func persistWritesIndex() throws {
        let fixture = try Fixture327()
        defer { fixture.cleanup() }

        let payload = makePayload(sourceRef: "run1.dat")
        _ = try fixture.makePersistUseCase().execute(
            sampleKey: "S1", payload: payload, imageData: Data([0x00])
        )

        let indexURL = try fixture.resolver.absoluteURL(for: "samples/S1/_spinlab/results_index.json")
        #expect(FileManager.default.fileExists(atPath: indexURL.path))
    }

    // MARK: - Overwrite: same identity → single file, content replaced

    @Test("persist twice with same payload writes single PNG (overwrite, not duplicate)")
    func samePayloadWritesSingleFile() throws {
        let fixture = try Fixture327()
        defer { fixture.cleanup() }

        let payload = makePayload(sourceRef: "run1.dat")
        let useCase = fixture.makePersistUseCase()
        let first = try useCase.execute(sampleKey: "S1", payload: payload, imageData: Data([0x01]))
        let second = try useCase.execute(sampleKey: "S1", payload: payload, imageData: Data([0x02]))

        #expect(first.imagePath == second.imagePath)

        // Only one file at that path
        let imageURL = try fixture.resolver.absoluteURL(for: second.imagePath)
        let onDisk = try Data(contentsOf: imageURL)
        #expect(onDisk == Data([0x02]))  // second write wins
    }

    // MARK: - Trace projection wired from persist result

    @Test("trace projection built from persist result has correct fields")
    func traceProjectionFromPersistResult() throws {
        let fixture = try Fixture327()
        defer { fixture.cleanup() }

        let payload = makePayload(sourceRef: "run1.dat")
        let result = try fixture.makePersistUseCase().execute(
            sampleKey: "S1", payload: payload, imageData: Data([0x00]),
            runID: "r42", appVersion: "v3.2.7"
        )

        let trace = BuildRunTraceProjectionUseCase().execute(
            manifest: result.manifest,
            chartIdentityKey: result.chartIdentityKey,
            manifestPath: result.manifestPath
        )

        #expect(trace.runID == "r42")
        #expect(trace.appVersion == "v3.2.7")
        #expect(trace.outputImagePath == result.imagePath)
        #expect(trace.manifestPath == result.manifestPath)
        #expect(trace.chartIdentityKey == result.chartIdentityKey)
        #expect(!trace.outputImagePath.hasPrefix("/"))
        #expect(!trace.manifestPath.hasPrefix("/"))
    }

    // MARK: - No non-atomic write path: V3.2 artifact writes use AtomicFileWriter

    @Test("PersistChartArtifactUseCase uses injected writer (no direct FileManager write)")
    func persistUsesInjectedWriter() throws {
        let fixture = try Fixture327()
        defer { fixture.cleanup() }

        var commitCallCount = 0
        let spyWriter = SpyAtomicWriter { entries in
            commitCallCount += 1
            // Delegate actual write to AtomicFileWriter so files land on disk
            try AtomicFileWriter().commit(entries)
        }

        let useCase = PersistChartArtifactUseCase(
            writer: spyWriter,
            pathResolver: fixture.resolver
        )
        _ = try useCase.execute(
            sampleKey: "S1",
            payload: makePayload(sourceRef: "run1.dat"),
            imageData: Data([0x00])
        )

        #expect(commitCallCount == 1)
    }
}

// MARK: - Helpers

private func makePayload(sourceRef: String) -> WorkbenchPlotPayload {
    WorkbenchPlotPayload(
        workflowID: "AHE",
        workflowDisplayName: "AHE",
        title: "Test",
        axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
        series: [WorkbenchPlotSeries(label: "S", x: [1.0], y: [1.0], sourceRef: sourceRef)]
    )
}

// MARK: - Spy writer

private struct SpyAtomicWriter: AtomicFileWritingCapability {
    let onCommit: ([AtomicWriteEntry]) throws -> Void

    func write(_ data: Data, to destinationURL: URL) throws {
        try commit([AtomicWriteEntry(destinationURL: destinationURL, data: data)])
    }

    func commit(_ entries: [AtomicWriteEntry]) throws {
        try onCommit(entries)
    }
}

// MARK: - Fixture

private struct Fixture327 {
    let rootURL: URL
    let resolver: LibraryPathResolver
    private let fm = FileManager.default

    init() throws {
        rootURL = fm.temporaryDirectory.appending(
            path: "spinlab-v327-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        resolver = LibraryPathResolver(libraryRootURL: rootURL)
    }

    func makePersistUseCase() -> PersistChartArtifactUseCase {
        PersistChartArtifactUseCase(writer: AtomicFileWriter(), pathResolver: resolver)
    }

    func cleanup() { try? fm.removeItem(at: rootURL) }
}
