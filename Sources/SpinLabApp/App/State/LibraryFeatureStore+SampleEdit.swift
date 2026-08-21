import Foundation

extension LibraryFeatureStore {
    // MARK: - Sample Edit Operations

    func saveLibrarySampleEdits(
        useCase: SaveLibrarySampleEditsUseCase,
        resolveRegistrySourceURL: () -> URL?
    ) -> SaveLibrarySampleEditsOutcome {
        // A dirty edit session belongs to the Drawer sample that opened it,
        // not to whichever selection Detail currently displays. Browser
        // navigation must never block (or silently drop) a Drawer save, so
        // this gate checks edit-session ownership (draft + base sample)
        // instead of `canMutateLibraryDetailSelection` (Detail focus).
        guard librarySampleEditDraft != nil, libraryState.sampleEditBaseSample != nil else {
            let error = AppError.state("Cannot save: no active sample edit session.")
            librarySampleEditError = error.localizedDescription
            return .failure(error)
        }
        librarySampleEditError = nil
        librarySampleEditMessage = nil
        librarySampleEditIsSaving = true
        defer { librarySampleEditIsSaving = false }

        let result = useCase.execute(
            input: SaveLibrarySampleEditsUseCase.Input(
                rootPath: librarySettings.rootPath,
                draft: librarySampleEditDraft,
                baseSample: libraryState.sampleEditBaseSample
            ),
            snapshotIndexFromFilesystem: { [libraryStore] rootURL in
                libraryStore.snapshotIndexFromFilesystem(rootURL: rootURL)
            },
            applyDraft: { [librarySampleEditService] draft, current in
                try librarySampleEditService.apply(draft: draft, to: current)
            },
            updateSample: { [libraryStore] updated, rootURL in
                try libraryStore.updateSample(updated, rootURL: rootURL, changeSource: "manual_edit")
            },
            resolveRegistrySourceURL: resolveRegistrySourceURL,
            syncRegistrySource: { [libraryRegistrySyncService] current, updated, registrySourceURL in
                try libraryRegistrySyncService.syncEditedSample(
                    oldSample: current,
                    updatedSample: updated,
                    registrySourceURL: registrySourceURL
                )
            }
        )

        switch result {
        case let .success(output):
            if output.clearDraft {
                librarySampleEditDraft = nil
                libraryState.sampleEditBaseSample = nil
                libraryState.sampleEditOriginalDraft = nil
            }
            if let nonFatalError = output.nonFatalError {
                librarySampleEditError = nonFatalError.localizedDescription
            }

            let message = makeLibrarySampleEditMessage(
                syncSummary: output.syncSummary,
                syncIssue: output.syncIssue,
                nonFatalError: output.nonFatalError
            )
            librarySampleEditMessage = message
            return .success(
                rootURLForCommit: output.rootURLForCommit,
                nonFatalError: output.nonFatalError,
                message: message
            )
        case let .failure(error):
            librarySampleEditError = error.localizedDescription
            return .failure(error)
        }
    }

    func makeLibrarySampleEditMessage(
        syncSummary: LibraryRegistrySourceSyncResult?,
        syncIssue: SaveLibrarySampleEditsUseCase.RegistrySyncIssue?,
        nonFatalError: AppError?
    ) -> String {
        if let syncSummary {
            return """
            已保存样品编辑。
            Metadata 写回 XLSX：成功 \(syncSummary.metadataWrittenCount) 项，失败 \(syncSummary.metadataFailedCount) 项。
            Numeric 日志新增：\(syncSummary.manualLoggedCount) 项（\(syncSummary.manualLogSheetName)）。
            Metadata 日志表：\(syncSummary.metadataLogSheetName)。
            """
        }

        switch syncIssue {
        case .sourceMissing:
            return """
            已保存样品编辑。
            XLSX 同步警告：未找到 registry source。
            """
        case .syncFailed:
            return """
            已保存样品编辑。
            XLSX 同步警告：\(nonFatalError?.localizedDescription ?? "未知错误")
            """
        case .none:
            return "已保存样品编辑。"
        }
    }

    func beginEditingSelectedLibrarySample(selectedSample: LibrarySample?) {
        librarySampleEditError = nil
        librarySampleEditMessage = nil

        guard let selectedSample else {
            librarySampleEditError = "Select an existing drawer sample to edit."
            return
        }

        libraryState.sampleEditBaseSample = selectedSample
        let draft = librarySampleEditService.makeDraft(from: selectedSample)
        librarySampleEditDraft = draft
        libraryState.sampleEditOriginalDraft = draft
    }

    func beginEditingSelectedDrawerSampleIfNeeded() {
        let selectedSample = libraryActiveSelectionSource == .drawer ? selectedExistingDrawerSample() : nil
        beginEditingSelectedLibrarySample(selectedSample: selectedSample)
    }

    func cancelEditingSelectedLibrarySample(message: String = "Edit canceled.") {
        librarySampleEditDraft = nil
        libraryState.sampleEditBaseSample = nil
        libraryState.sampleEditOriginalDraft = nil
        librarySampleEditError = nil
        librarySampleEditMessage = message
    }

    func discardEditingSelectedLibrarySample() {
        librarySampleEditDraft = nil
        libraryState.sampleEditBaseSample = nil
        libraryState.sampleEditOriginalDraft = nil
        librarySampleEditError = nil
        librarySampleEditMessage = "Edit discarded."
    }

    func updateLibrarySampleEditSubstrateTags(_ value: String) {
        guard var draft = librarySampleEditDraft else {
            return
        }
        draft.substrateTagsText = value
        librarySampleEditDraft = draft
    }

    func updateLibrarySampleEditNumericValue(key: String, value: String) {
        guard var draft = librarySampleEditDraft,
              let index = draft.numericValues.firstIndex(where: { $0.key == key }) else {
            return
        }
        draft.numericValues[index].value = value
        librarySampleEditDraft = draft
    }

    func updateLibrarySampleEditMetadataValue(key: String, value: String) {
        guard var draft = librarySampleEditDraft,
              let index = draft.metadataValues.firstIndex(where: { $0.key == key }) else {
            return
        }
        draft.metadataValues[index].value = value
        librarySampleEditDraft = draft
    }

    func reconcileLibrarySampleEditingSelection() {
        guard let draft = librarySampleEditDraft else {
            return
        }

        // Keyed on Drawer selection identity only — a dirty edit session
        // must survive Browser-pane mutations (Apply Selected, Refresh
        // Incremental, etc.) that reach this via `applyExistingIndex` while
        // Detail focus happens to be `.browser`. Detail focus is irrelevant
        // here; only the Drawer sample actually disappearing or changing
        // identity should cancel the draft.
        guard let selectedSample = selectedExistingDrawerSample() else {
            librarySampleEditDraft = nil
            libraryState.sampleEditBaseSample = nil
            libraryState.sampleEditOriginalDraft = nil
            librarySampleEditError = nil
            librarySampleEditMessage = "Edit canceled after leaving existing drawer selection."
            return
        }

        guard selectedSample.id == draft.sampleId else {
            librarySampleEditDraft = nil
            libraryState.sampleEditBaseSample = nil
            libraryState.sampleEditOriginalDraft = nil
            librarySampleEditError = nil
            librarySampleEditMessage = "Edit canceled after sample selection changed."
            return
        }
    }
}
