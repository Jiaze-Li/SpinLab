import SwiftUI

struct SelectedHitsTray: View {
    let workflowID: WorkbenchWorkflowID
    let workbench: WorkbenchFeatureStore

    var body: some View {
        let infos = workbench.selectedHitDisplayInfos(for: workflowID)
        let count = workbench.selectedCount(for: workflowID)

        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Selected (\(count))")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Clear") {
                    workbench.deselectAll(for: workflowID)
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(infos, id: \.id) { info in
                        SelectedHitsTrayRow(info: info) {
                            workbench.toggleSearchHitSelection(info.id, for: workflowID)
                        }
                    }
                }
                .padding(5)
            }
        }
    }
}

private struct SelectedHitsTrayRow: View {
    let info: SelectedHitDisplayInfo
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line1)
                    .font(.caption2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(info.shortFilename)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 2)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.top, 1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
    }

    private var line1: String {
        var tokens: [String] = [info.sampleBatchAndSubstrate, "·", info.workflowDisplayName]
        if !info.conditionSummary.isEmpty && info.conditionSummary != "-" {
            tokens += ["·", info.conditionSummary]
        }
        return tokens.joined(separator: " ")
    }
}
