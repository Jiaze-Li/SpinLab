import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.12 InboxViewModel projection", .serialized)
struct V5112InboxViewModelProjectionTests {

    // MARK: - Fixtures

    private func makePending(fileName: String) -> SpinLabDomain.PendingImport {
        SpinLabDomain.PendingImport(
            workflow: .amrPhe,
            fileName: fileName,
            sourceFilePath: "/tmp/\(fileName)",
            originalFilePath: "/tmp/\(fileName)",
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints()
        )
    }

    // MARK: - Tests
    // Without routing rules loaded, all pending imports resolve to reviewRequired verdict.

    @Test("projection returns zero counts when pending queue is empty")
    func emptyQueueProducesZeroCounts() {
        let appState = SpinLabAppState()
        appState.inbox.pendingImports = []
        let viewModel = InboxViewModel()

        let projection = viewModel.projection(from: appState)

        #expect(projection.libraryMatchedCount == 0)
        #expect(projection.reviewRequiredCount == 0)
        #expect(projection.filteredPendingImports.isEmpty)
    }

    @Test("projection.reviewRequiredCount equals pending count when none are library-matched")
    func reviewRequiredCountEqualsTotal_whenNoneMatched() {
        let appState = SpinLabAppState()
        appState.inbox.pendingImports = [
            makePending(fileName: "a.dat"),
            makePending(fileName: "b.dat"),
            makePending(fileName: "c.dat"),
        ]
        let viewModel = InboxViewModel()

        let projection = viewModel.projection(from: appState)

        #expect(projection.libraryMatchedCount == 0)
        #expect(projection.reviewRequiredCount == 3)
    }

    @Test("projection.filteredPendingImports respects .all filter")
    func filteredImports_allFilter() {
        let p1 = makePending(fileName: "a.dat")
        let p2 = makePending(fileName: "b.dat")
        let appState = SpinLabAppState()
        appState.inbox.pendingImports = [p1, p2]

        let viewModel = InboxViewModel()
        viewModel.fileFilter = .all
        let projection = viewModel.projection(from: appState)

        #expect(projection.filteredPendingImports.count == 2)
    }

    @Test("projection.filteredPendingImports respects .reviewRequired filter when none are matched")
    func filteredImports_reviewRequiredFilter_returnsAll_whenNoneMatched() {
        let p1 = makePending(fileName: "a.dat")
        let p2 = makePending(fileName: "b.dat")
        let appState = SpinLabAppState()
        appState.inbox.pendingImports = [p1, p2]

        let viewModel = InboxViewModel()
        viewModel.fileFilter = .reviewRequired
        let projection = viewModel.projection(from: appState)

        #expect(projection.filteredPendingImports.count == 2)
    }

    @Test("projection.filteredPendingImports respects .libraryMatched filter and returns empty when none matched")
    func filteredImports_libraryMatchedFilter_returnsEmpty_whenNoneMatched() {
        let p1 = makePending(fileName: "a.dat")
        let appState = SpinLabAppState()
        appState.inbox.pendingImports = [p1]

        let viewModel = InboxViewModel()
        viewModel.fileFilter = .libraryMatched
        let projection = viewModel.projection(from: appState)

        #expect(projection.filteredPendingImports.isEmpty)
    }

    @Test("projection.routePresentationByID contains an entry for each pending import")
    func routePresentationByIDContainsAllPending() {
        let p1 = makePending(fileName: "a.dat")
        let p2 = makePending(fileName: "b.dat")
        let appState = SpinLabAppState()
        appState.inbox.pendingImports = [p1, p2]

        let viewModel = InboxViewModel()
        let projection = viewModel.projection(from: appState)

        #expect(projection.routePresentationByID.count == 2)
        #expect(projection.routePresentationByID[p1.id] != nil)
        #expect(projection.routePresentationByID[p2.id] != nil)
    }

    @Test("projection reflects fileFilter change immediately")
    func projectionReflectsFileFilterChange() {
        let p1 = makePending(fileName: "a.dat")
        let p2 = makePending(fileName: "b.dat")
        let appState = SpinLabAppState()
        appState.inbox.pendingImports = [p1, p2]

        let viewModel = InboxViewModel()
        viewModel.fileFilter = .all
        #expect(viewModel.projection(from: appState).filteredPendingImports.count == 2)

        viewModel.fileFilter = .libraryMatched
        #expect(viewModel.projection(from: appState).filteredPendingImports.isEmpty)
    }
}
