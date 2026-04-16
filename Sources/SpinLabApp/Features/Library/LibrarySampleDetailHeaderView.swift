import SwiftUI

struct LibrarySampleDetailHeaderView: View {
    let isEditingSelectedSample: Bool
    let sampleEditIsDirty: Bool
    let sampleEditIsSaving: Bool
    let canEditSelectedLibrarySample: Bool
    let sampleEditError: String?
    let sampleEditMessage: String?

    let onLoadGlobalManualLogs: () -> Void
    let onLoadMetadataSyncLogs: () -> Void
    let onCancelEdit: () -> Void
    let onSaveEdit: () -> Void
    let onBeginEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sample Detail")
                    .font(AppFontScale.sectionTitle)
                Spacer()
                Button("Numeric日志") {
                    onLoadGlobalManualLogs()
                }
                Button("Metadata日志") {
                    onLoadMetadataSyncLogs()
                }
                if isEditingSelectedSample {
                    Button("Cancel") {
                        onCancelEdit()
                    }
                    Button("Save") {
                        onSaveEdit()
                    }
                    .disabled(!sampleEditIsDirty || sampleEditIsSaving)
                } else {
                    Button("Edit") {
                        onBeginEdit()
                    }
                    .disabled(!canEditSelectedLibrarySample)
                }
            }

            if let sampleEditError {
                Text(sampleEditError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let sampleEditMessage {
                Text(sampleEditMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
