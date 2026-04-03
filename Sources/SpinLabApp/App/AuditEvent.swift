import Foundation

struct AuditEvent: Codable, Equatable {
    var eventID: String
    var timestamp: String
    var action: String
    var sourceFileName: String
    var sourceFilePath: String
    var targetDrawers: [String]
    var result: String
    var metadata: [String: String]
}
