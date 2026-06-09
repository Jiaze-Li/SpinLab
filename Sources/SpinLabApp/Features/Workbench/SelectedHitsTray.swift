import SwiftUI

struct SelectedHitsTray: View {
    let workflowID: WorkbenchWorkflowID
    let workbench: WorkbenchFeatureStore

    var body: some View {
        let infos = workbench.selectedHitDisplayInfos(for: workflowID)
        let count = workbench.selectedCount(for: workflowID)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("Selected (\(count))")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Clear") {
                    workbench.deselectAll(for: workflowID)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(infos, id: \.id) { info in
                        SelectedHitsTrayRow(info: info) {
                            workbench.toggleSearchHitSelection(info.id, for: workflowID)
                        }
                    }
                }
                .padding(6)
            }
        }
    }
}

private struct SelectedHitsTrayRow: View {
    let info: SelectedHitDisplayInfo
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Line 1: sample name left · workflow badge + remove right
            HStack(alignment: .center, spacing: 4) {
                Text(info.sampleBatchAndSubstrate)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(info.workflowDisplayName)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(Color.accentColor)
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            // Line 2: condition chips (values only, max 3)
            if !conditionChips.isEmpty {
                HStack(spacing: 3) {
                    ForEach(conditionChips, id: \.self) { chip in
                        Text(chip)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Line 3: filename
            Text(info.shortFilename)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
    }

    /// Parses "key=value, key=value, …" → value strings only, max 3.
    private var conditionChips: [String] {
        guard info.conditionSummary != "-", !info.conditionSummary.isEmpty else { return [] }
        return info.conditionSummary
            .components(separatedBy: ", ")
            .compactMap { pair -> String? in
                if let eq = pair.firstIndex(of: "=") {
                    let v = String(pair[pair.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                    return v.isEmpty ? nil : v
                }
                return pair.isEmpty ? nil : pair
            }
            .prefix(3)
            .map { $0 }
    }
}
