import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.1.11 Align XY Series Order UseCase")
struct V5111AlignXYSeriesOrderUseCaseTests {

    @Test("no persisted order and no selection keeps analysis order")
    func noPersistedNoSelection() {
        assertAlignment(
            persistedOrder: nil,
            selectedHitIDs: [],
            analysisIdentifiers: ["a", "b", "c"],
            expected: ["a", "b", "c"]
        )
    }

    @Test("persisted order is preserved")
    func persistedNoSelection() {
        assertAlignment(
            persistedOrder: ["c", "a", "b"],
            selectedHitIDs: [],
            analysisIdentifiers: ["a", "b", "c"],
            expected: ["c", "a", "b"]
        )
    }

    @Test("selected identifiers move to front after persisted alignment")
    func persistedWithPartialSelection() {
        assertAlignment(
            persistedOrder: ["c", "a", "b"],
            selectedHitIDs: ["a"],
            analysisIdentifiers: ["a", "b", "c"],
            expected: ["a", "c", "b"]
        )
    }

    @Test("persisted order drops deleted identifiers")
    func persistedWithDeletedIdentifiers() {
        assertAlignment(
            persistedOrder: ["c", "x", "a"],
            selectedHitIDs: [],
            analysisIdentifiers: ["a", "b", "c"],
            expected: ["c", "a", "b"]
        )
    }

    @Test("persisted order with no overlap falls back to analysis order")
    func persistedWithNoOverlap() {
        assertAlignment(
            persistedOrder: ["d", "e"],
            selectedHitIDs: ["a"],
            analysisIdentifiers: ["a", "b", "c"],
            expected: ["a", "b", "c"]
        )
    }

    private func assertAlignment(
        persistedOrder: [String]?,
        selectedHitIDs: [String],
        analysisIdentifiers: [String],
        expected: [String],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let output = AlignXYSeriesOrderUseCase().execute(.init(
            analysisIdentifiers: analysisIdentifiers,
            persistedOrder: persistedOrder,
            selectedHitIDs: selectedHitIDs,
            legendReversed: true
        ))

        #expect(output.alignedOrder == expected, sourceLocation: sourceLocation)
        let n = expected.count
        for (index, id) in expected.enumerated() {
            #expect(output.legendIndexMap[id] == n - 1 - index, sourceLocation: sourceLocation)
        }
    }
}
