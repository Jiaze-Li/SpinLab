import SwiftUI

struct RuleExpandableRow<Detail: View>: View {
    let title: String
    let subtitle: String?
    let isExpanded: Bool
    let rowHasError: Bool
    let deleteAccessibilityLabel: String
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?
    let onToggle: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let detail: () -> Detail

    init(
        title: String,
        subtitle: String? = nil,
        isExpanded: Bool,
        rowHasError: Bool,
        deleteAccessibilityLabel: String = "Delete",
        onMoveUp: (() -> Void)? = nil,
        onMoveDown: (() -> Void)? = nil,
        onToggle: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder detail: @escaping () -> Detail
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isExpanded = isExpanded
        self.rowHasError = rowHasError
        self.deleteAccessibilityLabel = deleteAccessibilityLabel
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onToggle = onToggle
        self.onDelete = onDelete
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { onToggle() }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Text(title)
                        .font(.body.weight(.semibold).monospaced())
                        .foregroundStyle(rowHasError ? Color.red : .primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let onMoveUp {
                        Button(action: onMoveUp) {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .accessibilityLabel("Move \(title) up")
                    }
                    if let onMoveDown {
                        Button(action: onMoveDown) {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .accessibilityLabel("Move \(title) down")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityLabel(deleteAccessibilityLabel)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, AppSpacing.lg)
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
