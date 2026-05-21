import SwiftUI

// MARK: - WorkbenchResultHeaderShell

/// Shared Workbench result header block.
///
/// Owns the result title row, clear/save actions, and the load-pack affordance.
/// Render state stays compatible with `WorkbenchReadAdapter` because callers
/// can project the same active-image / active-result state into the block.
struct WorkbenchResultHeaderShell<Store: WorkbenchWorkspaceProviding>: View {
    let store: Store
    let analysisMessage: String?
    let warningCount: Int
    let isAnalyzing: Bool
    let hasAnalysisResult: Bool
    let hasActiveImageData: Bool

    let onClearPlot: () -> Void
    let onSaveAnalysis: () -> Void
    let onSaveToLibrary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Result")
                    .font(AppFontScale.sectionTitle)
                Spacer()

                Button("Clear Plot") {
                    onClearPlot()
                }
                .buttonStyle(.bordered)
                .disabled(!hasActiveImageData && !isAnalyzing)

                if store.matchingVaultPack != nil {
                    Button("Update Analysis") {
                        onSaveAnalysis()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasAnalysisResult)
                } else {
                    Button("Save Analysis") {
                        onSaveAnalysis()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasAnalysisResult)
                }

                Button("Save to Library") {
                    onSaveToLibrary()
                }
                .buttonStyle(.bordered)
                .disabled(!hasAnalysisResult)
            }

            if let pack = store.matchingVaultPack {
                Text("→ \(pack.label)")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }

            if let msg = analysisMessage {
                if warningCount > 0 {
                    (Text(msg).foregroundStyle(.secondary)
                     + Text(" (\(warningCount) warning(s))").foregroundStyle(.orange))
                        .font(.callout)
                        .textSelection(.enabled)
                } else {
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
            }
        }
    }
}
