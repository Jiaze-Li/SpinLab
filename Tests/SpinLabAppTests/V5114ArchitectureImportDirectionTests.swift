import Testing
import Foundation

// INV-11: ThreeOmegaIngestionContracts split — UI tab enum must live in Features/Workbench,
// domain contracts must live in Workbench/Domain. Neither may cross into the other's directory.

@Suite("V5.1.14 Architecture Import Direction")
struct V5114ArchitectureImportDirectionTests {

    private static let projectRoot: URL = {
        // #filePath: .../Tests/SpinLabAppTests/V5114ArchitectureImportDirectionTests.swift
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()  // SpinLabAppTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
    }()

    // INV-11a: ThreeOmegaWorkbenchTab is defined in Features/Workbench/
    @Test("INV-11a: ThreeOmegaWorkbenchTab definition is in Features/Workbench")
    func threeOmegaTabDefinedInFeatures() throws {
        let featuresDir = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/Features/Workbench", isDirectory: true)

        let found = try swiftFilesContaining(pattern: "enum ThreeOmegaWorkbenchTab", under: featuresDir)
        #expect(!found.isEmpty,
                "ThreeOmegaWorkbenchTab must be defined in Sources/SpinLabApp/Features/Workbench/ — found in: \(found)")
    }

    // INV-11b: ThreeOmegaWorkbenchTab is NOT defined in Workbench/Domain
    @Test("INV-11b: ThreeOmegaWorkbenchTab is absent from Workbench/Domain")
    func threeOmegaTabAbsentFromDomain() throws {
        let domainDir = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/Workbench/Domain", isDirectory: true)

        let found = try swiftFilesContaining(pattern: "enum ThreeOmegaWorkbenchTab", under: domainDir)
        #expect(found.isEmpty,
                "ThreeOmegaWorkbenchTab must not leak into Workbench/Domain — found in: \(found)")
    }

    // INV-11c: ThreeOmegaIngestionResult domain type is defined in Workbench/Domain
    @Test("INV-11c: ThreeOmegaIngestionResult domain contract is in Workbench/Domain")
    func ingestionResultDefinedInWorkbenchDomain() throws {
        let domainDir = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/Workbench/Domain", isDirectory: true)

        let found = try swiftFilesContaining(pattern: "struct ThreeOmegaIngestionResult", under: domainDir)
        #expect(!found.isEmpty,
                "ThreeOmegaIngestionResult must be in Sources/SpinLabApp/Workbench/Domain/ — found in: \(found)")
    }

    // INV-11d: domain contract is NOT defined in Features
    @Test("INV-11d: ThreeOmegaIngestionResult is absent from Features")
    func ingestionResultAbsentFromFeatures() throws {
        let featuresDir = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/Features", isDirectory: true)

        let found = try swiftFilesContaining(pattern: "struct ThreeOmegaIngestionResult", under: featuresDir)
        #expect(found.isEmpty,
                "ThreeOmegaIngestionResult domain contract must not be in Features/ — found in: \(found)")
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
