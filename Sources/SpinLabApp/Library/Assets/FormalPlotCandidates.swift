import Foundation

/// Display facts of one replaceable formal Plot, as shown by the shared Plot Selector and the Library list.
/// Built from registered rows plus the small manifest; never decodes a processed matrix.
struct FormalPlotSummary: Identifiable, Equatable, Sendable {
    let plotID: String
    let revision: Int
    let isStale: Bool
    let title: String
    let workflowLabel: String
    let savedAt: Date
    let inputs: [PlotInputKey]
    let sampleUIDs: [String]
    let sampleLabels: [String]
    let batchLabels: [String]
    let fileNames: [String]
    let channelSummary: String
    var id: String { plotID }

    /// Stored Dataset/channel identity; nil when the registration is corrupt (never matched or replaced silently).
    var inputSet: Set<PlotInputKey>? {
        inputs.isEmpty || inputs.contains { $0.channelID == nil } ? nil : Set(inputs)
    }
}

/// What the user is saving right now (the current analysis), as seen by the ranker.
struct FormalPlotSaveSubject: Equatable, Sendable {
    let inputs: Set<PlotInputKey>
    let sampleUIDs: Set<String>
    let workflowLabel: String
    /// The Plot the user explicitly opened from the Library, if still the analysis target.
    let openedPlotID: String?
}

enum FormalPlotRelevance: Int, Comparable, CaseIterable, Sendable {
    case sameInputs = 0, sharesDataset = 1, sameSampleAndWorkflow = 2, other = 3
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .sameInputs: return "Same data and channel"
        case .sharesDataset: return "Shares a dataset"
        case .sameSampleAndWorkflow: return "Same sample"
        case .other: return "Other plots"
        }
    }
}

struct RankedFormalPlot: Identifiable, Equatable, Sendable {
    let summary: FormalPlotSummary
    let relevance: FormalPlotRelevance
    var id: String { summary.id }
}

enum FormalPlotRecommendation: Equatable, Sendable {
    case new
    case replace(plotID: String)
}

enum FormalPlotRanker {
    /// Corrupt registrations are excluded: they are shown as errors by the Library, never offered for replacement.
    static func rank(_ plots: [FormalPlotSummary], subject: FormalPlotSaveSubject) -> [RankedFormalPlot] {
        plots.compactMap { plot -> RankedFormalPlot? in
            guard let set = plot.inputSet else { return nil }
            let relevance: FormalPlotRelevance
            if set == subject.inputs {
                relevance = .sameInputs
            } else if !set.map(\.datasetID).filter({ id in subject.inputs.contains { $0.datasetID == id } }).isEmpty {
                relevance = .sharesDataset
            } else if !Set(plot.sampleUIDs).isDisjoint(with: subject.sampleUIDs), plot.workflowLabel == subject.workflowLabel {
                relevance = .sameSampleAndWorkflow
            } else {
                relevance = .other
            }
            return RankedFormalPlot(summary: plot, relevance: relevance)
        }
        .sorted { a, b in
            if a.relevance != b.relevance { return a.relevance < b.relevance }
            if a.relevance == .sharesDataset {
                let oa = overlap(a.summary, subject), ob = overlap(b.summary, subject)
                if oa != ob { return oa > ob }
            }
            if a.summary.savedAt != b.summary.savedAt { return a.summary.savedAt > b.summary.savedAt }
            return a.summary.plotID < b.summary.plotID
        }
    }

    /// Default action from the Library record alone (never from session memory): an explicitly opened and still
    /// valid Plot first, else the most recently saved Plot with the identical Dataset set and channel, else New.
    static func recommend(_ plots: [FormalPlotSummary], subject: FormalPlotSaveSubject) -> FormalPlotRecommendation {
        if let opened = subject.openedPlotID, plots.contains(where: { $0.plotID == opened && $0.inputSet != nil }) {
            return .replace(plotID: opened)
        }
        if let best = rank(plots, subject: subject).first(where: { $0.relevance == .sameInputs }) {
            return .replace(plotID: best.summary.plotID)
        }
        return .new
    }

    /// Case-insensitive match over title, sample, batch, workflow and original file names; empty query keeps all.
    static func filter(_ plots: [RankedFormalPlot], query: String) -> [RankedFormalPlot] {
        let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return plots }
        return plots.filter { item in
            let haystack = ([item.summary.title, item.summary.workflowLabel, item.summary.channelSummary]
                + item.summary.sampleLabels + item.summary.batchLabels + item.summary.fileNames).joined(separator: " ").lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    private static func overlap(_ plot: FormalPlotSummary, _ subject: FormalPlotSaveSubject) -> Int {
        Set(plot.inputs.map(\.datasetID)).intersection(subject.inputs.map(\.datasetID)).count
    }
}

// MARK: - Registered Plots -> summaries

/// Reads registered Plots and their small manifests into display summaries. Workflow-neutral at the
/// call site (the Plot Selector and Library list share it); today only `afm_plot_v1` exists.
struct FormalPlotLibrary {
    let service: LibraryAssetService

    func summaries(rootURL: URL) throws -> [FormalPlotSummary] {
        let rows = try service.listPlots(rootURL: rootURL)
        let datasets = try service.listAnalysisDatasets(format: AFMDatasetCodec.format, rootURL: rootURL)
        let byDataset = Dictionary(datasets.map { ($0.datasetID, $0) }, uniquingKeysWith: { a, _ in a })
        return rows.map { row in
            let manifest = (try? service.readPlotFile(plotID: row.id, name: AFMPlotCodec.manifestName, rootURL: rootURL))
                .flatMap { try? AFMPlotCodec.decodeManifest($0) }
            let info = row.inputs.compactMap { byDataset[$0.datasetID] }
            return FormalPlotSummary(
                plotID: row.id, revision: row.record.currentRevision, isStale: row.record.liveState == "stale",
                title: manifest?.resolvedTitle.isEmpty == false ? manifest!.resolvedTitle : (manifest?.title ?? "Unreadable plot"),
                workflowLabel: "AFM", savedAt: manifest?.savedAt ?? .distantPast, inputs: row.inputs,
                sampleUIDs: row.sampleUIDs,
                sampleLabels: Array(Set(info.map(\.sampleDisplayName))).sorted(),
                batchLabels: Array(Set(info.map(\.batchID))).sorted(),
                fileNames: info.map(\.originalFileName),
                channelSummary: manifest?.channelLabel ?? ""
            )
        }
    }

    /// One Plot's stored figure for a thumbnail or preview.
    func png(plotID: String, rootURL: URL) -> Data? {
        try? service.readPlotFile(plotID: plotID, name: AFMPlotCodec.pngName, rootURL: rootURL)
    }
}
