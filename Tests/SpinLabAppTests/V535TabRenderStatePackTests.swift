import Foundation
import XCTest
@testable import SpinLabApp

final class V535TabRenderStatePackTests: XCTestCase {

    func testCodableRoundtrip() throws {
        let state = TabRenderState(hiddenPointLabelIndicesBySeries: ["0": [1, 3]])

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TabRenderState.self, from: data)

        XCTAssertEqual(decoded.hiddenPointLabelIndicesBySeries, ["0": [1, 3]])
    }

    func testOldPackMissingField() throws {
        let json = """
        {
          "titleOverride": "T",
          "xLabelOverride": "X",
          "yLabelOverride": "Y",
          "seriesLabelOverrides": {"0": "S0"}
        }
        """

        let decoded = try JSONDecoder().decode(TabRenderState.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.hiddenPointLabelIndicesBySeries, [:])
    }

    func testEmptyJsonDecodes() throws {
        let decoded = try JSONDecoder().decode(TabRenderState.self, from: Data("{}".utf8))

        XCTAssertNil(decoded.legendPoint)
        XCTAssertEqual(decoded.titleOverride, "")
        XCTAssertEqual(decoded.xLabelOverride, "")
        XCTAssertEqual(decoded.yLabelOverride, "")
        XCTAssertEqual(decoded.seriesLabelOverrides, [:])
        XCTAssertEqual(decoded.hiddenPointLabelIndicesBySeries, [:])
    }
}
