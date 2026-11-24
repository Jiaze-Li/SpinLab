import Foundation
import Testing
@testable import SpinLabApp

/// Shared helpers for the asset-storage suites (task 5A). Everything runs in isolated temp libraries.
enum AssetTestSupport {
    struct Crash: Error {}

    struct Scenario {
        let root: URL
        let store: LibraryStore
        let service: LibraryAssetService
        let sampleA: LibrarySample
        let sampleB: LibrarySample
        var uidA: String { sampleA.sampleUID ?? sampleA.id }
        var uidB: String { sampleB.sampleUID ?? sampleB.id }
    }

    static func makeScenario() throws -> Scenario {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SpinLab_Task5A_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = LibraryStore()
        try store.initializeV2Library(at: root)
        let a = try makeSample(store: store, root: root, batch: "PN501")
        let b = try makeSample(store: store, root: root, batch: "PN502")
        return Scenario(root: root, store: store, service: LibraryAssetService(libraryStore: store), sampleA: a, sampleB: b)
    }

    static func makeSample(store: LibraryStore, root: URL, batch: String) throws -> LibrarySample {
        let outcome = NativeSampleCreationService().createSample(
            draft: CreateNativeSampleDraft(batchId: batch, substrateDescription: "STO(001)", sampleUID: SampleIdentityRule.makeRandomUID()),
            rootURL: root, libraryStore: store, settings: .default
        )
        guard case .success(let sample, _, _) = outcome else {
            throw AppError.state("sample creation failed: \(outcome)")
        }
        return sample
    }

    /// Non-square (5×3), three channels, positive/negative values, NaN and ±Inf, calibrated axes.
    static func fixtureIBW(seed: Float = 0, dataUnit: String = "m") -> Data {
        func values(_ base: Float) -> [[Float]] {
            (0..<3).map { y in (0..<5).map { x in (base + Float(y) * 1.5 - Float(x) * 0.25 + seed) * 1e-9 } }
        }
        var phase = values(-2)
        phase[0][1] = .nan
        phase[1][2] = .infinity
        phase[2][3] = -.infinity
        return IBWFixtureBuilder.build(
            waveName: "Fixture", nX: 5, nY: 3,
            channels: [
                .init(label: "HeightRetrace", semanticType: "Height", values: values(1)),
                .init(label: "DeflectionRetrace", semanticType: "Deflection", values: values(-0.5)),
                .init(label: "PhaseRetrace", semanticType: "Phase", values: phase)
            ],
            xScale: 2e-7, yScale: 3e-7, xUnit: "m", yUnit: "m", dataUnit: dataUnit
        )
    }

    static func writeFixture(seed: Float = 0, dataUnit: String = "m", name: String = "fixture.ibw") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "SpinLab_Task5A_src_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: name)
        try fixtureIBW(seed: seed, dataUnit: dataUnit).write(to: url)
        return url
    }

    @discardableResult
    static func ingest(_ s: Scenario, file: URL? = nil, targets: [String]? = nil, op: String = UUID().uuidString, reuse: String? = nil) throws -> AssetIngestResult {
        let url = try file ?? writeFixture()
        return try s.service.ingestAsset(
            sourceFileURL: url, adapter: AFMIBWStandardizationAdapter(), targetSampleUIDs: targets ?? [s.uidA],
            operationID: op, reuseSourceID: reuse, rootURL: s.root
        )
    }

    static func exists(_ s: Scenario, _ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: s.root.appending(path: rel).path)
    }

    static func bitEqual(_ a: CanonicalAFMDataset, _ b: CanonicalAFMDataset) -> Bool {
        func bits(_ v: [Double]) -> [UInt64] { v.map(\.bitPattern) }
        guard a.title == b.title, a.sourceRef == b.sourceRef, a.sourceMetadata == b.sourceMetadata,
              bits(a.xCoordinates) == bits(b.xCoordinates), bits(a.yCoordinates) == bits(b.yCoordinates),
              a.channels.count == b.channels.count else { return false }
        for (x, y) in zip(a.channels, b.channels) {
            guard x.id == y.id, x.sourceIndex == y.sourceIndex, x.sourceLabel == y.sourceLabel,
                  x.semanticTypeRaw == y.semanticTypeRaw, x.displayLabel == y.displayLabel,
                  x.canonicalUnit == y.canonicalUnit, x.sourceUnit == y.sourceUnit, x.provenance == y.provenance,
                  x.values.map(bits) == y.values.map(bits) else { return false }
        }
        return true
    }

    static func expectedDataset(from file: URL) throws -> CanonicalAFMDataset {
        try AFMInputAdapter.build(from: Data(contentsOf: file), sourceRef: file.path).dataset
    }
}
