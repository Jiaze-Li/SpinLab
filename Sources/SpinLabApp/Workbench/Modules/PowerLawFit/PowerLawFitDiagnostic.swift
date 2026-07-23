import Foundation

enum PowerLawFitDiagnosticSeverity: String, Codable, Hashable, Sendable {
    case info
    case warning
    case error
}

struct PowerLawFitDiagnostic: Codable, Hashable, Sendable {
    var code: String
    var message: String
    var severity: PowerLawFitDiagnosticSeverity
}

