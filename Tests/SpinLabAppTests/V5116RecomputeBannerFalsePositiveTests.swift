import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.16 Recompute Banner False Positive")
struct V5116RecomputeBannerFalsePositiveTests {

    @Test("staleCount > 0 should imply non-empty recompute diff")
    func staleCount_implies_nonEmptyDiff() throws {
        let rootURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "unmatched_measurement.dat")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data())

        let loadResult = SpinLabRuleProvider.shared.loadResult()
        let parser = FilenameRuleParser(ruleSet: loadResult.ruleSet)
        let hints = parser.parse(from: sourceURL)
        var snapshot = SidecarCompositionUseCase.buildRuleSnapshot(
            hints: hints,
            ruleSetFingerprint: loadResult.ruleSetFingerprint,
            ruleSetVersion: loadResult.ruleSetVersion,
            evaluatedAt: Date(timeIntervalSince1970: 0)
        )
        snapshot.ruleSetFingerprint = "v0:stale-but-field-equivalent"

        let sidecar = SpinLabFileSidecar(
            workflow: "General",
            workflowDisplayName: "General",
            channels: [],
            sourceFilePath: sourceURL.path,
            appliedAt: Date(timeIntervalSince1970: 0),
            ruleSnapshot: snapshot
        )
        let sidecarURL = rootURL.appending(path: "unmatched_measurement.dat.spinlab.json")
        try writeSidecar(sidecar, to: sidecarURL)

        let service = LibrarySidecarService(libraryStore: LibraryStore())
        let staleCount = service.computeStaleCount(
            rootURL: rootURL,
            currentFingerprint: loadResult.ruleSetFingerprint
        )
        let diff = service.computeRecomputeDiff(rootURL: rootURL)

        #expect(staleCount > 0)
        #expect(diff.isEmpty)
        if staleCount > 0 {
            #expect(
                diff.isEmpty == false,
                "staleCount=\(staleCount) but diff is empty (false positive)"
            )
        }
    }

    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "spinlab-v5116-recompute-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeSidecar(_ sidecar: SpinLabFileSidecar, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(sidecar)
        try data.write(to: url, options: .atomic)
    }
}
