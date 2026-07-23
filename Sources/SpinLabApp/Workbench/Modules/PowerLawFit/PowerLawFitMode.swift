import Foundation

/// Exponent selection for the generic power-law fit module.
///
/// `none` disables fitting. `one`/`two`/`three` transform the x-axis as x^1/x^2/x^3
/// before running the linear regression.
enum PowerLawFitMode: Int, Codable, Hashable, Sendable, CaseIterable {
    case none = 0
    case one = 1
    case two = 2
    case three = 3

    var exponent: Double? {
        switch self {
        case .none: return nil
        case .one: return 1
        case .two: return 2
        case .three: return 3
        }
    }
}

