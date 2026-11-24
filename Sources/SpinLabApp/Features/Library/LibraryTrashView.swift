import SwiftUI

struct LibraryTrashPrimaryView: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var pendingPermanentDeleteSample: LibrarySample?
    @State private var pendingV2DeletionPlan: PermanentDeletionPlan?
    @State private var isShowingEmptyTrashConfirm = false
    @State private var pendingV2EmptyTrashPlans: [(sample: LibrarySample, plan: PermanentDeletionPlan)] = []

    private var trashedSamples: [LibrarySample] {
        appState.library.libraryTrashedSamples
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack(alignment: .center, spacing: AppSpacing.md) {
                Text("Trash")
                    .font(AppFontScale.sectionTitle)
                Spacer()
                if !trashedSamples.isEmpty {
                    Button("Empty Trash") {
                        beginEmptyTrash()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
            }

            if let error = appState.library.libraryDrawerError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if let message = appState.library.libraryDrawerMessage {
                Text(message)
                    .font(.callout)
            }

            if trashedSamples.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Trash is empty.")
                        .font(.body)
                    Text("Deleted samples stay here until you restore them or delete them permanently.")
                        .font(.callout)
                }
                .padding(.top, AppSpacing.sm)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.md) {
                        ForEach(trashedSamples) { sample in
                            trashedSampleRow(sample)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.bottom, AppSpacing.xl)
        .alert(
            "Delete Sample Permanently?",
            isPresented: Binding(
                get: { pendingPermanentDeleteSample != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingPermanentDeleteSample = nil
                        pendingV2DeletionPlan = nil
                    }
                }
            ),
            presenting: pendingPermanentDeleteSample
        ) { sample in
            Button("Cancel", role: .cancel) {
                pendingPermanentDeleteSample = nil
                pendingV2DeletionPlan = nil
            }
            Button("Delete Permanently", role: .destructive) {
                if let plan = pendingV2DeletionPlan {
                    appState.commitV2PermanentSampleDeletion(sample: sample, plan: plan)
                } else {
                    appState.permanentlyDeleteTrashedSample(sample)
                }
                pendingPermanentDeleteSample = nil
                pendingV2DeletionPlan = nil
            }
        } message: { sample in
            if let plan = pendingV2DeletionPlan {
                let staleSuffix = plan.staleLiveAssetIDs.isEmpty
                    ? ""
                    : " \(plan.staleLiveAssetIDs.count) retained live output(s) will be marked stale."
                Text("This will permanently remove '\(sample.displayName)' (Batch \(sample.batchId)). It will delete \(plan.deleteFileCount) file(s) (\(plan.assetsToDelete.count) asset(s)), and retain \(plan.retainedFileCount) file(s) (\(plan.retainedAssets.count) shared/referenced asset(s)).\(staleSuffix) This action cannot be undone.")
            } else {
                Text("This will permanently remove '\(sample.displayName)' (Batch \(sample.batchId)) and its sample files from disk. This action cannot be undone.")
            }
        }
        .alert("Empty Trash?", isPresented: $isShowingEmptyTrashConfirm) {
            Button("Cancel", role: .cancel) {
                pendingV2EmptyTrashPlans = []
            }
            Button("Empty Trash", role: .destructive) {
                if appState.isV2LibraryLayout {
                    commitReviewedEmptyTrash()
                } else {
                    appState.emptyTrash()
                }
            }
        } message: {
            if appState.isV2LibraryLayout, !pendingV2EmptyTrashPlans.isEmpty {
                let plans = pendingV2EmptyTrashPlans.map(\.plan)
                let deleteFiles = plans.reduce(0) { $0 + $1.deleteFileCount }
                let deleteAssets = plans.reduce(0) { $0 + $1.assetsToDelete.count }
                let retainFiles = plans.reduce(0) { $0 + $1.retainedFileCount }
                let retainAssets = plans.reduce(0) { $0 + $1.retainedAssets.count }
                let staleCount = Set(plans.flatMap(\.staleLiveAssetIDs)).count
                let staleSuffix = staleCount == 0 ? "" : " \(staleCount) retained live output(s) will be marked stale."
                Text("This will permanently remove all \(plans.count) sample(s) in Trash. It will delete \(deleteFiles) file(s) (\(deleteAssets) asset(s)), and retain \(retainFiles) file(s) (\(retainAssets) shared/referenced asset(s)).\(staleSuffix) This action cannot be undone.")
            } else {
                Text("This will permanently remove all \(trashedSamples.count) sample(s) in Trash and their sample files from disk. This action cannot be undone.")
            }
        }
    }

    /// V2 computes every deletion plan before confirmation; V1 keeps its original flow.
    private func beginEmptyTrash() {
        guard appState.isV2LibraryLayout else {
            pendingV2EmptyTrashPlans = []
            isShowingEmptyTrashConfirm = true
            return
        }
        var reviewed: [(sample: LibrarySample, plan: PermanentDeletionPlan)] = []
        for sample in trashedSamples {
            switch appState.planV2PermanentSampleDeletion(sample: sample) {
            case let .success(plan):
                reviewed.append((sample, plan))
            case let .failure(error):
                appState.library.libraryDrawerError = error.localizedDescription
                return
            }
        }
        pendingV2EmptyTrashPlans = reviewed
        isShowingEmptyTrashConfirm = true
    }

    /// Re-plans every sample and aborts before any deletion if the reviewed plans changed.
    private func commitReviewedEmptyTrash() {
        let reviewed = pendingV2EmptyTrashPlans
        pendingV2EmptyTrashPlans = []
        for item in reviewed {
            switch appState.planV2PermanentSampleDeletion(sample: item.sample) {
            case let .success(fresh):
                guard fresh == item.plan else {
                    appState.library.libraryDrawerError =
                        "Trash contents changed since review. Nothing was deleted; please review Empty Trash again."
                    return
                }
            case let .failure(error):
                appState.library.libraryDrawerError = error.localizedDescription
                return
            }
        }
        for item in reviewed {
            guard appState.commitV2PermanentSampleDeletion(sample: item.sample, plan: item.plan) else { return }
        }
    }

    @ViewBuilder
    private func trashedSampleRow(_ sample: LibrarySample) -> some View {
        GroupBox {
            HStack(alignment: .center, spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(sample.displayName)
                        .font(AppFontScale.groupHeader)
                    HStack(spacing: AppSpacing.md) {
                        Text("Batch: \(sample.batchId)")
                            .font(.callout)
                        if !sample.substrateDisplay.isEmpty {
                            Text("Substrate: \(sample.substrateDisplay)")
                                .font(.callout)
                        }
                        if let deletedAt = sample.deletedAt {
                            Text("Deleted: \(formattedTrashDate(deletedAt))")
                                .font(.callout)
                        }
                    }
                }
                Spacer()
                HStack(spacing: AppSpacing.sm) {
                    Button("Restore") {
                        appState.restoreSampleFromTrash(sample)
                    }
                    .buttonStyle(.bordered)

                    Button("Delete Permanently") {
                        if appState.isV2LibraryLayout {
                            switch appState.planV2PermanentSampleDeletion(sample: sample) {
                            case let .success(plan):
                                pendingV2DeletionPlan = plan
                                pendingPermanentDeleteSample = sample
                            case let .failure(error):
                                appState.library.libraryDrawerError = error.localizedDescription
                            }
                        } else {
                            pendingV2DeletionPlan = nil
                            pendingPermanentDeleteSample = sample
                        }
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
            }
            .padding(AppSpacing.xs)
        }
    }

    private func formattedTrashDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let dateYear = calendar.component(.year, from: date)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = (dateYear == currentYear) ? "MM-dd HH:mm" : "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

struct LibraryTrashDetailView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text("Trash Policy")
                .font(AppFontScale.sectionTitle)

            GroupBox {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Samples in Trash: \(appState.library.libraryTrashedSamples.count)")
                        .font(AppFontScale.groupHeader)
                    Text("• Samples in Trash are hidden from Library lists, Library search, Inbox matching, and Workbench search.")
                        .font(.callout)
                    Text("• Original files remain in place on disk until you choose Delete Permanently or Empty Trash.")
                        .font(.callout)
                    Text("• Samples in Trash are kept indefinitely and never removed automatically.")
                        .font(.callout)
                    Text("• Restore returns a sample to its original batch with all measurements and charts intact.")
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.xs)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.bottom, AppSpacing.xl)
    }
}
