import Foundation
import Testing
@testable import SpinLabApp

@Suite("Keychain phone access token store")
struct KeychainPhoneAccessTokenStoreTests {
    private func store(
        tool: [String: String?],
        direct: [String: String?] = [:],
        directCalls: Counter = Counter()
    ) -> KeychainPhoneAccessTokenStore {
        KeychainPhoneAccessTokenStore(
            readViaSecurityTool: { tool[$0] ?? nil },
            readDirectly: { account in directCalls.count += 1; return direct[account] ?? nil }
        )
    }

    final class Counter { var count = 0 }

    @Test("Both values from the security tool make the token without touching the direct read")
    func toolGivesToken() {
        let calls = Counter()
        let token = store(tool: ["client-id": "abc", "client-secret": "xyz"], directCalls: calls).token()
        #expect(token == PhoneAccessToken(clientId: "abc", clientSecret: "xyz"))
        #expect(calls.count == 0)
    }

    @Test("When the tool yields nothing the direct read is used")
    func fallsBackToDirectRead() {
        let calls = Counter()
        let token = store(
            tool: ["client-id": "abc"],
            direct: ["client-secret": "xyz"],
            directCalls: calls
        ).token()
        #expect(token == PhoneAccessToken(clientId: "abc", clientSecret: "xyz"))
        #expect(calls.count == 1)
    }

    @Test("An empty tool answer counts as missing")
    func emptyAnswerFallsBack() {
        let token = store(tool: ["client-id": "", "client-secret": ""], direct: ["client-id": "a", "client-secret": "b"]).token()
        #expect(token == PhoneAccessToken(clientId: "a", clientSecret: "b"))
    }

    @Test("A missing secret everywhere means no token")
    func missingSecretMeansNoToken() {
        #expect(store(tool: ["client-id": "abc"]).token() == nil)
        #expect(store(tool: [:]).token() == nil)
    }

    @Test("The real tool returns nil for an account that does not exist, without hanging")
    func realToolMissingAccount() {
        #expect(KeychainPhoneAccessTokenStore.readWithSecurityTool(account: "spinlab-test-account-that-does-not-exist") == nil)
    }
}
