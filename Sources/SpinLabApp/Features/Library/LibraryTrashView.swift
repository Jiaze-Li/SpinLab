import SwiftUI

struct LibraryTrashPrimaryView: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var pendingPermanentDeleteSample: LibrarySample?
    @State private var isShowingEmptyTrashConfirm = false

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
                        isShowingEmptyTrashConfirm = true
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
                    }
                }
            ),
            presenting: pendingPermanentDeleteSample
        ) { sample in
            Button("Cancel", role: .cancel) {
                pendingPermanentDeleteSample = nil
            }
            Button("Delete Permanently", role: .destructive) {
                appState.permanentlyDeleteTrashedSample(sample)
                pendingPermanentDeleteSample = nil
            }
        } message: { sample in
            Text("This will permanently remove '\(sample.displayName)' (Batch \(sample.batchId)) and its sample files from disk. This action cannot be undone.")
        }
        .alert("Empty Trash?", isPresented: $isShowingEmptyTrashConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Empty Trash", role: .destructive) {
                appState.emptyTrash()
            }
        } message: {
            Text("This will permanently remove all \(trashedSamples.count) sample(s) in Trash and their sample files from disk. This action cannot be undone.")
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
                        pendingPermanentDeleteSample = sample
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
