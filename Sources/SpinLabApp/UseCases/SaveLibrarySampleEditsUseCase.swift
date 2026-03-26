import Foundation

struct SaveLibrarySampleEditsUseCase {
    struct Input {
        var rootPath: String?
        var draft: LibrarySampleEditDraft?
        var baseSample: LibrarySample?
    }

    struct Output {
        var error: String?
        var message: String?
        var clearDraft: Bool
        var rootURLForCommit: URL?
    }

    func execute(
        input: Input,
        snapshotIndexFromFilesystem: (URL) -> LibraryIndex,
        applyDraft: (LibrarySampleEditDraft, LibrarySample) throws -> LibrarySample,
        updateSample: (LibrarySample, URL) -> Void,
        resolveRegistrySourceURL: () -> URL?,
        syncRegistrySource: (LibrarySample, LibrarySample, URL) throws -> LibraryRegistrySourceSyncResult
    ) -> Output {
        guard let rootPath = input.rootPath else {
            return Output(
                error: "Select a Library Root first.",
                message: nil,
                clearDraft: false,
                rootURLForCommit: nil
            )
        }
        guard let draft = input.draft,
              let base = input.baseSample else {
            return Output(
                error: "No active edit draft.",
                message: nil,
                clearDraft: false,
                rootURLForCommit: nil
            )
        }
        guard draft.sampleId == base.id else {
            return Output(
                error: "Selection changed. Restart edit for the selected sample.",
                message: nil,
                clearDraft: false,
                rootURLForCommit: nil
            )
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        let snapshot = snapshotIndexFromFilesystem(rootURL)
        guard let current = snapshot.samples.first(where: { $0.id == draft.sampleId }) else {
            return Output(
                error: "Selected sample no longer exists.",
                message: nil,
                clearDraft: true,
                rootURLForCommit: nil
            )
        }
        guard current.updatedAt == draft.baseUpdatedAt else {
            return Output(
                error: "Sample changed on disk. Reload and edit again.",
                message: nil,
                clearDraft: false,
                rootURLForCommit: nil
            )
        }

        do {
            let updated = try applyDraft(draft, current)
            updateSample(updated, rootURL)

            var syncSummary: String?
            var syncError: String?

            if let registrySourceURL = resolveRegistrySourceURL() {
                do {
                    let syncResult = try syncRegistrySource(current, updated, registrySourceURL)
                    syncSummary = """
                    已保存样品编辑。
                    Metadata 写回 XLSX：成功 \(syncResult.metadataWrittenCount) 项，失败 \(syncResult.metadataFailedCount) 项。
                    Numeric 日志新增：\(syncResult.manualLoggedCount) 项（\(syncResult.manualLogSheetName)）。
                    Metadata 日志表：\(syncResult.metadataLogSheetName)。
                    """
                    if syncResult.metadataFailedCount > 0 {
                        syncError = "Metadata sync partial failure: \(syncResult.metadataFailedCount) field(s) failed. Check Metadata日志."
                    }
                } catch {
                    syncSummary = """
                    已保存样品编辑。
                    XLSX 同步警告：\(error.localizedDescription)
                    """
                    syncError = "Metadata sync failed: \(error.localizedDescription)"
                }
            } else {
                syncSummary = """
                已保存样品编辑。
                XLSX 同步警告：未找到 registry source。
                """
                syncError = "Metadata sync failed: registry source not found."
            }

            return Output(
                error: syncError,
                message: syncSummary ?? "已保存样品编辑。",
                clearDraft: true,
                rootURLForCommit: rootURL
            )
        } catch {
            return Output(
                error: error.localizedDescription,
                message: nil,
                clearDraft: false,
                rootURLForCommit: nil
            )
        }
    }
}
