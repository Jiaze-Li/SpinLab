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
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
                Text("Sample Detail")
                    .font(AppFontScale.sectionTitle)
                Spacer(minLength: 0)
                if isEditingSelectedSample {
                    Button("Cancel") {
                        onCancelEdit()
                    }
                    Button("Save") {
                        onSaveEdit()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!sampleEditIsDirty || sampleEditIsSaving)
                } else {
                    Button("Delete") {
                        onDelete()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                    .disabled(!canEditSelectedLibrarySample)

                    Button("Edit") {
                        onBeginEdit()
                    }
                    .disabled(!canEditSelectedLibrarySample)
                }
            }

            FlowLayout(spacing: AppSpacing.sm) {
                Button("Numeric Log") {
                    onLoadGlobalManualLogs()
                }
                .buttonStyle(.bordered)

                Button("Metadata Log") {
                    onLoadMetadataSyncLogs()
                }
                .buttonStyle(.bordered)
            }

            if let sampleEditError {
                Text(sampleEditError)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if let sampleEditMessage {
                Text(sampleEditMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
