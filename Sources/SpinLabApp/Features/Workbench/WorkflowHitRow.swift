import SwiftUI

// MARK: - WorkflowHitRow

/// 通用搜索结果行。
/// 适用于所有 workflow 的 WorkflowMeasurementSearchHit 显示。
struct WorkflowHitRow: View {
    let hit: WorkflowMeasurementSearchHit
    let isSelected: Bool
    var numericDisplay: [String: String] = [:]
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .font(.body)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Workflow").font(.caption).foregroundStyle(.secondary)
                    Text(hit.workflowDisplayName).font(.body.weight(.semibold))
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Sample").font(.caption).foregroundStyle(.secondary)
                    Text(sampleDisplayText)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Condition").font(.caption).foregroundStyle(.secondary)
                    Text(hit.conditionSummary).font(.callout)
                }
                if !hit.channels.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Channels").font(.caption).foregroundStyle(.secondary)
                        Text(hit.channels.joined(separator: ", ")).font(.callout)
                    }
                }
                Text(hit.measurementFilePath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? AnyShapeStyle(Color.accentColor.opacity(0.08))
                : AnyShapeStyle(.regularMaterial),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .onTapGesture(perform: onTap)
    }

    private var sampleDisplayText: String {
        let base = hit.sampleBatchAndSubstrate
        guard !numericDisplay.isEmpty else { return base }
        let parts = NumericFieldOrder.preferred.compactMap { key -> String? in
            guard let value = numericDisplay[key],
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        // Append any keys not in preferred order
        let preferredSet = Set(NumericFieldOrder.preferred)
        let extra = numericDisplay.keys.sorted().compactMap { key -> String? in
            guard !preferredSet.contains(key),
                  let value = numericDisplay[key],
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        let all = parts + extra
        guard !all.isEmpty else { return base }
        return "\(base) (\(all.joined(separator: ", ")))"
    }
}
