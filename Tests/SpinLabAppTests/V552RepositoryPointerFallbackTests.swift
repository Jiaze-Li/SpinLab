import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.5.2 RepositoryPointer fallback")
struct V552RepositoryPointerFallbackTests {

    @Test("load auto-writes a local development fallback pointer")
    func autoWritesLocalFallbackPointer() throws {
        let runtimeConfigDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-pointer-runtime-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config", isDirectory: true)
        let repoRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-pointer-repo-\(UUID().uuidString)", isDirectory: true)

        try createDirectory(at: runtimeConfigDir)
        try createDirectory(at: repoRoot.appendingPathComponent(".git", isDirectory: true))
        try createDirectory(at: repoRoot.appendingPathComponent("Sources/SpinLabApp/config", isDirectory: true))

        let pointer = RepositoryPointer.load(
            runtimeConfigDir: runtimeConfigDir,
            localDevelopmentRepoRootFallback: repoRoot,
            allowAutoWriteInTests: true
        )

        #expect(pointer?.repoRoot.standardizedFileURL.path == repoRoot.standardizedFileURL.path)
        #expect(pointer?.repositoryConfigDir.standardizedFileURL.path == repoRoot
            .appendingPathComponent("Sources/SpinLabApp/config", isDirectory: true)
            .standardizedFileURL.path)
        #expect(FileManager.default.fileExists(atPath: runtimeConfigDir.appendingPathComponent(".repo_pointer.json").path))
    }

    private func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
