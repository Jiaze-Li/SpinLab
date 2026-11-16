import Foundation

enum WebLibraryPublishOutputKind: Sendable {
    case stdout
    case stderr
}

protocol WebLibraryPublishingCapability: Sendable {
    /// `libraryRootURL` is the Library SpinLab has selected; the script has no Library of its own.
    func publishWebLibrary(
        repoRootURL: URL,
        libraryRootURL: URL,
        onOutput: @escaping @Sendable (_ kind: WebLibraryPublishOutputKind, _ line: String) -> Void
    ) async throws -> Int32
}

struct WebLibraryPublishService: WebLibraryPublishingCapability {
    /// `libraryRootURL` is the Library SpinLab has selected; the script has no Library of its own.
    func publishWebLibrary(
        repoRootURL: URL,
        libraryRootURL: URL,
        onOutput: @escaping @Sendable (_ kind: WebLibraryPublishOutputKind, _ line: String) -> Void
    ) async throws -> Int32 {
        let scriptURL = repoRootURL.appending(path: "scripts/publish_web_library.sh")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw AppError.notFound("Publish script not found at \(scriptURL.path).")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.currentDirectoryURL = repoRootURL
        var environment = ProcessInfo.processInfo.environment
        environment["SPINLAB_LIBRARY_ROOT"] = libraryRootURL.path
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        async let stdoutResult = streamLines(
            from: stdoutPipe.fileHandleForReading,
            kind: .stdout,
            onOutput: onOutput
        )
        async let stderrResult = streamLines(
            from: stderrPipe.fileHandleForReading,
            kind: .stderr,
            onOutput: onOutput
        )

        try process.run()
        process.waitUntilExit()

        try await stdoutResult
        try await stderrResult

        return process.terminationStatus
    }

    private func streamLines(
        from handle: FileHandle,
        kind: WebLibraryPublishOutputKind,
        onOutput: @escaping @Sendable (_ kind: WebLibraryPublishOutputKind, _ line: String) -> Void
    ) async throws {
        for try await line in handle.bytes.lines {
            let trimmed = line.trimmingCharacters(in: .newlines)
            guard !trimmed.isEmpty else { continue }
            onOutput(kind, trimmed)
        }
    }
}
