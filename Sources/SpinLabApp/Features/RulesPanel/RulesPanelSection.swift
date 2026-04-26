import Foundation

enum RulesPanelSection: String, CaseIterable, Identifiable {
    case filenameParse
    case sampleID
    case workflowMatch
    case substrate
    case measurementTag

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .filenameParse:  return "Filename Parse"
        case .sampleID:       return "Sample ID"
        case .workflowMatch:  return "Workflow Match"
        case .substrate:      return "Substrate"
        case .measurementTag: return "Measurement Tags"
        }
    }

    var isEditable: Bool {
        switch self {
        case .filenameParse, .sampleID, .workflowMatch, .substrate: return true
        case .measurementTag: return false
        }
    }

    var sessionNote: String? {
        isEditable ? nil : "Editing will be available in Session 3"
    }
}
