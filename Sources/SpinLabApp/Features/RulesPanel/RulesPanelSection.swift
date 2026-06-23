import Foundation

enum RulesPanelSection: String, CaseIterable, Identifiable {
    case importFilters
    case filenameTokenization
    case sampleIdentification
    case workflow
    case measuringCondition
    case libraryRegistry

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .importFilters:        return "Import Filters"
        case .filenameTokenization: return "Filename Tokenization"
        case .sampleIdentification: return "Sample"
        case .workflow:             return "Workflow"
        case .measuringCondition:   return "Condition"
        case .libraryRegistry:      return "Registry Import"
        }
    }
}
