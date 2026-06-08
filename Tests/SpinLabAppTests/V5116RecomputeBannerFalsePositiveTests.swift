import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.16 Recompute Banner False Positive")
struct V5116RecomputeBannerFalsePositiveTests {

    /// 假阳性场景：sidecar fingerprint 旧、字段实质未变
    /// （生产里 547 个测量都走这条 — buildDiffItems 全部为 .noChange items）
    @Test("staleCount stays 0 when fingerprint stale but parsed fields equivalent")
    func staleCount_zero_when_parsed_fields_equivalent() throws {
        let bundledDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SpinLabApp/config")
        let savedPaths = RuleLoader.currentBookPaths
        RuleLoader.configure(bookPaths: RulesConfigPaths(configDirectoryURL: bundledDir), internalPaths: AppInternalPaths())
        defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }

        let rootURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileName = "RT_80K_1mA_PN40_AHE.dat"
        let sourceURL = rootURL.appending(path: fileName)
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

        // fixture 前提：filename 必须真被规则匹配出 conditions
        // 否则 buildDiffItems 不走 .noChange 路径，复现不出生产现象
        try #require(snapshot.fields.conditions.isEmpty == false)

        snapshot.ruleSetFingerprint = "v0:stale-but-field-equivalent"

        let sidecar = SpinLabFileSidecar(
            workflow: "AHE",
            workflowDisplayName: "AHE",
            channels: [],
            sourceFilePath: sourceURL.path,
            appliedAt: Date(timeIntervalSince1970: 0),
            ruleSnapshot: snapshot
        )
        let sidecarURL = rootURL.appending(path: "\(fileName).spinlab.json")
        try writeSidecar(sidecar, to: sidecarURL)

        let service = LibrarySidecarService(libraryStore: LibraryStore())
        let staleCount = service.computeStaleCount(
            rootURL: rootURL,
            currentFingerprint: loadResult.ruleSetFingerprint
        )
        let diff = service.computeRecomputeDiff(rootURL: rootURL)

        #expect(diff.allSatisfy { $0.status == .noChange })
        #expect(
            staleCount == 0,
            "staleCount=\(staleCount) 但 diff 全是 .noChange — 横幅假阳性"
        )
    }

    /// 反向 case：真有字段需要更新时，横幅 staleCount 必须计入
    @Test("staleCount > 0 when an actionable field diff exists")
    func staleCount_positive_when_actionable_diff() throws {
        let bundledDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SpinLabApp/config")
        let savedPaths = RuleLoader.currentBookPaths
        RuleLoader.configure(bookPaths: RulesConfigPaths(configDirectoryURL: bundledDir), internalPaths: AppInternalPaths())
        defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }

        let rootURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileName = "RT_80K_1mA_PN40_AHE.dat"
        let sourceURL = rootURL.appending(path: fileName)
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

        // 篡改一个 condition 值，使 sidecar 与"用当前规则重新解析"出现真实差异
        guard let firstKey = snapshot.fields.conditions.keys.sorted().first else {
            Issue.record("fixture 前提：parser 必须解析出至少一个 condition")
            return
        }
        snapshot.fields.conditions[firstKey] = SourcedValue(value: "STALE", source: "rule:legacy")
        snapshot.ruleSetFingerprint = "v0:stale-with-real-diff"

        let sidecar = SpinLabFileSidecar(
            workflow: "AHE",
            workflowDisplayName: "AHE",
            channels: [],
            sourceFilePath: sourceURL.path,
            appliedAt: Date(timeIntervalSince1970: 0),
            ruleSnapshot: snapshot
        )
        let sidecarURL = rootURL.appending(path: "\(fileName).spinlab.json")
        try writeSidecar(sidecar, to: sidecarURL)

        let service = LibrarySidecarService(libraryStore: LibraryStore())
        let staleCount = service.computeStaleCount(
            rootURL: rootURL,
            currentFingerprint: loadResult.ruleSetFingerprint
        )
        let diff = service.computeRecomputeDiff(rootURL: rootURL)

        #expect(diff.contains(where: { $0.status == .willUpdate }))
        #expect(staleCount == 1, "actionable diff 必须计入 banner staleCount")
    }

    /// Manual-override-only 场景：fingerprint 旧 + 仅 userOverrides 非空，
    /// 字段实质未变。如果横幅口径包含 .manualOverride，会显示但用户点开后
    /// "确认重算并应用" 按钮 disabled（按钮只看 group0），仍是假阳性变种。
    @Test("staleCount stays 0 when only manual overrides exist on stale fingerprint")
    func staleCount_zero_when_only_manual_overrides() throws {
        let bundledDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SpinLabApp/config")
        let savedPaths = RuleLoader.currentBookPaths
        RuleLoader.configure(bookPaths: RulesConfigPaths(configDirectoryURL: bundledDir), internalPaths: AppInternalPaths())
        defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }

        let rootURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileName = "RT_80K_1mA_PN40_AHE.dat"
        let sourceURL = rootURL.appending(path: fileName)
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

        guard let firstKey = snapshot.fields.conditions.keys.sorted().first else {
            Issue.record("fixture 前提：parser 必须解析出至少一个 condition")
            return
        }
        snapshot.ruleSetFingerprint = "v0:stale-with-manual-override-only"

        var overrides = SidecarUserOverrides.empty
        overrides.conditions[firstKey] = ManualValueOverride(
            value: "用户手填",
            reason: "manual",
            at: Date(timeIntervalSince1970: 0)
        )

        let sidecar = SpinLabFileSidecar(
            workflow: "AHE",
            workflowDisplayName: "AHE",
            channels: [],
            sourceFilePath: sourceURL.path,
            appliedAt: Date(timeIntervalSince1970: 0),
            ruleSnapshot: snapshot,
            userOverrides: overrides
        )
        let sidecarURL = rootURL.appending(path: "\(fileName).spinlab.json")
        try writeSidecar(sidecar, to: sidecarURL)

        let service = LibrarySidecarService(libraryStore: LibraryStore())
        let staleCount = service.computeStaleCount(
            rootURL: rootURL,
            currentFingerprint: loadResult.ruleSetFingerprint
        )
        let diff = service.computeRecomputeDiff(rootURL: rootURL)

        #expect(diff.contains(where: { $0.status == .manualOverride }))
        #expect(diff.allSatisfy { $0.status == .manualOverride || $0.status == .noChange })
        #expect(
            staleCount == 0,
            "staleCount=\(staleCount) 但 diff 只有 .manualOverride / .noChange — 用户无法点击 '确认重算并应用'"
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
