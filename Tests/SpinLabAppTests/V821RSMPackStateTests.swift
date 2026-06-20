import Foundation
import Testing
@testable import SpinLabApp

@Suite("RSM pack state")
struct V821RSMPackStateTests {

    @Test("RSM pack state round-trips Codable state")
    func roundTripsCodableState() throws {
        let original = RSMPackState(
            schemaVersion: 1,
            sourceFileIdentity: "/tmp/rsm-source.dat",
            detectorColumnName: "Detector",
            activeView: .kl
        )

        let decoded = try roundTrip(original)
        #expect(decoded == original)
        #expect(decoded.sourceFileIdentity == "/tmp/rsm-source.dat")
        #expect(decoded.detectorColumnName == "Detector")
        #expect(decoded.activeView == .kl)
    }

    @Test("RSM pack state defaults activeView to HL when missing")
    func missingActiveViewDefaultsToHL() throws {
        let json = """
        {
          "schemaVersion": 1,
          "sourceFileIdentity": "/tmp/rsm-source.dat",
          "detectorColumnName": "Counts"
        }
        """

        let state = try decode(json)
        #expect(state.activeView == .hl)
        #expect(state.sourceFileIdentity == "/tmp/rsm-source.dat")
        #expect(state.detectorColumnName == "Counts")
    }

    @Test("RSM pack state decodes legacy view key and falls back on unknown view")
    func legacyAndUnknownViewDecodeFallback() throws {
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "sourceFileIdentity": "/tmp/rsm-source.dat",
          "detectorColumnName": "Intensity",
          "view": "HK"
        }
        """
        let legacy = try decode(legacyJSON)
        #expect(legacy.activeView == .hk)

        let unknownJSON = """
        {
          "schemaVersion": 1,
          "sourceFileIdentity": "/tmp/rsm-source.dat",
          "detectorColumnName": "Intensity",
          "activeView": "QZ"
        }
        """
        let unknown = try decode(unknownJSON)
        #expect(unknown.activeView == .hl)
    }

    @Test("RSM pack state round-trips detector column and schema version")
    func detectorColumnAndSchemaVersionRoundTrip() throws {
        let original = RSMPackState(
            schemaVersion: 42,
            sourceFileIdentity: "import://rsm/abc123",
            detectorColumnName: "Counts",
            activeView: .hk
        )

        let decoded = try roundTrip(original)
        #expect(decoded.schemaVersion == 42)
        #expect(decoded.detectorColumnName == "Counts")
        #expect(decoded.sourceFileIdentity == "import://rsm/abc123")
        #expect(decoded.activeView == .hk)
    }

    @Test("RSM pack state defaults schemaVersion when missing")
    func missingSchemaVersionDefaultsSafely() throws {
        let json = """
        {
          "sourceFileIdentity": "/tmp/rsm-source.dat",
          "detectorColumnName": "Detector",
          "activeView": "KL"
        }
        """

        let state = try decode(json)
        #expect(state.schemaVersion == RSMPackState.currentSchemaVersion)
        #expect(state.activeView == .kl)
    }

    @Test("RSM pack state encoded JSON does not include derived render fields")
    func encodedJSONContainsOnlyRSMOwnedState() throws {
        let state = RSMPackState(
            schemaVersion: 1,
            sourceFileIdentity: "/tmp/rsm-source.dat",
            detectorColumnName: "Detector",
            activeView: .hl
        )

        let data = try JSONEncoder().encode(state)
        let json = String(decoding: data, as: UTF8.self)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("Encoded pack state should be a JSON object.")
            return
        }
        let keys = Set(object.keys)

        #expect(keys == [
            "schemaVersion",
            "sourceFileIdentity",
            "detectorColumnName",
            "activeView"
        ])

        for forbiddenToken in [
            "renderedPNG",
            "HeatmapPlotLayout",
            "HeatmapPlotPayload",
            "HeatmapRenderer",
            "HeatmapRenderPipeline",
            "HeatmapTabRenderState",
            "titleOverride",
            "xLabelOverride",
            "yLabelOverride",
            "zLabelOverride",
            "seriesOrder",
            "legendPoint",
            "hiddenPointLabelIndicesBySeries"
        ] {
            #expect(!json.contains(forbiddenToken), "Unexpected persisted field: \(forbiddenToken)")
        }
    }

    private func roundTrip(_ state: RSMPackState) throws -> RSMPackState {
        try decode(encode(state))
    }

    private func encode(_ state: RSMPackState) throws -> Data {
        try JSONEncoder().encode(state)
    }

    private func decode(_ data: Data) throws -> RSMPackState {
        try JSONDecoder().decode(RSMPackState.self, from: data)
    }

    private func decode(_ json: String) throws -> RSMPackState {
        try decode(Data(json.utf8))
    }
}
