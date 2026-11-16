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
    /// The shell that runs the script. Injectable so a launch failure can be tested.
    var shellURL = URL(fileURLWithPath: "/bin/bash")

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
        process.executableURL = shellURL
        process.arguments = [scriptURL.path]
        process.currentDirectoryURL = repoRootURL
        var environment = ProcessInfo.processInfo.environment
        environment["SPINLAB_LIBRARY_ROOT"] = libraryRootURL.path
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Launch first: if it fails, nothing is waiting on the pipes (their write ends are still held
        // here, so a reader started earlier would never see end-of-file and the publish would hang).
        do {
            try process.run()
        } catch {
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            throw error
        }

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
