import Foundation
import Testing
@testable import SpinLabApp

@Suite("V3.2.4 Chart Identity + Overwrite Behavior")
struct V324ChartIdentityOverwriteTests {

    // MARK: - Identity: style-only change does not affect key

    @Test("styleParams change does not alter identity key")
    func styleChangeDoesNotAlterIdentity() {
        let base = makePayload(workflowID: "AHE", sourceRef: "a.dat",
                               xField: "X", yField: "Y", styleParams: [:])
        let styled = makePayload(workflowID: "AHE", sourceRef: "a.dat",
                                 xField: "X", yField: "Y",
                                 styleParams: ["showGrid": "true", "theme": "dark"])

        #expect(WorkbenchChartIdentity.makeIdentityKey(from: base) ==
                WorkbenchChartIdentity.makeIdentityKey(from: styled))
    }

    @Test("title change does not alter identity key")
    func titleChangeDoesNotAlterIdentity() {
        let base = makePayload(workflowID: "AHE", sourceRef: "a.dat",
                               xField: "X", yField: "Y", title: "Old Title")
        let retitled = makePayload(workflowID: "AHE", sourceRef: "a.dat",
                                   xField: "X", yField: "Y", title: "New Title")

        #expect(WorkbenchChartIdentity.makeIdentityKey(from: base) ==
                WorkbenchChartIdentity.makeIdentityKey(from: retitled))
    }

    // MARK: - Identity: semantic changes produce new key

    @Test("axisMapping change produces distinct identity key")
    func axisMappingChangeProducesNewKey() {
        let original = makePayload(workflowID: "AHE", sourceRef: "a.dat",
                                   xField: "Magnetic Field (Oe)", yField: "Bridge 1 Resistance (Ohms)")
        let remapped = makePayload(workflowID: "AHE", sourceRef: "a.dat",
                                   xField: "Temperature (K)", yField: "Bridge 1 Resistance (Ohms)")

        #expect(WorkbenchChartIdentity.makeIdentityKey(from: original) !=
                WorkbenchChartIdentity.makeIdentityKey(from: remapped))
    }

    @Test("different input files produce distinct identity key")
    func differentInputFilesProduceNewKey() {
        let payloadA = makePayload(workflowID: "AHE", sourceRef: "run1.dat",
                                   xField: "X", yField: "Y")
        let payloadB = makePayload(workflowID: "AHE", sourceRef: "run2.dat",
                                   xField: "X", yField: "Y")

        #expect(WorkbenchChartIdentity.makeIdentityKey(from: payloadA) !=
                WorkbenchChartIdentity.makeIdentityKey(from: payloadB))
    }

    @Test("workflowID change produces distinct identity key")
    func workflowIDChangeProducesNewKey() {
        let ahe = makePayload(workflowID: "AHE", sourceRef: "a.dat", xField: "X", yField: "Y")
        let rt = makePayload(workflowID: "RT", sourceRef: "a.dat", xField: "X", yField: "Y")

        #expect(WorkbenchChartIdentity.makeIdentityKey(from: ahe) !=
                WorkbenchChartIdentity.makeIdentityKey(from: rt))
    }

    @Test("identity key format is chart_ prefix followed by 64 hex chars")
    func identityKeyFormat() {
        let payload = makePayload(workflowID: "AHE", sourceRef: "a.dat", xField: "X", yField: "Y")
        let key = WorkbenchChartIdentity.makeIdentityKey(from: payload)

        #expect(key.hasPrefix("chart_"))
        let hex = String(key.dropFirst("chart_".count))
        #expect(hex.count == 64)
        #expect(hex.allSatisfy { $0.isHexDigit })
    }

    // MARK: - Overwrite: same identity replaces artifact at same path

    @Test("same identity persist twice reports isOverwrite=true on second call")
    func sameIdentitySecondPersistIsOverwrite() throws {
        let fixture = try Fixture324()
        defer { fixture.cleanup() }

        let payload = makePayload(workflowID: "AHE", sourceRef: "a.dat", xField: "X", yField: "Y")
        let useCase = fixture.makeUseCase()
        let pngData = Data([0x89, 0x50, 0x4E, 0x47]) // minimal stub

        let first = try useCase.execute(sampleKey: "S1", payload: payload, imageData: pngData)
        let second = try useCase.execute(sampleKey: "S1", payload: payload, imageData: pngData)

        #expect(!first.isOverwrite)
        #expect(second.isOverwrite)
        #expect(first.chartIdentityKey == second.chartIdentityKey)
        #expect(first.imagePath == second.imagePath)
        #expect(first.manifestPath == second.manifestPath)
    }

    @Test("overwrite leaves image file at same path")
    func overwriteLeavesImageAtSamePath() throws {
        let fixture = try Fixture324()
        defer { fixture.cleanup() }

        let payload = makePayload(workflowID: "AHE", sourceRef: "a.dat", xField: "X", yField: "Y")
        let useCase = fixture.makeUseCase()
        let firstData = Data([0x01, 0x02])
        let secondData = Data([0x03, 0x04])

        let first = try useCase.execute(sampleKey: "S1", payload: payload, imageData: firstData)
        let second = try useCase.execute(sampleKey: "S1", payload: payload, imageData: secondData)

        let imageURL = try fixture.resolver.absoluteURL(for: second.imagePath)
        let onDisk = try Data(contentsOf: imageURL)
        #expect(onDisk == secondData)
        #expect(first.imagePath == second.imagePath)
    }

    // MARK: - New artifact: distinct identity produces distinct path

    @Test("different identity produces distinct artifact paths")
    func differentIdentityDistinctPaths() throws {
        let fixture = try Fixture324()
        defer { fixture.cleanup() }

        let payloadA = makePayload(workflowID: "AHE", sourceRef: "a.dat",
                                   xField: "Magnetic Field (Oe)", yField: "Bridge 1 Resistance (Ohms)",
                                   title: "Run A")
        let payloadB = makePayload(workflowID: "AHE", sourceRef: "a.dat",
                                   xField: "Temperature (K)", yField: "Bridge 1 Resistance (Ohms)",
                                   title: "Run B")
        let useCase = fixture.makeUseCase()
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])

        let resultA = try useCase.execute(sampleKey: "S1", payload: payloadA, imageData: pngData)
        let resultB = try useCase.execute(sampleKey: "S1", payload: payloadB, imageData: pngData)

        #expect(resultA.chartIdentityKey != resultB.chartIdentityKey)
        #expect(resultA.imagePath != resultB.imagePath)
        #expect(resultA.manifestPath != resultB.manifestPath)
    }

    // MARK: - Same-second, different-identity: no filename collision

    @Test("same-second different-identity writes produce distinct artifact paths")
    func sameSecondDifferentIdentityDistinctPaths() throws {
        let fixture = try Fixture324()
        defer { fixture.cleanup() }

        let sameMoment = Date()
        // Same title + same timestamp — only difference is sourceRef, so identityKeys differ.
        let payloadA = makePayload(workflowID: "AHE", sourceRef: "run_a.dat",
                                   xField: "X", yField: "Y", title: "My Chart")
        let payloadB = makePayload(workflowID: "AHE", sourceRef: "run_b.dat",
                                   xField: "X", yField: "Y", title: "My Chart")
        let useCase = fixture.makeUseCase()
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])

        let resultA = try useCase.execute(sampleKey: "S1", payload: payloadA,
                                          imageData: pngData, generatedAt: sameMoment)
        let resultB = try useCase.execute(sampleKey: "S1", payload: payloadB,
                                          imageData: pngData, generatedAt: sameMoment)

        #expect(resultA.imagePath != resultB.imagePath)
        #expect(resultA.manifestPath != resultB.manifestPath)
        #expect(resultA.chartIdentityKey != resultB.chartIdentityKey)
    }

    // MARK: - Index upsert behavior

    @Test("same identity twice results in one index entry")
    func sameIdentityUpsertIndexToOneEntry() throws {
        let fixture = try Fixture324()
        defer { fixture.cleanup() }

        let payload = makePayload(workflowID: "AHE", sourceRef: "a.dat", xField: "X", yField: "Y")
        let useCase = fixture.makeUseCase()
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])

        _ = try useCase.execute(sampleKey: "S1", payload: payload, imageData: pngData)
        _ = try useCase.execute(sampleKey: "S1", payload: payload, imageData: pngData)

        let index = try fixture.loadIndex(sampleKey: "S1")
        #expect(index.references.count == 1)
    }

    @Test("different identities produce two index entries")
    func differentIdentitiesAppendTwoIndexEntries() throws {
        let fixture = try Fixture324()
        defer { fixture.cleanup() }

        let payloadA = makePayload(workflowID: "AHE", sourceRef: "a.dat",
                                   xField: "Magnetic Field (Oe)", yField: "Bridge 1 Resistance (Ohms)")
        let payloadB = makePayload(workflowID: "AHE", sourceRef: "a.dat",
                                   xField: "Temperature (K)", yField: "Bridge 1 Resistance (Ohms)")
        let useCase = fixture.makeUseCase()
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])

        _ = try useCase.execute(sampleKey: "S1", payload: payloadA, imageData: pngData)
        _ = try useCase.execute(sampleKey: "S1", payload: payloadB, imageData: pngData)

        let index = try fixture.loadIndex(sampleKey: "S1")
        #expect(index.references.count == 2)
    }

    @Test("manifest records correct workflowID and outputImagePath")
    func manifestContentsAreCorrect() throws {
        let fixture = try Fixture324()
        defer { fixture.cleanup() }

        let payload = makePayload(workflowID: "AHE", sourceRef: "run1.dat", xField: "X", yField: "Y")
        let useCase = fixture.makeUseCase()
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])

        let result = try useCase.execute(sampleKey: "S1", payload: payload, imageData: pngData)
        let manifest = try fixture.loadManifest(at: result.manifestPath)

        #expect(manifest.workflowID == "AHE")
        #expect(manifest.outputImagePath == result.imagePath)
        #expect(manifest.inputFiles.contains("run1.dat"))
        #expect(manifest.appVersion == AppVersion.current)
    }
}

