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
            let orphanCount = report.orphanImages.count + report.orphanManifests.count
            let missingCount = report.missingActiveImages.count + report.missingActiveManifests.count
            if orphanCount == 0 && missingCount == 0 {
                self.chartAuditMessage = "No issues found."
            } else {
                self.chartAuditMessage = "\(orphanCount) orphan file(s), \(missingCount) missing active file(s)."
            }
        }
    }

    // MARK: - Archive orphans

    /// Archives the given orphan relative paths, then re-runs the audit to refresh state.
    func archiveOrphanCharts(relativePaths: [String]) {
        guard let rootPath = librarySettings.rootPath else { return }
        guard !relativePaths.isEmpty else { return }
        let rootURL = URL(fileURLWithPath: rootPath)
        let pathsCopy = relativePaths
        isChartAuditRunning = true
        chartAuditMessage = nil
        Task {
            let archived = await Task.detached(priority: .userInitiated) {
                ChartAssetAuditService.archiveOrphanFiles(pathsCopy, rootURL: rootURL)
            }.value
            let report = await Task.detached(priority: .userInitiated) {
                ChartAssetAuditService.audit(rootURL: rootURL)
            }.value
            self.chartAuditReport = report
            self.isChartAuditRunning = false
            self.chartAuditMessage = "Archived \(archived) file(s)."
        }
    }
}
