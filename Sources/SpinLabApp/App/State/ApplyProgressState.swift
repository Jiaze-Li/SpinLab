import Foundation

struct ApplyProgressState {
    var isRunning: Bool = false
    var totalCount: Int = 0
    var processedCount: Int = 0
    var appliedCount: Int = 0
    var skippedCount: Int = 0
    var failedCount: Int = 0
    var currentFileName: String = ""
}
