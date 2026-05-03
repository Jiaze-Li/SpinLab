import Testing
import Foundation
@testable import SpinLabApp

@MainActor
@Suite("V5.1.14 RestoreAnalysisPackUseCase Stateless")
struct V5114RestoreUseCaseStatelessTests {

    // INV-15a: stateless struct — no stored instance properties
    @Test("INV-15a: RestoreAnalysisPackUseCase has no stored instance properties")
    func useCaseHasNoStoredProperties() {
        let mirror = Mirror(reflecting: RestoreAnalysisPackUseCase())
        #expect(mirror.children.isEmpty, "UseCase must be stateless — no stored properties")
    }

    // INV-15b: execute routes call to injected vault capability
    @Test("INV-15b: execute calls injected vault, returns pack on success")
    func executeCallsFakeVault() {
        let fake = FakeVaultReading()
        let pack = fixturePack()
        fake.stubbedPack = pack

        let result = RestoreAnalysisPackUseCase().execute(packID: pack.id, vault: fake)

        #expect(fake.getCallCount == 1, "vault.get must be called once per execute")
        guard case .success(let loaded) = result else {
            Issue.record("Expected .success but got failure")
            return
        }
        #expect(loaded.id == pack.id)
    }

    // INV-15c: pack not found → typed failure
    @Test("INV-15c: execute returns packNotFound failure when vault returns nil")
    func executeFailsWhenPackMissing() {
        let fake = FakeVaultReading()
        fake.stubbedPack = nil
        let missingID = UUID()

        let result = RestoreAnalysisPackUseCase().execute(packID: missingID, vault: fake)

        guard case .failure(let error) = result else {
            Issue.record("Expected .failure but got success")
            return
        }
        guard case .packNotFound(let id) = error else {
            Issue.record("Expected .packNotFound")
            return
        }
        #expect(id == missingID)
    }

    // INV-2 still holds: vault state unchanged after execute read
    @Test("INV-2 regression: execute read does not mutate vault pack count")
    func vaultCountUnchangedAfterRestore() {
        let vault = AnalysisVault()
        let pack = fixturePack()
        vault.add(pack)
        let countBefore = vault.packs.count

        _ = RestoreAnalysisPackUseCase().execute(packID: pack.id, vault: vault)

        #expect(vault.packs.count == countBefore, "restore must not add or remove vault entries")
    }

    private func fixturePack() -> AnalysisPack {
        AnalysisPack(
            label: "UseCase Test Pack",
            workflowID: "3omega",
            filePaths: ["/tmp/fixture.dat"],
            sampleKeys: ["sample-A"],
            config: Data("{}".utf8),
            result: Data("{}".utf8)
        )
    }
}

@MainActor
private final class FakeVaultReading: AnalysisVaultReading {
    private(set) var getCallCount = 0
    var stubbedPack: AnalysisPack? = nil

    func get(id: AnalysisPack.ID) -> AnalysisPack? {
        getCallCount += 1
        return stubbedPack
    }
}