// MARK: - Helpers

private func makePayload(
    workflowID: String,
    sourceRef: String,
    xField: String,
    yField: String,
    title: String = "Test",
    styleParams: [String: String] = [:],
    semanticParams: [String: String] = [:]
) -> WorkbenchPlotPayload {
    WorkbenchPlotPayload(
        workflowID: workflowID,
        workflowDisplayName: workflowID,
        title: title,
        axisMapping: WorkbenchAxisMapping(xField: xField, yField: yField),
        series: [WorkbenchPlotSeries(label: "S", x: [1.0], y: [1.0], sourceRef: sourceRef)],
        semanticParams: semanticParams,
        styleParams: styleParams
    )
}

// MARK: - Fixture

private struct Fixture324 {
    let rootURL: URL
    let resolver: LibraryPathResolver
    private let fm = FileManager.default

    init() throws {
        rootURL = fm.temporaryDirectory.appending(
            path: "spinlab-v324-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        resolver = LibraryPathResolver(libraryRootURL: rootURL)
    }

    func makeUseCase() -> PersistChartArtifactUseCase {
        PersistChartArtifactUseCase(writer: AtomicFileWriter(), pathResolver: resolver)
    }

    func loadIndex(sampleKey: String) throws -> WorkbenchResultsIndex {
        let url = try resolver.absoluteURL(for: "samples/\(sampleKey)/_spinlab/results_index.json")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkbenchResultsIndex.self, from: data)
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
