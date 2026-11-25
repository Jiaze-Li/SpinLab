import SwiftUI

struct DeletionConfirmationContext: Identifiable {
    enum Kind {
        case singleSample(displayName: String, batchID: String, plan: PermanentDeletionPlan?)
        case emptyTrash(sampleCount: Int, plan: PermanentDeletionPlan?)
        case measurement(title: String, datasetCount: Int, isSingleDataset: Bool, plan: PermanentDeletionPlan)
    }

    let id = UUID()
    let kind: Kind
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var title: String {
        switch kind {
        case .singleSample:
            return "Delete Sample Permanently?"
        case .emptyTrash:
            return "Empty Trash?"
        case let .measurement(_, _, isSingleDataset, _):
            return isSingleDataset ? "Delete Dataset?" : "Delete Measurement?"
        }
    }

    var confirmButtonTitle: String {
        switch kind {
        case .singleSample:
            return "Delete Permanently"
        case .emptyTrash:
            return "Empty Trash"
        case let .measurement(_, _, isSingleDataset, _):
            return isSingleDataset ? "Delete Dataset" : "Delete Measurement"
        }
    }

    var summaryLine: String {
        switch kind {
        case let .singleSample(displayName, batchID, _):
            return "This will permanently remove sample '\(displayName)' (Batch \(batchID))."
        case let .emptyTrash(sampleCount, plan):
            let count = plan?.sampleUIDs.count ?? sampleCount
            return "This will permanently remove all \(count) sample(s) in Trash."
        case let .measurement(title, datasetCount, isSingleDataset, _):
            if isSingleDataset {
                return "This will permanently remove 1 standardized dataset from '\(title)'. The raw source file and other datasets will be kept."
            }
            return "This will permanently remove measurement '\(title)' (\(datasetCount) standardized dataset(s))."
        }
    }

    var plan: PermanentDeletionPlan? {
        switch kind {
        case let .singleSample(_, _, plan), let .emptyTrash(_, plan):
            return plan
        case let .measurement(_, _, _, plan):
            return plan
        }
    }

    var retentionNotice: String? {
        guard let plan else { return nil }
        var parts: [String] = []
        if !plan.retainedAssets.isEmpty {
            parts.append("\(plan.retainedAssets.count) referenced item(s) will be retained")
        }
        if !plan.staleLiveAssetIDs.isEmpty {
            parts.append("\(plan.staleLiveAssetIDs.count) live output(s) will be marked stale")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ") + "."
    }
}

struct LibraryDeletionConfirmationSheet: View {
    let context: DeletionConfirmationContext
    @Environment(\.dismiss) private var dismiss
    @State private var isDetailsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text(context.title)
                .font(AppFontScale.sectionHeader)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(context.summaryLine)
                    .font(.body)

                if let retentionNotice = context.retentionNotice {
                    Text(retentionNotice)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text("This action cannot be undone.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let plan = context.plan {
                DisclosureGroup("Deletion Details", isExpanded: $isDetailsExpanded) {
                    Grid(alignment: .leading, horizontalSpacing: AppSpacing.lg, verticalSpacing: AppSpacing.xs) {
                        detailRow("Assets to delete", "\(plan.assetsToDelete.count)")
                        detailRow("Files to delete", "\(plan.deleteFileCount)")
                        detailRow("Retained assets", "\(plan.retainedAssets.count)")
                        detailRow("Retained files", "\(plan.retainedFileCount)")
                        if !plan.staleLiveAssetIDs.isEmpty {
                            detailRow("Stale live outputs", "\(plan.staleLiveAssetIDs.count)")
                        }
                    }
                    .padding(.top, AppSpacing.xs)
                }
                .font(.callout)
            }

            HStack(spacing: AppSpacing.md) {
                Spacer()
                Button("Cancel") {
                    context.onCancel()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button(context.confirmButtonTitle) {
                    context.onConfirm()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
            }
        }
        .padding(AppSpacing.xxl)
        .frame(minWidth: 420)
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
        }
    }
}
