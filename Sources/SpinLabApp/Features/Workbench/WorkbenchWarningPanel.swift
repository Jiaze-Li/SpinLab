import SwiftUI

struct WorkbenchWarningPanel: View {
    let entries: [WorkbenchWarningEntry]

    @State private var isExpanded = true

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        if entries.isEmpty {
            GroupBox {
                Text("No warnings.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AppSpacing.xs)
            } label: {
                Label("Warnings (0)", systemImage: "checkmark.circle")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: AppSpacing.sm) {
                            Text(Self.timeFormatter.string(from: entry.timestamp))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 54, alignment: .leading)
                            Text("[\(entry.source)]")
                                .font(.caption2.bold())
                                .foregroundStyle(.orange)
                            Text(entry.message)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, AppSpacing.xs)
            } label: {
                Label("Warnings (\(entries.count))", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
            .groupBoxStyle(.automatic)
            .padding(.vertical, AppSpacing.xs)
        }
    }
}
