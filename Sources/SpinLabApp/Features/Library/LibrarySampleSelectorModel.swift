import Foundation

/// Pure presentation model for the Sample Workspace's Sample selector.
/// Holds no selection state: the committed Drawer selection lives in
/// `LibraryFeatureStore`; this only describes how to present the options.
struct LibrarySampleSelectorModel: Equatable {
    enum Style: Equatable {
        case empty
        case single
        case chips
        case menu
    }

    struct Option: Equatable, Identifiable {
        let id: String
        /// Primary label (never empty).
        let title: String
        /// Disambiguating secondary text (sample key when the title is not unique).
        let subtitle: String?
    }

    /// Up to this many samples are shown as a horizontal chip strip.
    static let maxChipCount = 6

    let style: Style
    let options: [Option]

    init(samples: [LibrarySample]) {
        let rawTitles = samples.map { Self.baseTitle(for: $0) }
        var counts: [String: Int] = [:]
        for t in rawTitles { counts[t, default: 0] += 1 }
        options = zip(samples, rawTitles).map { sample, title in
            let duplicated = (counts[title] ?? 0) > 1
            return Option(id: sample.id, title: title, subtitle: duplicated ? sample.id : nil)
        }
        switch samples.count {
        case 0: style = .empty
        case 1: style = .single
        case 2...Self.maxChipCount: style = .chips
        default: style = .menu
        }
    }

    static func baseTitle(for sample: LibrarySample) -> String {
        let name = sample.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let substrate = sample.substrateDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        return substrate.isEmpty ? sample.id : substrate
    }

    /// Case-insensitive match over title, subtitle and key.
    func filtered(by query: String) -> [Option] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return options }
        return options.filter {
            $0.title.lowercased().contains(q)
                || $0.id.lowercased().contains(q)
                || ($0.subtitle?.lowercased().contains(q) ?? false)
        }
    }

    /// The sample the page should display: the committed selection only if it
    /// belongs to this batch's samples; never a fallback to another batch.
    func isValidSelection(_ sampleId: String?) -> Bool {
        guard let sampleId else { return false }
        return options.contains { $0.id == sampleId }
    }
}
