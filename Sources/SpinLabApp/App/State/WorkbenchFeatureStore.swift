import Foundation
import Observation

@MainActor
@Observable
final class WorkbenchFeatureStore {
    private let workbenchState = WorkbenchState()

    var archivedRecords: [SpinLabDomain.ArchivedRecord]
    var projectCatalog: [SpinLabDomain.Project]
    var selectedArchivedRecordID: UUID?
    var workbenchResultDraft: String = ""

    @ObservationIgnored
    private var archivedRecordsProjectionTask: Task<Void, Never>?
    @ObservationIgnored
    private var projectCatalogProjectionTask: Task<Void, Never>?
    @ObservationIgnored
    private var bufferedArchivedRecordsProjection: [SpinLabDomain.ArchivedRecord]?
    @ObservationIgnored
    private var bufferedProjectCatalogProjection: [SpinLabDomain.Project]?
    @ObservationIgnored
    private var isArchivedRecordsProjectionDrainScheduled = false
    @ObservationIgnored
    private var isProjectCatalogProjectionDrainScheduled = false

    @ObservationIgnored
    private let libraryRepository: LibraryRepository

    init(libraryRepository: LibraryRepository) {
        self.libraryRepository = libraryRepository
        self.archivedRecords = libraryRepository.archivedRecords
        self.projectCatalog = libraryRepository.projects
        self.selectedArchivedRecordID = self.archivedRecords.first?.id
    }

    deinit {
        archivedRecordsProjectionTask?.cancel()
        projectCatalogProjectionTask?.cancel()
    }

    func replaceArchivedRecords(_ records: [SpinLabDomain.ArchivedRecord], persist: Bool = true) -> [SpinLabDomain.ArchivedRecord] {
        let updated = libraryRepository.replaceArchivedRecords(records, persist: persist)
        archivedRecords = updated
        return updated
    }

    func replaceProjectCatalog(_ projects: [SpinLabDomain.Project], persist: Bool = true) -> [SpinLabDomain.Project] {
        let updated = libraryRepository.replaceProjects(projects, persist: persist)
        projectCatalog = updated
        return updated
    }

    func setupProjectionTasks(
        onArchivedRecordsProjected: @escaping @MainActor ([SpinLabDomain.ArchivedRecord]) -> Void,
        onProjectCatalogProjected: @escaping @MainActor ([SpinLabDomain.Project]) -> Void
    ) {
        archivedRecordsProjectionTask?.cancel()
        projectCatalogProjectionTask?.cancel()

        archivedRecordsProjectionTask = Task { [weak self] in
            guard let self else { return }
            for await records in libraryRepository.archivedRecordsStream {
                self.bufferArchivedRecordsProjection(records, onProjected: onArchivedRecordsProjected)
            }
        }

        projectCatalogProjectionTask = Task { [weak self] in
            guard let self else { return }
            for await projects in libraryRepository.projectsStream {
                self.bufferProjectCatalogProjection(projects, onProjected: onProjectCatalogProjected)
            }
        }
    }

    func restoreInteraction(
        selectedArchivedRecordID: UUID?,
        workbenchResultDraft: String
    ) {
        if let selectedArchivedRecordID,
           archivedRecords.contains(where: { $0.id == selectedArchivedRecordID }) {
            self.selectedArchivedRecordID = selectedArchivedRecordID
        }
        self.workbenchResultDraft = workbenchResultDraft
    }

    func captureInteraction(into snapshot: inout SpinLabInteractionSnapshot) {
        snapshot.selectedArchivedRecordID = selectedArchivedRecordID
        snapshot.workbenchResultDraft = workbenchResultDraft
    }

    func selectedArchivedRecord() -> SpinLabDomain.ArchivedRecord? {
        guard let selectedArchivedRecordID else {
            return nil
        }
        return archivedRecords.first { $0.id == selectedArchivedRecordID }
    }

    @discardableResult
    func selectArchivedRecord(
        _ recordID: UUID,
        analysisModule: AnalysisModuleExtension
    ) -> Bool {
        guard let record = archivedRecords.first(where: { $0.id == recordID }) else {
            return false
        }
        selectedArchivedRecordID = recordID
        workbenchResultDraft = workbenchState.resolvedSummary(
            for: record.measurement,
            draftSummary: record.latestResult?.summary ?? "",
            analysisModule: analysisModule
        )
        return true
    }

    func saveWorkbenchResult(analysisModule: AnalysisModuleExtension) -> [SpinLabDomain.ArchivedRecord]? {
        guard let selectedArchivedRecordID else {
            return nil
        }
        guard let recordIndex = archivedRecords.firstIndex(where: { $0.id == selectedArchivedRecordID }) else {
            return nil
        }

        var record = archivedRecords[recordIndex]
        let existingResultID = record.latestResult?.id ?? UUID()
        record.latestResult = SpinLabDomain.Result(
            id: existingResultID,
            measurementID: record.measurement.id,
            summary: workbenchState.resolvedSummary(
                for: record.measurement,
                draftSummary: workbenchResultDraft,
                analysisModule: analysisModule
            ),
            rating: record.latestResult?.rating,
            updatedAt: .now
        )

        archivedRecords[recordIndex] = record
        return archivedRecords
    }

    @MainActor
    private func bufferArchivedRecordsProjection(
        _ records: [SpinLabDomain.ArchivedRecord],
        onProjected: @escaping @MainActor ([SpinLabDomain.ArchivedRecord]) -> Void
    ) {
        bufferedArchivedRecordsProjection = records
        scheduleProjectionDrainIfNeeded(
            scheduledFlag: \.isArchivedRecordsProjectionDrainScheduled,
            bufferedValue: \.bufferedArchivedRecordsProjection,
            apply: { [weak self] value in
                guard let self else { return }
                self.archivedRecords = value
                onProjected(value)
            }
        )
    }

    @MainActor
    private func bufferProjectCatalogProjection(
        _ projects: [SpinLabDomain.Project],
        onProjected: @escaping @MainActor ([SpinLabDomain.Project]) -> Void
    ) {
        bufferedProjectCatalogProjection = projects
        scheduleProjectionDrainIfNeeded(
            scheduledFlag: \.isProjectCatalogProjectionDrainScheduled,
            bufferedValue: \.bufferedProjectCatalogProjection,
            apply: { [weak self] value in
                guard let self else { return }
                self.projectCatalog = value
                onProjected(value)
            }
        )
    }

    @MainActor
    private func scheduleProjectionDrainIfNeeded<T>(
        scheduledFlag: ReferenceWritableKeyPath<WorkbenchFeatureStore, Bool>,
        bufferedValue: ReferenceWritableKeyPath<WorkbenchFeatureStore, T?>,
        apply: @escaping @MainActor (T) -> Void
    ) {
        guard !self[keyPath: scheduledFlag] else {
            return
        }
        self[keyPath: scheduledFlag] = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            if let value = self[keyPath: bufferedValue] {
                apply(value)
                self[keyPath: bufferedValue] = nil
            }
            self[keyPath: scheduledFlag] = false
        }
    }
}
