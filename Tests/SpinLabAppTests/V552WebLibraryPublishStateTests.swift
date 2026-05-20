import Testing
import Foundation
@testable import SpinLabApp

@MainActor
@Suite("V5.5.2 WebLibraryPublishState")
struct V552WebLibraryPublishStateTests {

    @Test("finishWebLibraryPublish shows success summary and site")
    func finishSuccess() {
        let store = TestFixtures.makeStore()
        store.beginWebLibraryPublish()
        store.appendWebLibraryPublishOutput(kind: .stdout, line: "Cloudflare Pages will redeploy automatically")

        store.finishWebLibraryPublish(exitCode: 0)

        #expect(store.webLibraryPublishState.isRunning == false)
        #expect(store.webLibraryPublishState.statusMessage == LibraryFeatureStore.WebLibraryPublishState.publishedSuccessfullyMessage)
        #expect(store.webLibraryPublishState.summaryMessage == LibraryFeatureStore.WebLibraryPublishState.publishedSiteMessage)
        #expect(store.webLibraryPublishState.completedAt != nil)
    }

    @Test("finishWebLibraryPublish shows no changes status when script reports no changes")
    func finishNoChanges() {
        let store = TestFixtures.makeStore()
        store.beginWebLibraryPublish()
        store.appendWebLibraryPublishOutput(kind: .stdout, line: "No web snapshot changes to publish")

        store.finishWebLibraryPublish(exitCode: 0)

        #expect(store.webLibraryPublishState.statusMessage == LibraryFeatureStore.WebLibraryPublishState.noChangesMessage)
        #expect(store.webLibraryPublishState.summaryMessage == nil)
    }

    @Test("finishWebLibraryPublish shows failure summary from stderr")
    func finishFailure() {
        let store = TestFixtures.makeStore()
        store.beginWebLibraryPublish()
        store.appendWebLibraryPublishOutput(kind: .stderr, line: "fatal: unable to access repository")

        store.finishWebLibraryPublish(exitCode: 1)

        #expect(store.webLibraryPublishState.statusMessage == LibraryFeatureStore.WebLibraryPublishState.publishFailedMessage)
        #expect(store.webLibraryPublishState.summaryMessage == "fatal: unable to access repository")
        #expect(store.webLibraryPublishState.completedAt != nil)
    }
}

private enum TestFixtures {
    @MainActor
    static func makeStore() -> LibraryFeatureStore {
        let store = LibraryFeatureStore()
        store.librarySettings.rootPath = nil
        return store
    }
}
