import Foundation

@MainActor extension LibraryFeatureStore {
    /// Step 1 of the one-time permanent-ID issue for existing samples: reports how many samples would get one.
    /// Writes nothing.
    func previewSampleUIDBackfill() -> Int? {
        guard let rootPath = librarySettings.rootPath else {
            libraryRootVerificationMessage = "No Library Root selected."
            return nil
        }
        do {
            let report = try LegacySampleBackfillService().run(
                libraryStore: libraryStore, rootURL: URL(fileURLWithPath: rootPath), dryRun: true)
            libraryRootVerificationMessage = report.pending.isEmpty
                ? "Every sample already has a permanent ID."
                : "\(report.pending.count) existing samples need a permanent ID. Nothing has been changed yet."
            libraryRootVerificationPath = rootPath
            return report.pending.count
        } catch {
            libraryRootVerificationMessage = error.localizedDescription
            libraryRootVerificationPath = rootPath
            return nil
        }
    }

    /// Step 2 (after the user confirmed the preview): backs up, issues the IDs, rebuilds the index once.
    func runSampleUIDBackfill() {
        guard let rootPath = librarySettings.rootPath else { return }
        do {
            let report = try LegacySampleBackfillService().run(
                libraryStore: libraryStore, rootURL: URL(fileURLWithPath: rootPath), dryRun: false)
            libraryRootVerificationMessage = report.succeeded
                ? "Issued permanent IDs to \(report.issued) existing samples. A backup was saved first."
                : "Permanent IDs were issued to \(report.issued) samples, but some failed: \((report.failures + report.missingAfterwards).joined(separator: "; "))"
            libraryRootVerificationPath = rootPath
            syncLibraryFromFiles()
        } catch {
            libraryRootVerificationMessage = error.localizedDescription
            libraryRootVerificationPath = rootPath
        }
    }
}
