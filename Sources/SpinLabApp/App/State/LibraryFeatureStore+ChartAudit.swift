import Foundation

@MainActor extension LibraryFeatureStore {

    // MARK: - Run audit

    func runChartAssetAudit() {
        guard let rootPath = librarySettings.rootPath else {
            chartAuditMessage = "Library root not set."
            return
        }
        guard !isChartAuditRunning else { return }
        isChartAuditRunning = true
        chartAuditMessage = nil
        let rootURL = URL(fileURLWithPath: rootPath)
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                ChartAssetAuditService.audit(rootURL: rootURL)
            }.value
            self.chartAuditReport = report
            self.isChartAuditRunning = false
            self.chartAuditMessage = Self.chartAuditSummaryMessage(for: report)
        }
    }

    nonisolated static func chartAuditSummaryMessage(for report: ChartAssetAuditReport) -> String {
        let orphanCount = report.orphanImages.count + report.orphanManifests.count
        let missingCount = report.missingActiveImages.count + report.missingActiveManifests.count
        var parts: [String] = []
        if orphanCount == 0 && missingCount == 0 {
            parts.append("No issues found.")
        } else {
            parts.append("\(orphanCount) orphan file(s), \(missingCount) missing active file(s).")
        }
        if !report.unreadableIndexSampleKeys.isEmpty {
            parts.append("\(report.unreadableIndexSampleKeys.count) sample(s) have an unreadable index and were excluded from orphan detection — needs attention: \(report.unreadableIndexSampleKeys.joined(separator: ", ")).")
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Delete orphans

    /// Permanently deletes the given orphan relative paths from disk, then re-runs the audit.
    func deleteOrphanCharts(relativePaths: [String]) {
        guard let rootPath = librarySettings.rootPath else { return }
        guard !relativePaths.isEmpty else { return }
        let rootURL = URL(fileURLWithPath: rootPath)
        let pathsCopy = relativePaths
        isChartAuditRunning = true
        chartAuditMessage = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                ChartAssetAuditService.deleteOrphanFiles(pathsCopy, rootURL: rootURL)
            }.value
            let report = await Task.detached(priority: .userInitiated) {
                ChartAssetAuditService.audit(rootURL: rootURL)
            }.value
            self.chartAuditReport = report
            self.isChartAuditRunning = false
            var message = result.failedPaths.isEmpty
                ? "Deleted \(result.deletedCount) file(s)."
                : "Deleted \(result.deletedCount) file(s); \(result.failedPaths.count) failed."
            if !report.unreadableIndexSampleKeys.isEmpty {
                message += " \(report.unreadableIndexSampleKeys.count) sample(s) have an unreadable index and were excluded from orphan detection — needs attention."
            }
            self.chartAuditMessage = message
        }
    }

    // MARK: - Clean missing references

    /// Removes index entries whose PNG or manifest files are absent on disk, then re-runs the audit.
    func cleanMissingReferences() {
        guard let rootPath = librarySettings.rootPath else { return }
        let rootURL = URL(fileURLWithPath: rootPath)
        isChartAuditRunning = true
        chartAuditMessage = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                ChartAssetAuditService.cleanMissingReferences(rootURL: rootURL)
            }.value
            let report = await Task.detached(priority: .userInitiated) {
                ChartAssetAuditService.audit(rootURL: rootURL)
            }.value
            self.chartAuditReport = report
            self.isChartAuditRunning = false
            var message = result.failedSampleKeys.isEmpty
                ? "Cleaned \(result.cleanedRefCount) missing reference(s)."
                : "Cleaned \(result.cleanedRefCount) reference(s); \(result.failedSampleKeys.count) sample(s) failed."
            if !report.unreadableIndexSampleKeys.isEmpty {
                message += " \(report.unreadableIndexSampleKeys.count) sample(s) have an unreadable index and were excluded from orphan detection — needs attention."
            }
            self.chartAuditMessage = message
        }
    }
}
