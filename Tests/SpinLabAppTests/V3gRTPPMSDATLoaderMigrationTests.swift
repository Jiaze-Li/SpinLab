import Testing
import Foundation
@testable import SpinLabApp

// Phase 3g: RT PPMS .dat migration to the shared PPMSDATLoader (mirrors Phase 3f's AHE
// migration). Architecture guards proving RT's raw PPMS parsing now goes exclusively through
// PPMSDATLoader, with no second active raw PPMS parser left for RT and no RT-specific
// interpretation (bridge -> Rxx, Resistance/Resistivity fallback) leaking into the shared loader.

@Suite("Phase 3g RT PPMSDATLoader Migration")
struct V3gRTPPMSDATLoaderMigrationTests {

    private static let projectRoot: URL = {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()  // SpinLabAppTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
    }()

    @Test("raw PPMS file I/O for RT occurs only through PPMSDATLoader")
    func rawFileIOOnlyInSharedLoaderForRT() throws {
        let useCasesDir = Self.projectRoot.appendingPathComponent("Sources/SpinLabApp/UseCases", isDirectory: true)
        let ioSites = try swiftFilesContaining(pattern: "String(contentsOf:", under: useCasesDir)
        #expect(!ioSites.contains("RTPPMSDatParser.swift"),
                "RTPPMSDatParser must no longer perform raw file I/O directly — it must delegate to PPMSDATLoader")
        #expect(ioSites.contains("PPMSDATLoader.swift"),
                "PPMSDATLoader must own raw file I/O for the shared PPMS .dat grammar")
    }

    @Test("RTPPMSDatParser no longer performs [Header]/[Data] grammar detection itself")
    func noDuplicateHeaderScanForRT() throws {
        let adapterURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/RTPPMSDatParser.swift")
        let contents = try String(contentsOf: adapterURL, encoding: .utf8)
        #expect(!contents.contains("firstIndex(where:"),
                "RTPPMSDatParser must not re-implement [Header]/[Data] line scanning — that belongs to PPMSDATLoader only")
        #expect(!contents.contains(".components(separatedBy: \",\")"),
                "RTPPMSDatParser must not re-implement CSV row splitting — PPMSDATLoader already provides parsed rows")
        #expect(contents.contains("PPMSDATLoader"),
                "RTPPMSDatParser must delegate raw parsing to PPMSDATLoader")

        let loaderURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/PPMSDATLoader.swift")
        let loaderContents = try String(contentsOf: loaderURL, encoding: .utf8)
        #expect(loaderContents.contains("firstIndex(of: \"[Data]\")"),
                "PPMSDATLoader must own the single [Header]/[Data] detection for this grammar")
    }

    @Test("PPMSDATLoader does not depend on RT workflow types (bridge/Rxx interpretation stays out)")
    func loaderHasNoRTWorkflowDependency() throws {
        let loaderURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/PPMSDATLoader.swift")
        let contents = try String(contentsOf: loaderURL, encoding: .utf8)
        // Note: "Rxx"/"Rxy" appear legitimately in the loader's own doc comments explaining that it
        // deliberately does *not* own that interpretation, so those substrings aren't guarded here —
        // only concrete RT type/function references are.
        let forbidden = ["RTPPMSDatParser", "AnalyzeRTWorkflowUseCase", "RTAnalysisResult",
                          "bridgeIndex(forChannel"]
        for name in forbidden {
            #expect(!contents.contains(name),
                    "PPMSDATLoader must not reference \(name) — bridge -> Rxx interpretation is RT workflow-owned")
        }
    }

    @Test("AnalyzeRTWorkflowUseCase's PPMS .dat path performs no raw file I/O of its own")
    func useCaseDoesNoRawIO() throws {
        let useCaseURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/AnalyzeRTWorkflowUseCase.swift")
        let contents = try String(contentsOf: useCaseURL, encoding: .utf8)
        #expect(!contents.contains("String(contentsOf:"),
                "AnalyzeRTWorkflowUseCase must not perform raw file I/O directly")
    }

    @Test("RT workflow layer may depend on PPMSDATLoader")
    func rtWorkflowMayDependOnLoader() throws {
        let parserURL = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases/RTPPMSDatParser.swift")
        let contents = try String(contentsOf: parserURL, encoding: .utf8)
        #expect(contents.contains("PPMSDATLoader().loadRawTable"),
                "RTPPMSDatParser is expected to consume PPMSDATLoader.loadRawTable directly")
    }

    // MARK: - Helpers

    private func swiftFilesContaining(pattern: String, under dir: URL) throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }

        var matches: [String] = []
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if contents.contains(pattern) {
                matches.append(url.lastPathComponent)
            }
        }
        return matches
    }
}
