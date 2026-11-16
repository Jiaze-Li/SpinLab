import SwiftUI

/// Publish area detail pane: the script output of the latest run.
struct PublishDetailView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let lines = appState.publish.outputLines
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Output")
                .font(.headline)
            if lines.isEmpty {
                Text("No output yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(lines.map { "\($0.kind == .stderr ? "stderr" : "stdout"): \($0.line)" }.joined(separator: "\n"))
                        .font(.callout.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
