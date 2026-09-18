import Foundation
import Testing
@testable import SpinLabApp

/// Real-file smoke test against a representative Asylum Research `.ibw` on this development
/// machine. The file is never committed to the repo (per task instructions) — this test looks
/// it up by absolute path and skips gracefully (not a failure) when the file isn't present, so
/// the suite stays green on any other machine or CI.
@Suite("AFM real-file smoke (local machine only)")
struct AFMRealFileSmokeTests {

    private static let candidatePaths: [String] = [
        "/Users/jack/Library/Group Containers/UBF8T346G9.OneDriveStandaloneSuite/OneDrive - National University of Singapore.noindex/OneDrive - National University of Singapore/Desktop/Y1 MRAM/experiment results/sample data/LiJiaze AFM/LSMO/LSMO13_CONTACT_0000.ibw",
    ]

    private func locateRepresentativeFile() -> URL? {
        for path in Self.candidatePaths where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    @Test("representative file parses as 256×256×3, ~20µm×20µm, defaulting to Height")
    func representativeFileSmoke() throws {
        guard let url = locateRepresentativeFile() else {
            return   // not present on this machine — not a failure, just nothing to verify here
        }

        let output = try AFMInputAdapter.load(fileURL: url)
        let dataset = output.dataset

        #expect(dataset.xCoordinates.count == 256)
        #expect(dataset.yCoordinates.count == 256)
        #expect(dataset.channels.count == 3)

        let labels = Set(dataset.channels.map(\.sourceLabel))
        #expect(labels == ["HeightRetrace", "DeflectionRetrace", "ZSensorRetrace"])

        let xSpan = dataset.xCoordinates.last! - dataset.xCoordinates.first!
        let ySpan = dataset.yCoordinates.last! - dataset.yCoordinates.first!
        #expect(abs(xSpan - 20.0) < 0.1, "expected ~20 µm fast-scan span, got \(xSpan)")
        #expect(abs(ySpan - 20.0) < 0.1, "expected ~20 µm slow-scan span, got \(ySpan)")

        let resolution = AFMChannelResolver.resolveDefaultChannel(in: dataset.channels)
        #expect(resolution.channel?.sourceLabel == "HeightRetrace")
        #expect(resolution.warning == nil)

        let height = dataset.channels.first { $0.sourceLabel == "HeightRetrace" }!
        #expect(height.canonicalUnit == "nm")
        #expect(height.provenance.planefit != nil, "source Planefit/Flatten provenance should be traceable")

        // Source provenance is captured but must not silently flip on SpinLab's own processing —
        // that policy lives in AFMProcessingConfiguration's default (Phase 3), not here; this
        // test only asserts the provenance itself round-trips through the adapter.
        #expect(dataset.sourceMetadata.sourceWidth == 256)
        #expect(dataset.sourceMetadata.sourceHeight == 256)
    }
}
