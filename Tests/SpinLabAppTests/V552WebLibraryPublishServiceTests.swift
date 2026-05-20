import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.5.2 WebLibraryPublishService")
struct V552WebLibraryPublishServiceTests {

    @Test("publish script streams stdout and stderr lines")
    func streamsScriptOutput() async throws {
        let repoRoot = try makeTemporaryRepoRoot(
            scriptBody: """
            #!/usr/bin/env bash
            set -euo pipefail
            printf 'stdout-line-1\\n'
            printf 'stderr-line-1\\n' >&2
            printf 'stdout-line-2\\n'
            """
        )

        let service = WebLibraryPublishService()
        let lines = PublishOutputCollector()

        let exitCode = try await service.publishWebLibrary(repoRootURL: repoRoot) { kind, line in
            lines.append(kind: kind, line: line)
        }
        #expect(exitCode == 0)

        let capturedLines = lines.snapshot()
        #expect(capturedLines.contains(where: { $0.0 == .stdout && $0.1 == "stdout-line-1" }))
        #expect(capturedLines.contains(where: { $0.0 == .stdout && $0.1 == "stdout-line-2" }))
        #expect(capturedLines.contains(where: { $0.0 == .stderr && $0.1 == "stderr-line-1" }))
    }

    @Test("publish script returns non-zero exit status")
    func returnsNonZeroExitStatus() async throws {
        let repoRoot = try makeTemporaryRepoRoot(
            scriptBody: """
            #!/usr/bin/env bash
            set -euo pipefail
            printf 'before-fail\\n'
            printf 'failure-line\\n' >&2
            exit 7
            """
        )

        let service = WebLibraryPublishService()
        let lines = PublishOutputCollector()

        let exitCode = try await service.publishWebLibrary(repoRootURL: repoRoot) { kind, line in
            lines.append(kind: kind, line: line)
        }
        #expect(exitCode == 7)

        let capturedLines = lines.snapshot()
        #expect(capturedLines.contains(where: { $0.0 == .stdout && $0.1 == "before-fail" }))
        #expect(capturedLines.contains(where: { $0.0 == .stderr && $0.1 == "failure-line" }))
    }

    private func makeTemporaryRepoRoot(scriptBody: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-web-publish-\(UUID().uuidString)", isDirectory: true)
        let scriptsDir = root.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        let scriptURL = scriptsDir.appendingPathComponent("publish_web_library.sh")
        try scriptBody.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return root
    }
}

final class PublishOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [(WebLibraryPublishOutputKind, String)] = []

    func append(kind: WebLibraryPublishOutputKind, line: String) {
        lock.lock()
        lines.append((kind, line))
        lock.unlock()
    }

    func snapshot() -> [(WebLibraryPublishOutputKind, String)] {
        lock.lock()
        let snapshot = lines
        lock.unlock()
        return snapshot
    }
}
