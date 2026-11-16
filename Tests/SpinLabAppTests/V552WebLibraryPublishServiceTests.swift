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

        let exitCode = try await service.publishWebLibrary(repoRootURL: repoRoot, libraryRootURL: URL(fileURLWithPath: "/tmp/lib")) { kind, line in
            lines.append(kind: kind, line: line)
        }
        #expect(exitCode == 0)

        let capturedLines = lines.snapshot()
        #expect(capturedLines.contains(where: { $0.0 == .stdout && $0.1 == "stdout-line-1" }))
        #expect(capturedLines.contains(where: { $0.0 == .stdout && $0.1 == "stdout-line-2" }))
        #expect(capturedLines.contains(where: { $0.0 == .stderr && $0.1 == "stderr-line-1" }))
    }

    @Test("the selected Library is handed to the script as its only Library")
    func passesLibraryRoot() async throws {
        let repoRoot = try makeTemporaryRepoRoot(
            scriptBody: """
            #!/usr/bin/env bash
            printf 'root=%s\\n' "${SPINLAB_LIBRARY_ROOT:-unset}"
            """
        )
        let lines = PublishOutputCollector()
        _ = try await WebLibraryPublishService().publishWebLibrary(
            repoRootURL: repoRoot, libraryRootURL: URL(fileURLWithPath: "/chosen/library")
        ) { kind, line in lines.append(kind: kind, line: line) }
        #expect(lines.snapshot().contains(where: { $0.1 == "root=/chosen/library" }))
    }

    @Test("a process that cannot start fails at once instead of hanging")
    func launchFailureDoesNotHang() async throws {
        let repoRoot = try makeTemporaryRepoRoot(scriptBody: "#!/usr/bin/env bash\nexit 0\n")
        let service = WebLibraryPublishService(shellURL: URL(fileURLWithPath: "/no/such/shell"))

        let outcome: String = await withTaskGroup(of: String.self) { group in
            group.addTask {
                do {
                    _ = try await service.publishWebLibrary(repoRootURL: repoRoot, libraryRootURL: URL(fileURLWithPath: "/tmp/lib")) { _, _ in }
                    return "returned"
                } catch {
                    return "threw"
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                return "hung"
            }
            let first = await group.next() ?? "none"
            group.cancelAll()
            return first
        }
        #expect(outcome == "threw")
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

        let exitCode = try await service.publishWebLibrary(repoRootURL: repoRoot, libraryRootURL: URL(fileURLWithPath: "/tmp/lib")) { kind, line in
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
