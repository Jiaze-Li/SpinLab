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

    // MARK: - INV-13: WorkflowID single definition in Domain/Workflow/

    // INV-13a: WorkflowID is defined in Domain/Workflow/
    @Test("INV-13a: WorkflowID enum is defined in Domain/Workflow")
    func workflowIDDefinedInDomain() throws {
        let domainDir = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/Domain/Workflow", isDirectory: true)

        let found = try swiftFilesContaining(pattern: "enum WorkflowID:", under: domainDir)
        #expect(!found.isEmpty,
                "WorkflowID must be defined in Sources/SpinLabApp/Domain/Workflow/ — found in: \(found)")
    }

    // INV-13b: WorkflowID has no duplicate definition elsewhere in Sources
    @Test("INV-13b: WorkflowID has exactly one definition across all Sources")
    func workflowIDDefinedOnce() throws {
        let sourcesDir = Self.projectRoot
            .appendingPathComponent("Sources", isDirectory: true)

        let found = try swiftFilesContaining(pattern: "enum WorkflowID:", under: sourcesDir)
        #expect(found.count == 1,
                "WorkflowID must be defined exactly once — found \(found.count) definition(s) in: \(found)")
    }

    // MARK: - INV-12: LibraryModels three-tier split

    // INV-12a: core domain types (LibrarySample, LibraryIndex) live in Library/Domain/
    @Test("INV-12a: LibrarySample domain entity is defined in Library/Domain")
    func librarySampleInDomain() throws {
        let domainDir = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/Library/Domain", isDirectory: true)

        let found = try swiftFilesContaining(pattern: "struct LibrarySample:", under: domainDir)
        #expect(!found.isEmpty,
                "LibrarySample must be in Sources/SpinLabApp/Library/Domain/ — found in: \(found)")
    }

    // INV-12b: UI projection types (LibraryPreview, LibraryRefreshReview) are NOT in Library/Domain/
    @Test("INV-12b: LibraryPreview UI projection is absent from Library/Domain")
    func libraryPreviewAbsentFromDomain() throws {
        let domainDir = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/Library/Domain", isDirectory: true)

        let found = try swiftFilesContaining(pattern: "struct LibraryPreview", under: domainDir)
        #expect(found.isEmpty,
                "LibraryPreview UI projection must not be in Library/Domain/ — found in: \(found)")
    }

    // INV-12c: UI projection types are not used by the UseCase layer
    @Test("INV-12c: UseCases do not reference UI-only Library projections")
    func useCasesDoNotUseLibraryProjections() throws {
        let useCasesDir = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/UseCases", isDirectory: true)

        let uiOnlyTypes = ["LibraryPreview", "LibraryPreviewBatchGroup", "LibraryRefreshReview",
                           "LibrarySyncBatchStatus", "LibraryDiff"]
        var violations: [String] = []

        for typeName in uiOnlyTypes {
            let found = try swiftFilesContaining(pattern: typeName, under: useCasesDir)
            if !found.isEmpty {
                violations.append("\(typeName) found in: \(found)")
            }
        }

        #expect(violations.isEmpty,
                "UseCase layer must not reference Library UI projections — violations: \(violations)")
    }

    // MARK: - INV-14: FilenameRuleSetSchema lives in Domain/Routing; compiled types stay in Import

    // INV-14a: FilenameRuleSetSchema enum is defined in Domain/Routing/
    @Test("INV-14a: FilenameRuleSetSchema is defined in Domain/Routing")
    func filenameRuleSchemaInDomain() throws {
        let domainDir = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/Domain/Routing", isDirectory: true)

        let found = try swiftFilesContaining(pattern: "enum FilenameRuleSetSchema", under: domainDir)
        #expect(!found.isEmpty,
                "FilenameRuleSetSchema must be in Sources/SpinLabApp/Domain/Routing/ — found in: \(found)")
    }

    // INV-14b: FilenameRuleSetSchema is NOT defined in Import/Rules/
    @Test("INV-14b: FilenameRuleSetSchema is absent from Import/Rules")
    func filenameRuleSchemaAbsentFromImport() throws {
        let importDir = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/Import/Rules", isDirectory: true)

        let found = try swiftFilesContaining(pattern: "enum FilenameRuleSetSchema", under: importDir)
        #expect(found.isEmpty,
                "FilenameRuleSetSchema must not be defined in Import/Rules/ — found in: \(found)")
    }

    // INV-14c: CompiledMatchSpec (compiled/runtime type) is NOT in Domain/Routing/
    @Test("INV-14c: CompiledMatchSpec compiled type is absent from Domain/Routing")
    func compiledMatchSpecAbsentFromDomain() throws {
        let domainDir = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/Domain/Routing", isDirectory: true)

        let found = try swiftFilesContaining(pattern: "struct CompiledMatchSpec", under: domainDir)
        #expect(found.isEmpty,
                "CompiledMatchSpec must not leak into Domain/Routing/ — found in: \(found)")
    }

    // INV-14d: FilenameRuleSet evaluator struct remains in Import/Rules/
    @Test("INV-14d: FilenameRuleSet evaluator struct is defined in Import/Rules")
    func filenameRuleSetEvaluatorInImport() throws {
        let importDir = Self.projectRoot
            .appendingPathComponent("Sources/SpinLabApp/Import/Rules", isDirectory: true)

        let found = try swiftFilesContaining(pattern: "struct FilenameRuleSet:", under: importDir)
        #expect(!found.isEmpty,
                "FilenameRuleSet evaluator must remain in Sources/SpinLabApp/Import/Rules/ — found in: \(found)")
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
