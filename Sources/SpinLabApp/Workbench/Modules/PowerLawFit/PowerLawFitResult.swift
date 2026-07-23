import Foundation

enum PowerLawFitStatus: String, Codable, Hashable, Sendable {
    case disabled
    case insufficientData
    case invalidInput
    case fitted
}

struct PowerLawFitResult: Codable, Hashable, Sendable {
    var status: PowerLawFitStatus
    var mode: PowerLawFitMode
    var subtractIntercept: Bool
    var sampleCount: Int
    var slope: Double?
    var intercept: Double?
    var rSquared: Double?
    var fitLine: PowerLawFitLineGeometry?
    var diagnostics: [PowerLawFitDiagnostic]

    var isSuccessful: Bool { status == .fitted && slope != nil && intercept != nil && fitLine != nil }
}

