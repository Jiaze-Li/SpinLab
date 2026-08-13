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
