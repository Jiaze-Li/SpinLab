import Foundation
import Testing
@testable import SpinLabApp

@Suite("V3.2.6 Run Manifest Trace")
struct V326RunManifestTraceTests {

    // MARK: - Manifest provenance fields

    @Test("manifest contains all required provenance fields")
    func manifestContainsRequiredProvenanceFields() throws {
        let fixture = try Fixture326()
        defer { fixture.cleanup() }

        let payload = makePayload(sourceRef: "run1.dat")
        let useCase = fixture.makePersistUseCase()
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let result = try useCase.execute(
            sampleKey: "S1", payload: payload, imageData: pngData,
            runID: "fixed-run-id", generatedAt: .distantPast, appVersion: "v3.2.6"
        )

        let manifest = try fixture.loadManifest(at: result.manifestPath)
        #expect(!manifest.runID.isEmpty)
        #expect(!manifest.manifestID.isEmpty)
        #expect(manifest.workflowID == "AHE")
        #expect(manifest.inputFiles.contains("run1.dat"))
        #expect(!manifest.outputImagePath.isEmpty)
        #expect(manifest.appVersion == "v3.2.6")
        #expect(manifest.axisMapping.xField == "X")
        #expect(manifest.axisMapping.yField == "Y")
    }

    @Test("manifest outputImagePath is library-root-relative (no leading slash)")
    func outputImagePathIsRelative() throws {
        let fixture = try Fixture326()
        defer { fixture.cleanup() }

        let payload = makePayload(sourceRef: "run1.dat")
        let result = try fixture.makePersistUseCase().execute(
            sampleKey: "S1", payload: payload, imageData: Data([0x00])
        )
        let manifest = try fixture.loadManifest(at: result.manifestPath)

        #expect(!manifest.outputImagePath.hasPrefix("/"))
        #expect(manifest.outputImagePath.hasSuffix(".png"))
    }

    @Test("manifest path itself is library-root-relative")
    func manifestPathIsRelative() throws {
        let fixture = try Fixture326()
        defer { fixture.cleanup() }

        let payload = makePayload(sourceRef: "run1.dat")
        let result = try fixture.makePersistUseCase().execute(
            sampleKey: "S1", payload: payload, imageData: Data([0x00])
        )

        #expect(!result.manifestPath.hasPrefix("/"))
        #expect(result.manifestPath.hasSuffix(".manifest.json"))
    }

    // MARK: - Trace projection: reads from manifest, no recomputation

    @Test("projection fields match manifest exactly")
    func projectionFieldsMatchManifest() throws {
        let fixture = try Fixture326()
        defer { fixture.cleanup() }

        let payload = makePayload(sourceRef: "run1.dat",
                                  semanticParams: ["condition": "80K"])
        let result = try fixture.makePersistUseCase().execute(
            sampleKey: "S1", payload: payload, imageData: Data([0x00]),
            runID: "test-run-42", generatedAt: .distantPast, appVersion: "v3.2.6"
        )
        let manifest = try fixture.loadManifest(at: result.manifestPath)

        let projection = BuildRunTraceProjectionUseCase().execute(
            manifest: manifest,
            manifestPath: result.manifestPath
        )

        #expect(projection.runID == manifest.runID)
        #expect(projection.workflowID == manifest.workflowID)
        #expect(projection.inputFiles == manifest.inputFiles)
        #expect(projection.axisMapping == manifest.axisMapping)
        #expect(projection.semanticParams == manifest.semanticParams)
        #expect(projection.outputImagePath == manifest.outputImagePath)
        #expect(projection.generatedAt == manifest.generatedAt)
    }

    @Test("projection manifestPath matches the path passed in, not recomputed")
    func projectionManifestPathFromArgument() {
        let manifest = WorkbenchRunManifest(
            manifestID: "m1", runID: "r1", workflowID: "AHE",
            inputFiles: ["a.dat"], filters: [:],
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            semanticParams: [:],
            outputImagePath: "samples/S1/charts/chart_abc.png",
            generatedAt: .distantPast, appVersion: "v3.2.6"
        )

        let projection = BuildRunTraceProjectionUseCase().execute(
            manifest: manifest,
            manifestPath: "samples/S1/charts/chart_abc.manifest.json"
        )

        #expect(projection.manifestPath == "samples/S1/charts/chart_abc.manifest.json")
    }

    // MARK: - Two runs produce independent traces

    @Test("two different runs produce distinct trace projections")
    func twoRunsProduceDistinctTraces() throws {
        let fixture = try Fixture326()
        defer { fixture.cleanup() }

        let payloadA = makePayload(sourceRef: "run1.dat",
                                   xField: "Magnetic Field (Oe)", yField: "Bridge 1 Resistance (Ohms)",
                                   title: "Run A")
        let payloadB = makePayload(sourceRef: "run1.dat",
                                   xField: "Temperature (K)", yField: "Bridge 1 Resistance (Ohms)",
                                   title: "Run B")
        let persist = fixture.makePersistUseCase()
        let pngData = Data([0x00])

        let resultA = try persist.execute(sampleKey: "S1", payload: payloadA, imageData: pngData,
                                          runID: "run-A")
        let resultB = try persist.execute(sampleKey: "S1", payload: payloadB, imageData: pngData,
                                          runID: "run-B")

        let manifestA = try fixture.loadManifest(at: resultA.manifestPath)
        let manifestB = try fixture.loadManifest(at: resultB.manifestPath)

        let traceA = BuildRunTraceProjectionUseCase().execute(
            manifest: manifestA,
            manifestPath: resultA.manifestPath
        )
        let traceB = BuildRunTraceProjectionUseCase().execute(
            manifest: manifestB,
            manifestPath: resultB.manifestPath
        )

        #expect(traceA.outputImagePath != traceB.outputImagePath)
        #expect(traceA.manifestPath != traceB.manifestPath)
        #expect(traceA.runID != traceB.runID)
    }
}

// MARK: - Helpers

private func makePayload(
    sourceRef: String,
    xField: String = "X",
    yField: String = "Y",
    title: String = "Test",
    semanticParams: [String: String] = [:]
) -> WorkbenchPlotPayload {
    WorkbenchPlotPayload(
        workflowID: "AHE",
        workflowDisplayName: "AHE",
        title: title,
        axisMapping: WorkbenchAxisMapping(xField: xField, yField: yField),
        series: [WorkbenchPlotSeries(label: "S", x: [1.0], y: [1.0], sourceRef: sourceRef)],
        semanticParams: semanticParams
    )
}

// MARK: - Fixture

private struct Fixture326 {
    let rootURL: URL
    let resolver: LibraryPathResolver
    private let fm = FileManager.default

    init() throws {
        rootURL = fm.temporaryDirectory.appending(
            path: "spinlab-v326-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        resolver = LibraryPathResolver(libraryRootURL: rootURL)
    }

    func makePersistUseCase() -> PersistChartArtifactUseCase {
        PersistChartArtifactUseCase(writer: AtomicFileWriter(), pathResolver: resolver)
    }

    func loadManifest(at relativePath: String) throws -> WorkbenchRunManifest {
        let url = try resolver.absoluteURL(for: relativePath)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkbenchRunManifest.self, from: data)
    }

    func cleanup() { try? fm.removeItem(at: rootURL) }
}
