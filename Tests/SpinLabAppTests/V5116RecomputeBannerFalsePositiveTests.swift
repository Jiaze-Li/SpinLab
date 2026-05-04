import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.16 Recompute Banner False Positive")
struct V5116RecomputeBannerFalsePositiveTests {

    /// 不变式：staleCount 与 recompute diff 必须共享同一事实源。
    /// 反例：fingerprint 旧但字段实质未变时，staleCount 不能 > 0（横幅假阳性）。
    @Test("staleCount stays 0 when fingerprint is stale but fields are field-equivalent")
    func staleCount_zero_when_fields_equivalent() throws {
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
        // 关键：fingerprint 是旧的（"v0:..."），但 snapshot 的字段是用当前规则刚解析得到的；
        // 所以 sidecar 与"用当前规则重新解析"的结果在字段层面完全一致。
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

        // 不变式：当字段实质未变时（diff 空），横幅 staleCount 也必须为 0。
        #expect(diff.isEmpty, "fixture 设计：字段应与新规则解析结果一致 → diff 空")
        #expect(
            staleCount == 0,
            "staleCount=\(staleCount) 但 diff 为空（横幅假阳性 — 修前必 fail）"
        )
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
