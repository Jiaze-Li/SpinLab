import Testing
import Foundation
@testable import SpinLabApp

// PR #148 corrective pass: PPMSDATLoader must locate the next non-empty Comment,... header after
// [Data], not assume it is the very next line — some historical RT files have one or more blank
// lines between [Data] and the header.

@Suite("PR #148 PPMSDATLoader blank-line-after-[Data] compatibility")
struct PR148PPMSDATLoaderBlankLineTests {
    private struct Fixture {
        let rootURL: URL
        private let fm = FileManager.default

        init() throws {
            rootURL = fm.temporaryDirectory.appending(
                path: "spinlab-pr148-ppmsdat-\(UUID().uuidString)", directoryHint: .isDirectory
            )
            try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        func write(name: String, content: String) throws -> URL {
            let url = rootURL.appending(path: name)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        func cleanup() { try? fm.removeItem(at: rootURL) }
    }

    private static let colHeader = "Comment,Time Stamp (sec),Temperature (K),Magnetic Field (Oe)"

    @Test("[Data] followed immediately by Comment,... still parses")
    func immediateCommentHeaderStillWorks() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let content = """
        [Header]
        TITLE, test
        [Data]
        \(Self.colHeader)
        ,0,80.0,10000.0
        """
        let url = try fixture.write(name: "immediate.dat", content: content)

        let loaded = try PPMSDATLoader().load(fileURL: url)
        #expect(loaded.rowCount == 1)
        #expect(loaded.signals.count == 4)
    }

    @Test("[Data] followed by one blank line then Comment,... parses")
    func oneBlankLineBeforeCommentHeaderParses() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let content = """
        [Header]
        TITLE, test
        [Data]

        \(Self.colHeader)
        ,0,80.0,10000.0
        """
        let url = try fixture.write(name: "one_blank.dat", content: content)

        let loaded = try PPMSDATLoader().load(fileURL: url)
        #expect(loaded.rowCount == 1)
        #expect(loaded.signals.count == 4)
        #expect(loaded.signals[2].rawLabel == "Temperature (K)")
    }

    @Test("[Data] followed by multiple blank lines then Comment,... parses")
    func multipleBlankLinesBeforeCommentHeaderParses() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let content = """
        [Header]
        TITLE, test
        [Data]



        \(Self.colHeader)
        ,0,80.0,10000.0
        ,1,81.0,9000.0
        """
        let url = try fixture.write(name: "multi_blank.dat", content: content)

        let loaded = try PPMSDATLoader().load(fileURL: url)
        #expect(loaded.rowCount == 2)
        #expect(loaded.signals.count == 4)
    }

    @Test("genuinely missing column header still fails")
    func genuinelyMissingHeaderStillFails() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let content = """
        [Header]
        TITLE, test
        [Data]
        ,0,80.0,10000.0
        ,1,81.0,9000.0
        """
        let url = try fixture.write(name: "missing_header.dat", content: content)

        #expect(throws: PPMSDATLoader.LoadError.self) {
            try PPMSDATLoader().load(fileURL: url)
        }
    }
}
