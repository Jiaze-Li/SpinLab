import Foundation

struct RulesMigrationState: Codable {
    var rules_schema_version: Int
    var migratedAt: String
    var sourceFileSHA256: [String: String]
}
