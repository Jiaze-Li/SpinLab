import Foundation

enum RTWorkbenchTab: String, CaseIterable, Identifiable {
    case rtCurve = "R(T)"

    var id: String { rawValue }

    var stableKey: String { "rtCurve" }

    var displayName: String { rawValue }

    static let stableKeyRank: [String: Int] = Dictionary(
        uniqueKeysWithValues: allCases.enumerated().map { ($1.stableKey, $0) }
    )
}
