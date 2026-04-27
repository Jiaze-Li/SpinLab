import Foundation
import XCTest
@testable import SpinLabApp

final class V535SampleKeyLookupTests: XCTestCase {

    func testExactMatchReturnsSample() {
        let index = makeIndex(samples: [
            makeSample(id: "PN14||STO|001", numeric: ["氧压": "10 mTorr"])
        ])
        let s = index.sample(matchingDiskKey: "PN14||STO|001")
        XCTAssertEqual(s?.id, "PN14||STO|001")
        XCTAssertEqual(s?.numericDisplay["氧压"], "10 mTorr")
    }

    func testSlashInIdMatchesHyphenDiskKey() {
        let index = makeIndex(samples: [
            makeSample(id: "PN13/S487||STO|111", numeric: ["氧压": "5 mTorr", "能量": "100 mJ"])
        ])
        let s = index.sample(matchingDiskKey: "PN13-S487||STO|111")
        XCTAssertEqual(s?.id, "PN13/S487||STO|111")
        XCTAssertEqual(s?.numericDisplay["氧压"], "5 mTorr")
        XCTAssertEqual(s?.numericDisplay["能量"], "100 mJ")
    }

    func testBackslashInIdMatchesHyphenDiskKey() {
        let index = makeIndex(samples: [
            makeSample(id: #"PN9\S483||STO|111"#, numeric: ["温度": "300 K"])
        ])
        let s = index.sample(matchingDiskKey: "PN9-S483||STO|111")
        XCTAssertEqual(s?.id, #"PN9\S483||STO|111"#)
    }

    func testExactMatchPreferredOverSanitizedFallback() {
        let index = makeIndex(samples: [
            makeSample(id: "PN13/S487||STO|111", numeric: ["氧压": "slash version"]),
            makeSample(id: "PN13-S487||STO|111", numeric: ["氧压": "hyphen version"])
        ])
        let s = index.sample(matchingDiskKey: "PN13-S487||STO|111")
        XCTAssertEqual(s?.numericDisplay["氧压"], "hyphen version")
    }

    func testNoMatchReturnsNil() {
        let index = makeIndex(samples: [
            makeSample(id: "PN14||STO|001", numeric: [:])
        ])
        XCTAssertNil(index.sample(matchingDiskKey: "PN99||STO|001"))
    }

    private func makeSample(id: String, numeric: [String: String]) -> LibrarySample {
        LibrarySample(
            id: id,
            displayName: id,
            batchId: "",
            substrateRaw: "",
            substrateDisplay: "",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: numeric,
            sourceSheetName: nil,
            sourceRowNumber: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeIndex(samples: [LibrarySample]) -> LibraryIndex {
        LibraryIndex(
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            registryInternalPath: nil,
            registrySourcePath: nil,
            metadataColumnOrder: [],
            batches: [],
            samples: samples
        )
    }
}
