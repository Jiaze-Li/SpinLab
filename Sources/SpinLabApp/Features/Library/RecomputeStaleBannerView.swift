import SwiftUI

struct RecomputeStaleBannerView: View {
    let staleCount: Int
    let onDismiss: () -> Void
    let onViewPreview: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
            Text("\(staleCount) 个测量基于旧规则，可重算")
                .font(.callout)
            Spacer(minLength: AppSpacing.sm)
            Button("稍后") { onDismiss() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("查看重算预览") { onViewPreview() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.22), lineWidth: 0.8)
        )
    }
}
