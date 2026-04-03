import Foundation
import Testing
@testable import SpinLabApp

@Suite("V2.7.1 Duplicate Guard")
struct V271DuplicateGuardTests {
    @Test("accepts first file and rejects duplicate content fingerprint")
    func rejectsDuplicateContentFingerprint() {
        var guarder = DuplicateGuard()

        let firstAccepted = guarder.accepts(
            originalPath: "/tmp/a/PN20_RT.dat",
            contentFingerprint: "abc123"
        )
        let secondAccepted = guarder.accepts(
            originalPath: "/tmp/b/RENAMED_RT.dat",
            contentFingerprint: "ABC123"
        )

        #expect(firstAccepted)
        #expect(!secondAccepted)
    }

    @Test("rejects excluded content fingerprint before path checks")
    func rejectsExcludedFingerprint() {
        var guarder = DuplicateGuard(excludedContentFingerprints: ["deadbeef"])

        let accepted = guarder.accepts(
            originalPath: "/tmp/c/PN30_RT.dat",
            contentFingerprint: "DEADBEEF"
        )

        #expect(!accepted)
    }
}
