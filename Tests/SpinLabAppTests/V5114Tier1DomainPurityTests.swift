import Testing
import Foundation

// INV-17: Tier 1 Sources/Domain files must not contain filesystem/network I/O patterns.
// Only Codable/Hashable/Sendable pure value contracts belong in Sources/SpinLabApp/Domain/.

@Suite("V5.1.14 Tier 1 Domain Purity")
struct V5114Tier1DomainPurityTests {

    private static let domainDir: URL = {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()  // SpinLabAppTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
            .appendingPathComponent("Sources/SpinLabApp/Domain", isDirectory: true)
    }()

    // Forbidden I/O patterns in Tier 1 Domain files.
    private static let forbiddenPatterns: [String] = [
        "FileManager",
        "URLSession",
        "Data(contentsOf:",
        "FileHandle",
        "OutputStream",
        "InputStream",
    ]

    @Test("INV-17: Tier 1 Domain files contain no filesystem/network I/O patterns")
    func tier1DomainFilesArePure() throws {
        var violations: [String] = []

        let fm = FileManager.default
        guard fm.fileExists(atPath: Self.domainDir.path),
              let enumerator = fm.enumerator(
                at: Self.domainDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            Issue.record("Domain directory not found at \(Self.domainDir.path)")
            return
        }

        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            for pattern in Self.forbiddenPatterns {
                if contents.contains(pattern) {
                    violations.append("\(url.lastPathComponent): contains '\(pattern)'")
                }
            }
        }

        #expect(violations.isEmpty,
                "Tier 1 Domain must be pure contracts — violations: \(violations.joined(separator: "; "))")
    }
}
