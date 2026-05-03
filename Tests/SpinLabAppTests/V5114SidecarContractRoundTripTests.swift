import Testing
import Foundation
@testable import SpinLabApp

// INV-6: sidecar contract 三 region round-trip JSON 不丢字段
// Full encode/decode cycle + v1→v2 migration. Fields verified by consumer region.

@Suite("V5.1.14 Sidecar Contract Round-Trip")
struct V5114SidecarContractRoundTripTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - INV-6: v2 round-trip

    @Test("INV-6: v2 sidecar round-trip preserves fields across Inbox/Library/Workbench concerns")
    func v2RoundTrip() throws {
        let original = SpinLabFileSidecar(
            workflow: "ahe",
            workflowDisplayName: "AHE",
            channels: ["CH1", "CH2"],
            sourceFilePath: "/data/sample/meas.csv",
            appliedAt: Date(timeIntervalSince1970: 1_700_000_000),
            ruleSnapshot: SidecarRuleSnapshot(
                ruleSetVersion: 3,
                ruleSetFingerprint: "abc123def456",
                appliedAt: Date(timeIntervalSince1970: 1_700_000_000),
                fields: SidecarRuleFields(
                    sampleID: SourcedValue(value: "PN001", source: "rule:sampleId.batchPrefixes#0"),
                    conditions: [
                        "temperature": SourcedValue(value: "300K", source: "rule:condition.temperature.rules#0"),
                        "current": SourcedValue(value: "10mA", source: "rule:condition.current.rules#1")
                    ],
                    substrateTags: [SourcedValue(value: "STO", source: "rule:substrate.materials#0")]
                )
            ),
            userOverrides: SidecarUserOverrides(conditions: [
                "temperature": ManualValueOverride(
                    value: "295K",
                    reason: "corrected",
                    at: Date(timeIntervalSince1970: 1_700_000_100)
                )
            ])
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SpinLabFileSidecar.self, from: data)

        // Inbox-region fields: workflow identity, channels, rule provenance
        #expect(decoded.version == 2)
        #expect(decoded.workflow == original.workflow)
        #expect(decoded.workflowDisplayName == original.workflowDisplayName)
        #expect(decoded.channels == original.channels)
        #expect(decoded.sourceFilePath == original.sourceFilePath)
        #expect(decoded.ruleSnapshot.ruleSetVersion == original.ruleSnapshot.ruleSetVersion)
        #expect(decoded.ruleSnapshot.ruleSetFingerprint == original.ruleSnapshot.ruleSetFingerprint)

        // Library-region fields: sampleID, conditions, substrateTags, userOverrides
        #expect(decoded.ruleSnapshot.fields.sampleID?.value == "PN001")
        #expect(decoded.ruleSnapshot.fields.conditions["temperature"]?.value == "300K")
        #expect(decoded.ruleSnapshot.fields.conditions["current"]?.value == "10mA")
        #expect(decoded.ruleSnapshot.fields.substrateTags.first?.value == "STO")
        #expect(decoded.userOverrides.conditions["temperature"]?.value == "295K")
        #expect(decoded.userOverrides.conditions["temperature"]?.reason == "corrected")

        // Workbench-region fields: effectiveConditions overlay (userOverride wins)
        #expect(decoded.effectiveConditions["temperature"] == "295K")
        #expect(decoded.effectiveConditions["current"] == "10mA")
        #expect(decoded.effectiveSampleID == "PN001")
        #expect(decoded.effectiveSubstrateTags == ["STO"])
    }

    // MARK: - v1 → v2 migration

    @Test("INV-6: v1 JSON migrates to v2 in-memory; condition values preserved under new schema")
    func v1MigrationPreservesConditions() throws {
        let v1Json = """
        {
            "workflow": "rt",
            "workflowDisplayName": "RT",
            "channels": ["A"],
            "sourceFilePath": "/old/meas.dat",
            "appliedAt": "2023-01-01T00:00:00Z",
            "conditions": {
                "temperature": "77K",
                "current": "5mA"
            }
        }
        """.data(using: .utf8)!

        let migrated = try decoder.decode(SpinLabFileSidecar.self, from: v1Json)

        #expect(migrated.version == 2, "v1 JSON must be upgraded to version 2 in-memory")
        #expect(migrated.workflow == "rt")
        #expect(migrated.ruleSnapshot.fields.conditions["temperature"]?.value == "77K")
        #expect(migrated.ruleSnapshot.fields.conditions["current"]?.value == "5mA")
        #expect(migrated.userOverrides == .empty)
    }

    // MARK: - v1 v1Conditions key is NOT re-emitted on encode

    @Test("INV-6: re-encoding a migrated v1 sidecar does not emit the legacy conditions key")
    func migratedV1DoesNotReemitLegacyKey() throws {
        let v1Json = """
        {
            "workflow": "3w",
            "appliedAt": "2022-06-15T12:00:00Z",
            "conditions": { "temperature": "300K" }
        }
        """.data(using: .utf8)!

        let migrated = try decoder.decode(SpinLabFileSidecar.self, from: v1Json)
        let reencoded = try encoder.encode(migrated)
        let jsonString = String(data: reencoded, encoding: .utf8) ?? ""

        // The top-level "conditions" key is a v1-only field and must not reappear
        // after migration. The field lives inside ruleSnapshot.fields.conditions now.
        let topLevel = try JSONSerialization.jsonObject(with: reencoded) as? [String: Any] ?? [:]
        #expect(topLevel["conditions"] == nil,
                "Legacy top-level 'conditions' key must not be emitted after migration; full JSON: \(jsonString)")
        #expect(topLevel["version"] as? Int == 2)
    }
}
