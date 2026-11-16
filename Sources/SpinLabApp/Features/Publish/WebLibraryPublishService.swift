import Foundation

enum WebLibraryPublishOutputKind: Sendable {
    case stdout
    case stderr
}

protocol WebLibraryPublishingCapability: Sendable {
    /// `libraryRootURL` and `webRepoURL` come from SpinLab's settings; `publishRootURL` holds the bundled scripts/templates/schema.
    func publishWebLibrary(
        publishRootURL: URL,
        libraryRootURL: URL,
        webRepoURL: URL,
        onOutput: @escaping @Sendable (_ kind: WebLibraryPublishOutputKind, _ line: String) -> Void
    ) async throws -> Int32
}

struct WebLibraryPublishService: WebLibraryPublishingCapability {
    /// The shell that runs the script. Injectable so a launch failure can be tested.
    var shellURL = URL(fileURLWithPath: "/bin/bash")
    /// Override search paths for system `python3` and `git` pre-flight checks (nil uses `PATH` + standard macOS locations).
    var toolSearchPaths: [String]? = nil

    /// Validates that required system tools (`python3` and `git`) are executable.
    func checkSystemTools() -> String? {
        let fm = FileManager.default
        let searchDirs: [String]
        if let toolSearchPaths {
            searchDirs = toolSearchPaths
        } else {
            let envPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
                .split(separator: ":")
                .map(String.init)
            let defaults = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
            searchDirs = Array(NSOrderedSet(array: envPaths + defaults)) as? [String] ?? defaults
        }

        func isExecutable(_ tool: String) -> Bool {
            for dir in searchDirs where !dir.isEmpty {
                let candidate = URL(fileURLWithPath: dir).appending(path: tool).path
                if fm.isExecutableFile(atPath: candidate) {
                    return true
                }
            }
            return false
        }

        if !isExecutable("python3") {
            return "Python 3 (python3) is not available on this Mac. Install Python 3 or Command Line Tools and try again."
        }
        if !isExecutable("git") {
            return "Git (git) is not available on this Mac. Install Git or Command Line Tools and try again."
        }
        return nil
    }

    func publishWebLibrary(
        publishRootURL: URL,
        libraryRootURL: URL,
        webRepoURL: URL,
        onOutput: @escaping @Sendable (_ kind: WebLibraryPublishOutputKind, _ line: String) -> Void
    ) async throws -> Int32 {
        let scriptURL = publishRootURL.appending(path: "scripts/publish_web_library.sh")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw AppError.notFound("Publish script not found at \(scriptURL.path).")
        }
        if let missingToolMessage = checkSystemTools() {
            throw AppError.notFound(missingToolMessage)
        }

        let templateDirURL: URL = {
            let bundled = publishRootURL.appending(path: "WebLibraryTemplate")
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
            return publishRootURL.appending(path: "Resources/WebLibraryTemplate")
        }()
        let schemaURL: URL = {
            let bundled = publishRootURL.appending(path: "config/new_sample_form_schema.json")
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
            return publishRootURL.appending(path: "Sources/SpinLabApp/config/new_sample_form_schema.json")
        }()
        let harnessURL = publishRootURL.appending(path: "scripts/tests/web_library_compare_harness.js")

        let process = Process()
        process.executableURL = shellURL
        process.arguments = [
            scriptURL.path,
            "--library-root", libraryRootURL.path,
            "--web-repo", webRepoURL.path,
            "--template-dir", templateDirURL.path,
            "--schema-path", schemaURL.path,
            "--harness-path", harnessURL.path,
        ]
        process.currentDirectoryURL = publishRootURL
        var environment = ProcessInfo.processInfo.environment
        environment["SPINLAB_PUBLISH_ROOT"] = publishRootURL.path
        environment["SPINLAB_LIBRARY_ROOT"] = libraryRootURL.path
        environment["SPINLAB_WEB_LIBRARY_DIR"] = webRepoURL.path
        environment["SPINLAB_WEB_TEMPLATE_DIR"] = templateDirURL.path
        environment["SPINLAB_NEW_SAMPLE_SCHEMA_PATH"] = schemaURL.path
        environment["SPINLAB_PAGE_CHECK_HARNESS_PATH"] = harnessURL.path
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
