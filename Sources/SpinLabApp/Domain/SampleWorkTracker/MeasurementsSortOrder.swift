import Foundation

enum MeasurementsSortOrder: String, CaseIterable, Sendable {
    case latestActivity
    case sampleName

    var label: String {
        switch self {
        case .latestActivity: return "Latest activity"
        case .sampleName: return "Sample name"
        }
    }

    func sort(_ summaries: [SampleWorkSummary]) -> [SampleWorkSummary] {
        switch self {
        case .sampleName:
            return summaries
        case .latestActivity:
            return summaries.sorted { lhs, rhs in
                let lhsUnknown = lhs.sampleKey.isEmpty
                let rhsUnknown = rhs.sampleKey.isEmpty
                if lhsUnknown != rhsUnknown { return rhsUnknown }
                switch (lhs.lastActivityAt, rhs.lastActivityAt) {
                case let (l?, r?):
                    if l != r { return l > r }
                    return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil):
                    return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
                }
            }
        }
    }
}
