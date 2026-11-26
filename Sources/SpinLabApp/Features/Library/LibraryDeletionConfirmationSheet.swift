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

    var leadPrompt: String {
        switch kind {
        case .singleSample:
            return "Permanently remove this sample from disk?"
        case .emptyTrash:
            return "Permanently remove all trashed samples from disk?"
        case let .measurement(_, _, isSingleDataset, _):
            return isSingleDataset
                ? "Permanently remove this standardized dataset? The raw source file and other datasets will be kept."
                : "Permanently remove this measurement and its standardized data?"
        }
    }

    var targetTitle: String {
        switch kind {
        case let .singleSample(displayName, _, _):
            return displayName
        case let .emptyTrash(sampleCount, plan):
            let count = plan?.sampleUIDs.count ?? sampleCount
            return "\(count) sample(s) in Trash"
        case let .measurement(title, _, _, _):
            return title
        }
    }

    var targetSubtitle: String? {
        switch kind {
        case let .singleSample(_, batchID, plan):
            if let plan {
                return "Batch \(batchID) · \(plan.deleteMeasurementCount) measurement(s)"
            }
            return "Batch \(batchID)"
        case let .emptyTrash(_, plan):
            if let plan {
                return "\(plan.deleteMeasurementCount) measurement(s)"
            }
            return nil
        case let .measurement(_, datasetCount, isSingleDataset, _):
            return isSingleDataset ? "1 standardized dataset" : "\(datasetCount) standardized dataset(s)"
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
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .vertical) {
                contentBody
                ScrollView(.vertical) {
                    contentBody
                }
                .scrollIndicators(.automatic)
            }

            HStack(spacing: AppSpacing.md) {
                Spacer()
                Button("Cancel") {
                    context.onCancel()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button(context.confirmButtonTitle, role: .destructive) {
                    context.onConfirm()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(AppSpacing.xxl)
        .frame(minWidth: 380, idealWidth: 440, maxWidth: 480)
    }

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(context.leadPrompt)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(context.targetTitle)
                        .font(AppFontScale.groupHeader)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle = context.targetSubtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let retentionNotice = context.retentionNotice {
                Text(retentionNotice)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("This action cannot be undone.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let plan = context.plan {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    CollapsibleSectionHeader(
                        title: "Deletion Details",
                        isExpanded: $isDetailsExpanded,
                        titleFont: .callout.weight(.medium)
                    )
                    .focusEffectDisabled()

                    if isDetailsExpanded {
                        Grid(alignment: .leading, horizontalSpacing: AppSpacing.lg, verticalSpacing: AppSpacing.xs) {
                            detailRow("Assets to delete", "\(plan.assetsToDelete.count)")
                            detailRow("Files to delete", "\(plan.deleteFileCount)")
                            detailRow("Retained assets", "\(plan.retainedAssets.count)")
                            detailRow("Retained files", "\(plan.retainedFileCount)")
                            if !plan.staleLiveAssetIDs.isEmpty {
                                detailRow("Stale live outputs", "\(plan.staleLiveAssetIDs.count)")
                            }
                        }
                        .padding(.leading, AppSpacing.xl)
                        .padding(.top, AppSpacing.xxs)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
