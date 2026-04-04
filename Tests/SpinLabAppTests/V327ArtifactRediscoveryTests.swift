import Foundation
import Testing
@testable import SpinLabApp

@Suite("V3.2.7 Artifact Rediscovery")
struct V327ArtifactRediscoveryTests {

    // MARK: - Happy path: index exists → loads latest artifact

    @Test("loads latest artifact when index and files exist")
    func loadsLatestArtifactFromIndex() throws {
        let fixture = try Fixture327R()
        defer { fixture.cleanup() }

        // Write two artifacts at different times
        let payloadA = makePayload(sourceRef: "run1.dat", xField: "X", yField: "Y")
        let payloadB = makePayload(sourceRef: "run1.dat", xField: "Temperature (K)", yField: "Y")
        let persist = fixture.makePersistUseCase()
        let earlier = Date(timeIntervalSince1970: 1000)
        let later   = Date(timeIntervalSince1970: 2000)

        _ = try persist.execute(sampleKey: "S1", payload: payloadA,
                                imageData: Data([0x01]), generatedAt: earlier)
        _ = try persist.execute(sampleKey: "S1", payload: payloadB,
                                imageData: Data([0x02]), generatedAt: later)

        let loaded = LoadLatestChartArtifactUseCase(pathResolver: fixture.resolver)
            .execute(sampleKey: "S1")

        #expect(loaded != nil)
        #expect(loaded?.imageData == Data([0x02]))   // latest wins
        #expect(loaded?.manifest.axisMapping.xField == "Temperature (K)")
    }

    @Test("loaded artifact produces correct trace projection")
    func loadedArtifactProducesTrace() throws {
        let fixture = try Fixture327R()
        defer { fixture.cleanup() }

        let payload = makePayload(sourceRef: "run1.dat", xField: "X", yField: "Y")
        let result = try fixture.makePersistUseCase().execute(
            sampleKey: "S1", payload: payload, imageData: Data([0xAB]),
            runID: "trace-run", appVersion: "v3.2.7"
        )

        let loaded = LoadLatestChartArtifactUseCase(pathResolver: fixture.resolver)
            .execute(sampleKey: "S1")!

        let trace = BuildRunTraceProjectionUseCase().execute(
            manifest: loaded.manifest,
            chartIdentityKey: loaded.chartIdentityKey,
            manifestPath: loaded.manifestPath
        )

        #expect(trace.runID == "trace-run")
        #expect(trace.appVersion == "v3.2.7")
        #expect(trace.chartIdentityKey == result.chartIdentityKey)
        #expect(!trace.outputImagePath.hasPrefix("/"))
    }

    // MARK: - Graceful degradation

    @Test("returns nil when no index exists (no crash)")
    func returnsNilWhenNoIndex() throws {
        let fixture = try Fixture327R()
        defer { fixture.cleanup() }

        let loaded = LoadLatestChartArtifactUseCase(pathResolver: fixture.resolver)
            .execute(sampleKey: "NonExistentSample")

        #expect(loaded == nil)
    }

    @Test("returns nil when index JSON is corrupted (no crash)")
    func returnsNilWhenIndexCorrupted() throws {
        let fixture = try Fixture327R()
        defer { fixture.cleanup() }

        // Write a corrupted index
        let indexRelPath = "samples/S1/_spinlab/results_index.json"
        let indexURL = try fixture.resolver.absoluteURL(for: indexRelPath)
        try FileManager.default.createDirectory(
            at: indexURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not valid json {{{".utf8).write(to: indexURL)

        let loaded = LoadLatestChartArtifactUseCase(pathResolver: fixture.resolver)
            .execute(sampleKey: "S1")

        #expect(loaded == nil)
    }

    @Test("returns nil when index references missing PNG file (no crash)")
    func returnsNilWhenPNGMissing() throws {
        let fixture = try Fixture327R()
        defer { fixture.cleanup() }

        // Write a valid artifact then delete the PNG
        let payload = makePayload(sourceRef: "run1.dat", xField: "X", yField: "Y")
        let result = try fixture.makePersistUseCase().execute(
            sampleKey: "S1", payload: payload, imageData: Data([0x00])
        )
        let imageURL = try fixture.resolver.absoluteURL(for: result.imagePath)
        try FileManager.default.removeItem(at: imageURL)

        let loaded = LoadLatestChartArtifactUseCase(pathResolver: fixture.resolver)
            .execute(sampleKey: "S1")

        #expect(loaded == nil)
    }

    // MARK: - Multiple references: most recent wins

    @Test("with three references at different times, most recent is returned")
    func mostRecentOfThreeIsReturned() throws {
        let fixture = try Fixture327R()
        defer { fixture.cleanup() }

        let persist = fixture.makePersistUseCase()
        let t1 = Date(timeIntervalSince1970: 100)
        let t2 = Date(timeIntervalSince1970: 200)
        let t3 = Date(timeIntervalSince1970: 300)

        _ = try persist.execute(sampleKey: "S1",
            payload: makePayload(sourceRef: "a.dat", xField: "F1", yField: "Y"),
            imageData: Data([0x01]), generatedAt: t1)
        _ = try persist.execute(sampleKey: "S1",
            payload: makePayload(sourceRef: "a.dat", xField: "F2", yField: "Y"),
            imageData: Data([0x02]), generatedAt: t2)
        _ = try persist.execute(sampleKey: "S1",
            payload: makePayload(sourceRef: "a.dat", xField: "F3", yField: "Y"),
            imageData: Data([0x03]), generatedAt: t3)

        let loaded = LoadLatestChartArtifactUseCase(pathResolver: fixture.resolver)
            .execute(sampleKey: "S1")

        #expect(loaded?.imageData == Data([0x03]))
        #expect(loaded?.manifest.axisMapping.xField == "F3")
    }
}

// MARK: - Helpers

private func makePayload(sourceRef: String, xField: String, yField: String) -> WorkbenchPlotPayload {
    WorkbenchPlotPayload(
        workflowID: "AHE",
        workflowDisplayName: "AHE",
        title: "Test",
        axisMapping: WorkbenchAxisMapping(xField: xField, yField: yField),
        series: [WorkbenchPlotSeries(label: "S", x: [1.0], y: [1.0], sourceRef: sourceRef)]
    )
}

// MARK: - Fixture

private struct Fixture327R {
    let rootURL: URL
    let resolver: LibraryPathResolver
    private let fm = FileManager.default

    init() throws {
        rootURL = fm.temporaryDirectory.appending(
            path: "spinlab-v327r-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        resolver = LibraryPathResolver(libraryRootURL: rootURL)
    }

    func makePersistUseCase() -> PersistChartArtifactUseCase {
        PersistChartArtifactUseCase(writer: AtomicFileWriter(), pathResolver: resolver)
    }

    func cleanup() { try? fm.removeItem(at: rootURL) }
}
