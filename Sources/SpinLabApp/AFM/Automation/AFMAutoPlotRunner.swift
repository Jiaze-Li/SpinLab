import Foundation
import Observation

/// What the user can see about one automatic attempt.
struct AutoPlotReport: Identifiable, Equatable, Sendable {
    let datasetID: String
    let revision: Int?
    let sampleUID: String?
    let result: AutoPlotRunResult
    let finishedAt: Date
    var id: String { "\(datasetID)#\(revision.map(String.init) ?? "now")" }
}

/// Runs automatic AFM plots in the background, one at a time, after an import has committed.
/// It owns no storage: intents live in the Library (persisted with the ingest), receipts in
/// `asset_operations`. Failures never touch the import that triggered them.
@MainActor
@Observable
final class AFMAutoPlotRunner {
    private(set) var reports: [AutoPlotReport] = []
    /// Bumped on every report change, including a retry that replaces a report with the same id.
    private(set) var reportVersion = 0
    private(set) var pendingCount = 0
    /// Called on the main actor after at least one plot was published, so lists can refresh.
    @ObservationIgnored var onPublished: (() -> Void)?

    /// Tests inject a service bound to their own write lease.
    @ObservationIgnored var makeService: (LibraryStore) -> LibraryAssetService = { LibraryAssetService(libraryStore: $0) }
    @ObservationIgnored private var chain: Task<Void, Never>?
    @ObservationIgnored private var inFlight = Set<String>()
    private static let reportLimit = 200

    // MARK: Entry points

    /// After an ingest committed: one attempt per new Dataset, using the persisted intent.
    func enqueue(triggers: [AutoPlotTrigger], libraryStore: LibraryStore) {
        for trigger in triggers {
            let service = makeService(libraryStore)
            let items = trigger.datasetIDs.map {
                WorkItem(datasetID: $0, revision: trigger.datasetRevision, sampleUID: trigger.sampleUID, intentVersion: trigger.intent.presetVersionID)
            }
            submit(items, rootURL: trigger.rootURL, service: service, silentSuccess: false)
        }
    }

    /// When a writable Library has been opened: re-evaluate unfinished intents for the applied preset.
    func recover(rootURL: URL, libraryStore: LibraryStore) {
        let service = makeService(libraryStore)
        pendingCount += 1
        let previous = chain
        chain = Task { [weak self] in
            await previous?.value
            let items: [WorkItem] = await Task.detached(priority: .utility) {
                guard let run = try? service.beginAutoPlotRun(rootURL: rootURL),
                      let pending = try? service.pendingAutoPlotIntents(
                        presetVersionID: run.context.presetVersionID, format: AFMDatasetCodec().datasetFormat, rootURL: rootURL
                      ) else { return [] }
                return pending.map {
                    WorkItem(datasetID: $0.datasetID, revision: $0.revision, sampleUID: $0.sampleUID, intentVersion: $0.presetVersionID)
                }
            }.value
            self?.pendingCount -= 1
            guard !items.isEmpty else { return }
            await self?.execute(items, rootURL: rootURL, service: service, silentSuccess: true)
        }
    }

    /// Explicit user action for one existing Dataset, using the applied preset as it is now.
    func rerun(datasetID: String, rootURL: URL, libraryStore: LibraryStore) {
        let service = makeService(libraryStore)
        submit([WorkItem(datasetID: datasetID, revision: nil, sampleUID: nil, intentVersion: nil)],
               rootURL: rootURL, service: service, silentSuccess: false)
    }

    /// Returns once everything queued so far has finished.
    func waitUntilIdle() async {
        while let current = chain {
            await current.value
            if chain == current { break }
        }
    }

    func latestReport(datasetID: String) -> AutoPlotReport? {
        reports.last { $0.datasetID == datasetID }
    }

    func clearReports() { reports.removeAll(); reportVersion += 1 }

    // MARK: Internals

    struct WorkItem: Sendable {
        let datasetID: String
        let revision: Int?
        let sampleUID: String?
        let intentVersion: String?
    }

    private func submit(_ items: [WorkItem], rootURL: URL, service: LibraryAssetService, silentSuccess: Bool) {
        guard !items.isEmpty else { return }
        pendingCount += items.count
        let previous = chain
        chain = Task { [weak self] in
            await previous?.value
            self?.pendingCount -= items.count
            await self?.execute(items, rootURL: rootURL, service: service, silentSuccess: silentSuccess)
        }
    }

    private func execute(_ items: [WorkItem], rootURL: URL, service: LibraryAssetService, silentSuccess: Bool) async {
        let rootPath = LibraryWriteLease.canonicalPath(of: rootURL)
        for item in items {
            let key = "\(rootPath)|\(item.datasetID)|\(item.revision.map(String.init) ?? "now")"
            guard inFlight.insert(key).inserted else { continue }   // single flight per intent
            let result = await Task.detached(priority: .utility) {
                Self.runOne(item, rootURL: rootURL, service: service)
            }.value
            inFlight.remove(key)
            if silentSuccess, result == .alreadyPublished { continue }
            record(AutoPlotReport(
                datasetID: item.datasetID, revision: item.revision, sampleUID: item.sampleUID, result: result, finishedAt: Date()
            ))
            if case .published = result { onPublished?() }
        }
    }

    private func record(_ report: AutoPlotReport) {
        reportVersion += 1
        reports.removeAll { $0.id == report.id }
        reports.append(report)
        if reports.count > Self.reportLimit { reports.removeFirst(reports.count - Self.reportLimit) }
    }

    nonisolated static func runOne(_ item: WorkItem, rootURL: URL, service: LibraryAssetService) -> AutoPlotRunResult {
        do {
            guard let run = try service.beginAutoPlotRun(rootURL: rootURL) else {
                return item.intentVersion == nil
                    ? .cancelled("Automatic plotting is off. Turn it on in the AFM preset first.")
                    : .cancelled("Automatic plotting was turned off.")
            }
            if let version = item.intentVersion, version != run.context.presetVersionID {
                return .cancelled("The preset was changed after this import. Use Run auto plot to apply the new one.")
            }
            return AFMAutoPlotService(assetService: service).run(
                datasetID: item.datasetID, expectedRevision: item.revision, rootURL: rootURL,
                context: run.context, preset: run.preset
            )
        } catch {
            return .failed(error.localizedDescription, retryable: true)
        }
    }
}
