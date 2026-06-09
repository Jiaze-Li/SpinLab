import SwiftUI

// MARK: - WorkflowHitRow

/// 通用搜索结果行，所有 workflow 共用。
/// Line 1: selection icon + base sample name (no parens) + workflow badge (top-right)
/// Line 2: parenthetical numeric details, e.g. (1500 ps, 60 mT, 750 °C)
/// Line 3: condition tokens as chips, max 3, e.g. [0.5mA] [90deg] [50K]
/// Minimum font: .body (13pt on macOS), one step above AppFontScale.minimumReadable.
struct WorkflowHitRow: View {
    let hit: WorkflowMeasurementSearchHit
    let isSelected: Bool
    var numericDisplay: [String: String] = [:]
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Line 1: selection icon | base sample name | workflow badge
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.45))
                    .font(.system(size: 14))

                Text(hit.sampleBatchAndSubstrate)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(hit.workflowDisplayName)
                    .font(.body)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            // Line 2: parenthetical numeric details
            if let details = sampleDetails {
                Text(details)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 19)
            }

            // Line 3: condition chips, max 3
            if !conditionChips.isEmpty {
                HStack(spacing: 4) {
                    ForEach(conditionChips, id: \.self) { chip in
                        Text(chip)
                            .font(.body)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                            .foregroundStyle(Color.secondary)
                    }
                }
                .padding(.leading, 19)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? AnyShapeStyle(Color.accentColor.opacity(0.08))
                : AnyShapeStyle(Color.secondary.opacity(0.06)),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .help(tooltipText)
        .onTapGesture(perform: onTap)
    }

    // MARK: - Private

    private var sampleDetails: String? {
        guard !numericDisplay.isEmpty else { return nil }
        let parts = NumericFieldOrder.preferred.compactMap { key -> String? in
            guard let value = numericDisplay[key],
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        let preferredSet = Set(NumericFieldOrder.preferred)
        let extra = numericDisplay.keys.sorted().compactMap { key -> String? in
            guard !preferredSet.contains(key),
                  let value = numericDisplay[key],
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        let all = parts + extra
        guard !all.isEmpty else { return nil }
        return "(\(all.joined(separator: ", ")))"
    }

    private var conditionChips: [String] {
        guard !hit.conditions.isEmpty else { return [] }
        return hit.conditions
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .prefix(3)
            .map { $0.value }
    }

    private var tooltipText: String {
        let filename = URL(fileURLWithPath: hit.measurementFilePath).lastPathComponent
        var lines = [filename, hit.measurementFilePath]
        if hit.conditionSummary != "-" && !hit.conditionSummary.isEmpty {
            lines.append(hit.conditionSummary)
        }
        if !hit.channels.isEmpty {
            lines.append("Channels: \(hit.channels.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }
}
