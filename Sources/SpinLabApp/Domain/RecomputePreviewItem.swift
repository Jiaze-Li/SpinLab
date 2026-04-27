import Foundation

enum RecomputeDiffStatus: Sendable {
    case willUpdate
    case migration
    case added
    case ruleRemoved
    case manualOverride
    case noChange

    var label: String {
        switch self {
        case .willUpdate:     return "将更新"
        case .migration:      return "迁移"
        case .added:          return "新增"
        case .ruleRemoved:    return "规则未命中"
        case .manualOverride: return "手动覆盖保留"
        case .noChange:       return "无变化"
        }
    }

    var groupIndex: Int {
        switch self {
        case .willUpdate, .migration, .added, .ruleRemoved: return 0
        case .manualOverride: return 1
        case .noChange:       return 2
        }
    }
}

struct RecomputeDiffItem: Identifiable, Sendable {
    var id: String          // "\(sidecarPath)|\(fieldKey)"
    var sidecarPath: String
    var sampleID: String
    var workflow: String
    var sourceFileName: String
    var fieldKey: String
    var oldValue: String?
    var newValue: String?
    var oldSource: String?
    var newSource: String?
    var status: RecomputeDiffStatus
}
