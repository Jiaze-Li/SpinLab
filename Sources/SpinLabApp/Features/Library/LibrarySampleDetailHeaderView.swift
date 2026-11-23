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
                    .workbenchProbed("library.detailHeader.title")
                Spacer(minLength: 0)
                if isEditingSelectedSample {
                    Button("Cancel") {
                        onCancelEdit()
                    }
                    .workbenchProbed("library.detailHeader.cancel")
                    Button("Save") {
                        onSaveEdit()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!sampleEditIsDirty || sampleEditIsSaving)
                    .workbenchProbed("library.detailHeader.save")
                } else {
                    Button("Delete") {
                        onDelete()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                    .disabled(!canEditSelectedLibrarySample)
                    .workbenchProbed("library.detailHeader.delete")

                    Button("Edit") {
                        onBeginEdit()
                    }
                    .disabled(!canEditSelectedLibrarySample)
                    .workbenchProbed("library.detailHeader.edit")
                }
            }

            FlowLayout(spacing: AppSpacing.sm) {
                Button("Numeric Log") {
                    onLoadGlobalManualLogs()
                }
                .buttonStyle(.bordered)
                .workbenchProbed("library.detailHeader.numericLog")

                Button("Metadata Log") {
                    onLoadMetadataSyncLogs()
                }
                .buttonStyle(.bordered)
                .workbenchProbed("library.detailHeader.metadataLog")
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
