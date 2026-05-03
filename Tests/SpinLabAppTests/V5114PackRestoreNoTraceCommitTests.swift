import Testing
import Foundation
@testable import SpinLabApp

@Suite("V5.1.14 Pack Restore No Trace Commit")
@MainActor
struct V5114PackRestoreNoTraceCommitTests {

    private func fixturePackRaw() -> AnalysisPack {
        AnalysisPack(
            label: "Fixture Pack",
            workflowID: "3omega",
            filePaths: ["/tmp/fixture.dat"],
            sampleKeys: ["sample-A"],
            config: Data("{}".utf8),
            result: Data("{}".utf8)
        )
    }

    // INV-2a: vault.add() is idempotent — adding the same pack ID twice stays at one entry
    @Test("INV-2a: vault add idempotent by pack ID")
    func vaultAddIdempotent() {
        let vault = AnalysisVault()
        let pack = fixturePackRaw()

        vault.add(pack)
        #expect(vault.packs.count == 1)

        vault.add(pack) // second add with same ID
        #expect(vault.packs.count == 1, "duplicate add must not create extra entries")
    }

    // INV-2b: vault.get() (read path used by loadPack) does not modify vault state
    @Test("INV-2b: vault read does not add entries — pack count unchanged after restore read")
    func vaultReadDoesNotCommitTrace() {
        let vault = AnalysisVault()
        let pack = fixturePackRaw()
        vault.add(pack)

        let countAfterSave = vault.packs.count

        // loadPack reads from vault but must not call vault.add()
        let loaded = vault.get(id: pack.id)
        #expect(loaded != nil)
        #expect(vault.packs.count == countAfterSave,
                "restore read must not add a new vault entry")
    }
}
