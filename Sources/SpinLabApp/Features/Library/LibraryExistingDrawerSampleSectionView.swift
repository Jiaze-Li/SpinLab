import SwiftUI

struct LibraryExistingDrawerSampleSectionView: View {

    let selectedPrefix: String?
    let selectedBatchId: String?
    let selectedSampleId: String?
    let selectedExistingBatchSamples: [LibrarySample]
    let onSelectSample: (LibrarySample) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Existing Drawer Samples")
                .font(AppFontScale.sectionHeader)
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    if let selectedPrefix, let selectedBatchId {
                        HStack {
                            Text("Batch")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(selectedPrefix)/\(selectedBatchId)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if selectedExistingBatchSamples.isEmpty {
                            Text("No samples found in selected drawer")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(selectedExistingBatchSamples) { sample in
                                        Button {
                                            onSelectSample(sample)
                                        } label: {
                                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                                Text(sample.substrateDisplay)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                            }
                                            .padding(6)
                                            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(selectedSampleId == sample.id ? Color.accentColor.opacity(0.15) : Color.clear)
                                            )
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(height: 220)
                        }
                    } else {
                        Text("Select a batch in the left Library tree to choose its samples")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Sample List")
                    .font(AppFontScale.groupHeader)
            }
        }
    }
}
