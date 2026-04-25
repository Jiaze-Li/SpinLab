import Foundation

enum RulesPanelSection: String, CaseIterable, Identifiable {
    case filenameParse
    case sampleID
    case workflowMatch
    case substrate
    case measurementTag
    case workflowIDPolicy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .filenameParse:    return "Filename Parse"
        case .sampleID:         return "Sample ID"
        case .workflowMatch:    return "Workflow Match"
        case .substrate:        return "Substrate"
        case .measurementTag:   return "Measurement Tags"
        case .workflowIDPolicy: return "Workflow ID Policy"
        }
    }

    var isEditable: Bool {
        switch self {
        case .filenameParse, .sampleID, .workflowMatch, .substrate: return true
        case .measurementTag, .workflowIDPolicy:                     return false
        }
    }

    var sessionNote: String? {
        isEditable ? nil : "Editing will be available in Session 3"
    }
}
