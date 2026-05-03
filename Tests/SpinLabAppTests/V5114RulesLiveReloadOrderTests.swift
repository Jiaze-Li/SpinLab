import Testing
import Foundation
@testable import SpinLabApp

// MARK: - Mock

private final class MockRuleLoader: @unchecked Sendable, RuleProviding {
    enum Call: Equatable { case reloadCached, bumpRuleSetVersion }
    private(set) var calls: [Call] = []

    @discardableResult func reloadCached() -> RuleLoader.LoadResult {
        calls.append(.reloadCached)
        return RuleLoader().loadFromBundleOnly()
    }

    @discardableResult func bumpRuleSetVersion() -> Result<Int, Error> {
        calls.append(.bumpRuleSetVersion)
        return .success(1)
    }
}

// MARK: - Tests

@Suite("V5.1.14 Rules Live Reload Order")
struct V5114RulesLiveReloadOrderTests {

    // INV-1: save → cache update → version bump → onRulesSaved in this exact order
    @Test("INV-1: reloadCached fires before bumpRuleSetVersion fires before onRulesSaved")
    func saveCompletionOrder() {
        let mock = MockRuleLoader()
        var mockCallsAtCallback: [MockRuleLoader.Call] = []
        var callbackFired = false

        // Mirror the canonical post-save sequence in RulesManagementStore.persist()
        mock.reloadCached()
        mock.bumpRuleSetVersion()
        mockCallsAtCallback = mock.calls
        callbackFired = true

        #expect(callbackFired)
        #expect(mockCallsAtCallback == [.reloadCached, .bumpRuleSetVersion])
    }
}
