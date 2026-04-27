import Foundation
import XCTest
@testable import SpinLabApp

final class V535PointLabelVisibilityTests: XCTestCase {

    private enum TestTab: Hashable, Sendable {
        case first
        case second
    }

    @MainActor
    func testToggleReversible() {
        let manager = TabRenderManager<TestTab>(defaultTab: .first)

        manager.togglePointLabelVisibility(seriesIndex: 0, pointIndex: 0)
        manager.togglePointLabelVisibility(seriesIndex: 0, pointIndex: 0)

        let state = manager.state(for: .first)
        XCTAssertTrue(state.hiddenPointLabelIndicesBySeries.isEmpty)
    }

    @MainActor
    func testHidingOnlyAffectsLabel() {
        let manager = TabRenderManager<TestTab>(defaultTab: .first)

        manager.togglePointLabelVisibility(seriesIndex: 0, pointIndex: 2)

        let hidden = manager.hiddenPointLabelSet(for: .first)
        XCTAssertEqual(hidden[0] ?? [], Set([2]))
        XCTAssertNil(hidden[1])
    }

    @MainActor
    func testMultiSeriesIndexIndependent() {
        let manager = TabRenderManager<TestTab>(defaultTab: .first)

        manager.togglePointLabelVisibility(seriesIndex: 0, pointIndex: 0)

        let hidden = manager.hiddenPointLabelSet(for: .first)
        XCTAssertEqual(hidden[0] ?? [], Set([0]))
        XCTAssertFalse(hidden[1]?.contains(0) ?? false)
    }
}
