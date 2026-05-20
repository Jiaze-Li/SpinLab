import SwiftUI

struct RuleExpandableRow<Detail: View>: View {
    let title: String
    let subtitle: String?
    let isExpanded: Bool
    let rowHasError: Bool
    let deleteAccessibilityLabel: String
    let onToggle: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let detail: () -> Detail

    init(
        title: String,
        subtitle: String? = nil,
        isExpanded: Bool,
        rowHasError: Bool,
        deleteAccessibilityLabel: String = "Delete",
        onToggle: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder detail: @escaping () -> Detail
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isExpanded = isExpanded
        self.rowHasError = rowHasError
        self.deleteAccessibilityLabel = deleteAccessibilityLabel
        self.onToggle = onToggle
        self.onDelete = onDelete
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { onToggle() }
            } label: {
                HStack(spacing: AppSpacing.md) {
                    Text(title)
                        .font(.callout.weight(.semibold).monospaced())
                        .foregroundStyle(rowHasError ? Color.red : .primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(deleteAccessibilityLabel)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, AppSpacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) {
                    if !isExpanded {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor))
                            .frame(height: 1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(isExpanded ? Color.accentColor.opacity(0.08) : .clear)
            .cornerRadius(AppSpacing.xs)
            .errorHighlight(rowHasError, cornerRadius: AppSpacing.xs)

            if isExpanded {
                detail()
                    .padding(AppSpacing.md)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(AppSpacing.md)
                    .padding(.top, AppSpacing.xs)
                    .padding(.bottom, AppSpacing.sm)
                Divider()
            }
        }
    }
}
