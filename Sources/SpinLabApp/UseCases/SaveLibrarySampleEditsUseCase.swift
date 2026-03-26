import Foundation

struct SaveLibrarySampleEditsUseCase {
    enum RegistrySyncIssue {
        case sourceMissing
        case syncFailed
    }

    struct Input {
        var rootPath: String?
        var draft: LibrarySampleEditDraft?
        var baseSample: LibrarySample?
    }

    struct Output {
        var clearDraft: Bool
        var rootURLForCommit: URL?
        var syncSummary: LibraryRegistrySourceSyncResult?
        var syncIssue: RegistrySyncIssue?
        var nonFatalError: AppError?
    }

    func execute(
        input: Input,
        snapshotIndexFromFilesystem: (URL) -> LibraryIndex,
        applyDraft: (LibrarySampleEditDraft, LibrarySample) throws -> LibrarySample,
        updateSample: (LibrarySample, URL) -> Void,
        resolveRegistrySourceURL: () -> URL?,
        syncRegistrySource: (LibrarySample, LibrarySample, URL) throws -> LibraryRegistrySourceSyncResult
    ) -> Result<Output, AppError> {
        guard let rootPath = input.rootPath else {
            return .failure(.validation("Select a Library Root first."))
        }
        guard let draft = input.draft,
              let base = input.baseSample else {
            return .failure(.validation("No active edit draft."))
        }
        guard draft.sampleId == base.id else {
            return .failure(.state("Selection changed. Restart edit for the selected sample."))
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        let snapshot = snapshotIndexFromFilesystem(rootURL)
        guard let current = snapshot.samples.first(where: { $0.id == draft.sampleId }) else {
            return .failure(.notFound("Selected sample no longer exists."))
        }
        guard current.updatedAt == draft.baseUpdatedAt else {
            return .failure(.state("Sample changed on disk. Reload and edit again."))
        }

        do {
            let updated = try applyDraft(draft, current)
            updateSample(updated, rootURL)

            var syncSummary: LibraryRegistrySourceSyncResult?
            var syncIssue: RegistrySyncIssue?
            var syncError: AppError?

            if let registrySourceURL = resolveRegistrySourceURL() {
                do {
                    let syncResult = try syncRegistrySource(current, updated, registrySourceURL)
                    syncSummary = syncResult
                    if syncResult.metadataFailedCount > 0 {
                        syncError = .sync("Metadata sync partial failure: \(syncResult.metadataFailedCount) field(s) failed. Check Metadata日志.")
                    }
                } catch {
                    syncIssue = .syncFailed
                    syncError = .sync("Metadata sync failed: \(error.localizedDescription)")
                }
            } else {
                syncIssue = .sourceMissing
                syncError = .sync("Metadata sync failed: registry source not found.")
            }

            return .success(Output(
                clearDraft: true,
                rootURLForCommit: rootURL,
                syncSummary: syncSummary,
                syncIssue: syncIssue,
                nonFatalError: syncError
            ))
        } catch {
            return .failure(AppError.from(error, fallback: "Failed to save sample edits."))
        }
    }
}
