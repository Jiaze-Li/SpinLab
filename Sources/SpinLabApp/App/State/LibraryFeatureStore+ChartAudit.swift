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
            if result.failedPaths.isEmpty {
                self.chartAuditMessage = "Deleted \(result.deletedCount) file(s)."
            } else {
                self.chartAuditMessage = "Deleted \(result.deletedCount) file(s); \(result.failedPaths.count) failed."
            }
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
            if result.failedSampleKeys.isEmpty {
                self.chartAuditMessage = "Cleaned \(result.cleanedRefCount) missing reference(s)."
            } else {
                self.chartAuditMessage = "Cleaned \(result.cleanedRefCount) reference(s); \(result.failedSampleKeys.count) sample(s) failed."
            }
        }
    }
}
