import Foundation

enum AngularFitDiagnosticSeverity: String, Codable, Hashable, Sendable {
    case info
    case warning
    case error
}

struct AngularFitDiagnostic: Codable, Hashable, Sendable {
    var code: String
    var message: String
    var severity: AngularFitDiagnosticSeverity
}
