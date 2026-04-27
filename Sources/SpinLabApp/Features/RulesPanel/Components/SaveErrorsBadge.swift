import SwiftUI

struct SaveErrorsBadge: View {
    let errors: [RulesPanelFieldError]

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("\(errors.count) validation error\(errors.count == 1 ? "" : "s")")
            }
            .font(.callout)
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                ForEach(errors) { error in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(error.field)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(error.message)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(AppSpacing.md)
            .frame(minWidth: 280, maxWidth: 480, alignment: .leading)
        }
    }
}
