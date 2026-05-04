import Foundation

@MainActor extension LibraryFeatureStore {

    func refreshRecomputeStaleCount() {
        guard let rootPath = librarySettings.rootPath else {
            recomputeStaleCount = 0
            return
        }
        let fingerprint = SpinLabRuleProvider.shared.loadResult().ruleSetFingerprint
        if recomputeDismissedFingerprintByRoot[rootPath] == fingerprint {
            recomputeStaleCount = 0
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        let snapshotRoot = rootPath
        let snapshotFingerprint = fingerprint
        let service = librarySidecarService
        Task {
            let count = await Task.detached(priority: .utility) {
                service.computeStaleCount(rootURL: rootURL, currentFingerprint: snapshotFingerprint)
            }.value
            guard self.librarySettings.rootPath == snapshotRoot,
                  SpinLabRuleProvider.shared.loadResult().ruleSetFingerprint == snapshotFingerprint else { return }
            self.recomputeStaleCount = count
        }
    }

    func dismissRecomputeBanner() {
        guard let rootPath = librarySettings.rootPath else { return }
        let fingerprint = SpinLabRuleProvider.shared.loadResult().ruleSetFingerprint
        recomputeDismissedFingerprintByRoot[rootPath] = fingerprint
        recomputeStaleCount = 0
    }

    func openRecomputePreview() {
        isShowingRecomputePreview = true
        isComputingRecomputePreview = true
        recomputeApplyMessage = nil
        recomputeApplyError = nil
        guard let rootPath = librarySettings.rootPath else {
            isComputingRecomputePreview = false
            recomputeDiffItems = []
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        let service = librarySidecarService
        Task {
            let items = await Task.detached(priority: .userInitiated) {
                service.computeRecomputeDiff(rootURL: rootURL)
            }.value
            self.recomputeDiffItems = items
            self.isComputingRecomputePreview = false
        }
    }

    func applyRecompute() {
        isApplyingRecompute = true
        recomputeApplyMessage = nil
        recomputeApplyError = nil
        guard let outcome = backfillSidecarsForCurrentRoot() else {
            isApplyingRecompute = false
            recomputeApplyError = "No library root selected."
            return
        }
        isApplyingRecompute = false
        let succeeded = outcome.result.updatedSidecarCount + outcome.result.createdSidecarCount
        let failed = outcome.result.failedSidecarCount
        if failed > 0 {
            recomputeApplyError = "\(succeeded) 成功 / \(failed) 失败，详情见 Logs"
        } else {
            recomputeApplyMessage = "\(succeeded) 个测量已重算"
        }
        isShowingRecomputePreview = false
        refreshRecomputeStaleCount()
    }
}
