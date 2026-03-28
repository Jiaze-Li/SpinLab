import SwiftUI

struct SelectionEntry {
    let source: LibrarySelectionSource
    let browserSampleId: String?
    let drawerPrefix: String?
    let drawerBatchId: String?
    let drawerSampleId: String?
}

struct SearchResultItem: Identifiable, Hashable {
    var id: String { "\(prefix)|\(sample.id)" }
    let prefix: String
    let sample: LibrarySample
}

struct SampleDetailSections {
    let sampleFields: [DetailField]
    let substrateFields: [DetailField]
    let numericFields: [DetailField]
    let metadataFields: [DetailField]

    var allFields: [DetailField] {
        sampleFields + substrateFields + numericFields + metadataFields
    }
}

struct ChangeHighlight: Identifiable, Hashable {
    var id: String { "\(key)|\(description)" }
    let key: String
    let description: String
}

struct DetailField: Hashable {
    let label: String
    let value: String
    var monospaced: Bool = false
    var fullWidth: Bool = false
}

struct PreviewSampleRow: View {
    let sample: LibrarySample
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
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
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}
