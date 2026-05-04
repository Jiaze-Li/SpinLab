import Foundation

struct MigrationMeasuringConditionFile: Decodable {
    let version: Int
    let conditionDefinitions: [FilenameRuleSet.ConditionDefinition]
}

struct MigrationWorkflowFile: Decodable {
    let version: Int
    struct WorkflowEntry: Decodable {
        let id: String
        let displayName: String
        let matchRules: [MatchSpec]
        let conditionFieldIDs: [String]
        struct MatchSpec: Decodable {
            let type: String
            let value: String
        }
    }
    let workflows: [WorkflowEntry]
}

struct MigrationSampleIdentificationFile: Decodable {
    let version: Int
    let sampleId: FilenameRuleSet.SampleIdRules
    // Flexible substrate verify: accepts v3 (materials as objects with id/tokens)
    // and v4 (materials as SubstrateEntry with displayName/matches).
    // Only checks that the substrate section is a valid decodable JSON object.
    let substrate: SubstrateVerify

    struct SubstrateVerify: Decodable {
        init(from decoder: Decoder) throws {
            _ = try decoder.container(keyedBy: AnyKey.self)
        }
        private struct AnyKey: CodingKey {
            var stringValue: String
            var intValue: Int?
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { self.intValue = intValue; self.stringValue = "\(intValue)" }
        }
    }
}
