import Foundation
import Testing
@testable import SpinLabApp

@Suite("V2.4.0 Workflow Registry")
struct V240WorkflowRegistryTests {
    @Test("empty registry seeds defaults on first load")
    func seedsDefaultsOnFirstLoad() throws {
        let fileURL = try makeRegistryFileURL(prefix: "seed")
        let store = WorkflowRegistryStore(registryFileURL: fileURL)

        let loaded = store.load()

        #expect(loaded.count == 2)
        #expect(loaded.contains(where: { $0.id == "XY" && $0.displayName == "XY Rotation" }))
        #expect(loaded.contains(where: { $0.id == "RT" && $0.displayName == "RT" }))
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("adding workflow persists after reload")
    func addPersistsAcrossStoreReload() throws {
        let fileURL = try makeRegistryFileURL(prefix: "add")
        let first = WorkflowRegistryStore(registryFileURL: fileURL)
        _ = first.load()

        try first.add(
            WorkflowDefinition(
                id: "AHE",
                displayName: "Anomalous Hall",
                parentID: nil,
                conditionFields: [
                    WorkflowConditionField(definitionID: "temperature")
                ]
            )
        )

        let second = WorkflowRegistryStore(registryFileURL: fileURL)
        let reloaded = second.load()

        #expect(reloaded.contains(where: { $0.id == "AHE" && $0.displayName == "Anomalous Hall" }))
    }

    @Test("removing workflow updates stored json")
    func removeUpdatesJSON() throws {
        let fileURL = try makeRegistryFileURL(prefix: "remove")
        let store = WorkflowRegistryStore(registryFileURL: fileURL)
        _ = store.load()

        try store.remove(id: "RT")

        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode([WorkflowDefinition].self, from: data)

        #expect(decoded.contains(where: { $0.id == "RT" }) == false)
    }

    @Test("editing condition selection persists")
    func editConditionSelectionPersists() throws {
        let fileURL = try makeRegistryFileURL(prefix: "edit")
        let first = WorkflowRegistryStore(registryFileURL: fileURL)
        _ = first.load()

        guard var xy = first.definition(for: "XY") else {
            Issue.record("Expected seeded XY workflow.")
            return
        }
        guard let firstField = xy.conditionFields.first else {
            Issue.record("Expected seeded XY condition field.")
            return
        }

        xy.conditionFields[0] = WorkflowConditionField(
            definitionID: firstField.definitionID
        )
        try first.update(xy)

        let second = WorkflowRegistryStore(registryFileURL: fileURL)
        let reloaded = second.load()
        let updated = reloaded.first(where: { $0.id == "XY" })

        #expect(updated?.conditionFields.first?.definitionID == firstField.definitionID)
    }

    @Test("duplicate workflow id is rejected in feature store")
    func duplicateWorkflowIDRejected() async throws {
        let fileURL = try makeRegistryFileURL(prefix: "duplicate-id")
        let store = WorkflowRegistryStore(registryFileURL: fileURL)
        let persistence = LocalPersistenceStub(
            pendingImports: [],
            archivedRecords: [],
            projects: [],
            interactionSnapshot: SpinLabInteractionSnapshot()
        )
        let repository = LibraryRepository(persistence: persistence)

        let featureStore = await MainActor.run {
            WorkbenchFeatureStore(
                libraryRepository: repository,
                workflowRegistryStore: store
            )
        }

        await MainActor.run {
            let originalID = featureStore.workflowDefinitions.first?.id ?? "XY"
            let targetID = featureStore.workflowDefinitions.first(where: { $0.id != originalID })?.id ?? "RT"
            featureStore.selectWorkflow(originalID)
            featureStore.updateSelectedWorkflow(
                id: targetID,
                displayName: "Duplicate",
                parentID: nil
            )
            #expect(featureStore.workflowRegistryMessage == "Workflow ID must be unique.")
            #expect(featureStore.workflowDefinitions.contains(where: { $0.id == originalID }))
        }
    }

    @Test("empty condition label is rejected in feature store")
    func emptyConditionLabelRejected() async throws {
        let fileURL = try makeRegistryFileURL(prefix: "empty-definition")
        let store = WorkflowRegistryStore(registryFileURL: fileURL)
        let persistence = LocalPersistenceStub(
            pendingImports: [],
            archivedRecords: [],
            projects: [],
            interactionSnapshot: SpinLabInteractionSnapshot()
        )
        let repository = LibraryRepository(persistence: persistence)

        let featureStore = await MainActor.run {
            WorkbenchFeatureStore(
                libraryRepository: repository,
                workflowRegistryStore: store
            )
        }

        await MainActor.run {
            let selectedID = featureStore.workflowDefinitions.first?.id
            featureStore.selectWorkflow(selectedID)
            let originalDefinitionID = featureStore.selectedWorkflowDefinition?.conditionFields.first?.definitionID
            featureStore.updateConditionFieldOnSelectedWorkflow(
                at: 0,
                definitionID: "   "
            )
            #expect(featureStore.workflowRegistryMessage == "Condition label cannot be empty.")
            #expect(featureStore.selectedWorkflowDefinition?.conditionFields.first?.definitionID == originalDefinitionID)
        }
    }

    @Test("feature store uses injected workflow id allocator instead of hardcoded ids")
    func addWorkflowUsesInjectedAllocator() async throws {
        let fileURL = try makeRegistryFileURL(prefix: "allocator")
        let store = WorkflowRegistryStore(registryFileURL: fileURL)
        let persistence = LocalPersistenceStub(
            pendingImports: [],
            archivedRecords: [],
            projects: [],
            interactionSnapshot: SpinLabInteractionSnapshot()
        )
        let repository = LibraryRepository(persistence: persistence)
        let allocator = FixedWorkflowIDAllocator(id: "CUSTOM_ID")

        let featureStore = await MainActor.run {
            WorkbenchFeatureStore(
                libraryRepository: repository,
                workflowRegistryStore: store,
                workflowIDAllocator: allocator
            )
        }

        await MainActor.run {
            featureStore.addWorkflow()
            #expect(featureStore.workflowDefinitions.contains(where: { $0.id == "CUSTOM_ID" }))
            #expect(featureStore.selectedWorkflowID == "CUSTOM_ID")
        }
    }

    @Test("workflow route tracks renamed workflow id")
    func workflowRouteTracksRenamedWorkflowID() async throws {
        let fileURL = try makeRegistryFileURL(prefix: "route-rename")
        let store = WorkflowRegistryStore(registryFileURL: fileURL)
        let persistence = LocalPersistenceStub(
            pendingImports: [],
            archivedRecords: [],
            projects: [],
            interactionSnapshot: SpinLabInteractionSnapshot()
        )
        let repository = LibraryRepository(persistence: persistence)

        let featureStore = await MainActor.run {
            WorkbenchFeatureStore(
                libraryRepository: repository,
                workflowRegistryStore: store
            )
        }

        await MainActor.run {
            guard let originalID = featureStore.workflowDefinitions.first?.id else {
                Issue.record("Expected at least one workflow definition.")
                return
            }

            featureStore.selectWorkflow(originalID)
            featureStore.updateSelectedWorkflow(
                id: "MR_NEW",
                displayName: "MR New",
                parentID: nil
            )

            #expect(featureStore.selectedWorkflowID == "MR_NEW")
            switch featureStore.currentRoute {
            case .workflow(let id):
                #expect(id == "MR_NEW")
            case .registry:
                Issue.record("Expected workflow route after rename.")
            }
        }
    }

    @Test("match rule editor uses workflow id token and allows inline edits before commit")
    func matchRuleEditorDefaultsAndEdits() async throws {
        let fileURL = try makeRegistryFileURL(prefix: "match-rule-editor")
        let store = WorkflowRegistryStore(registryFileURL: fileURL)
        let persistence = LocalPersistenceStub(
            pendingImports: [],
            archivedRecords: [],
            projects: [],
            interactionSnapshot: SpinLabInteractionSnapshot()
        )
        let repository = LibraryRepository(persistence: persistence)

        let featureStore = await MainActor.run {
            WorkbenchFeatureStore(
                libraryRepository: repository,
                workflowRegistryStore: store
            )
        }

        await MainActor.run {
            guard let selectedID = featureStore.selectedWorkflowID else {
                Issue.record("Expected selected workflow id.")
                return
            }

            featureStore.addMatchRuleToSelectedWorkflow()
            guard let rule = featureStore.selectedWorkflowMatchRules.last else {
                Issue.record("Expected a newly added match rule.")
                return
            }

            #expect(rule.matchValues == [selectedID.lowercased()])
            #expect(featureStore.matchRuleValuesCSV(rule.id) == selectedID.lowercased())

            featureStore.updateMatchRuleValuesCSV(rule.id, csv: "XY")
            #expect(featureStore.matchRuleValuesCSV(rule.id) == "XY")

            featureStore.updateMatchRuleValuesCSV(rule.id, csv: "   ")
            #expect(featureStore.matchRuleValuesCSV(rule.id).isEmpty)

            featureStore.commitMatchRuleValuesCSV(rule.id)
            #expect(featureStore.workflowRegistryMessage == "Match values cannot be empty in match rules.")
        }
    }

    @Test("removing selected workflow falls back to registry route")
    func removingSelectedWorkflowFallsBackToRegistryRoute() async throws {
        let fileURL = try makeRegistryFileURL(prefix: "route-remove")
        let store = WorkflowRegistryStore(registryFileURL: fileURL)
        let persistence = LocalPersistenceStub(
            pendingImports: [],
            archivedRecords: [],
            projects: [],
            interactionSnapshot: SpinLabInteractionSnapshot()
        )
        let repository = LibraryRepository(persistence: persistence)

        let featureStore = await MainActor.run {
            WorkbenchFeatureStore(
                libraryRepository: repository,
                workflowRegistryStore: store
            )
        }

        await MainActor.run {
            guard featureStore.workflowDefinitions.count >= 2 else {
                Issue.record("Expected seeded registry to include at least two workflows.")
                return
            }
            guard let removableID = featureStore.workflowDefinitions.last?.id else {
                Issue.record("Expected removable workflow id.")
                return
            }

            featureStore.selectWorkflow(removableID)
            featureStore.removeSelectedWorkflow()

            #expect(featureStore.workflowDefinitions.contains(where: { $0.id == removableID }) == false)
            switch featureStore.currentRoute {
            case .registry:
                #expect(Bool(true))
            case .workflow:
                Issue.record("Expected route to fall back to registry after removing selected workflow.")
            }
        }
    }

    @Test("navigating to workbench root resets workbench route to registry")
    @MainActor
    func appStateNavigateWorkbenchRootResetsRoute() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-v240-route-appstate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let persistence = LocalPersistenceStub(
            pendingImports: [],
            archivedRecords: [],
            projects: [],
            interactionSnapshot: SpinLabInteractionSnapshot()
        )
        let environment = AppEnvironment(
            persistence: persistence,
            managedStorage: SpinLabManagedStorage(rootURL: root.appendingPathComponent("storage", isDirectory: true)),
            sampleRegistry: SnapshotSampleRegistryIndex(snapshot: .empty()),
            registrySubstrateRules: RegistrySubstrateRuleBook(),
            routingCapabilities: .live,
            ruleRuntime: DefaultRuleRuntimeCapability(),
            dataActor: V240MockDataActor()
        )
        let appState = SpinLabAppState(environment: environment)
        guard let workflowID = appState.workbench.workflowDefinitions.first?.id else {
            Issue.record("Expected seeded workflow definitions.")
            return
        }

        appState.navigate(to: AppRoutePath.workbenchWorkflow(id: workflowID))
        switch appState.workbench.currentRoute {
        case .workflow(let id):
            #expect(id == workflowID)
        case .registry:
            Issue.record("Expected workflow route after navigating to workflow path.")
        }

        appState.navigate(to: AppRoutePath.workbench)
        switch appState.workbench.currentRoute {
        case .registry:
            #expect(Bool(true))
        case .workflow:
            Issue.record("Expected registry route after navigating to workbench root.")
        }
    }

    private func makeRegistryFileURL(prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-v240-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
            .appendingPathComponent("SpinLab", isDirectory: true)
            .appendingPathComponent("workflow_registry.json")
    }
}

private struct FixedWorkflowIDAllocator: WorkflowIDAllocating {
    let id: String

    func nextID(existingIDs: [String]) -> String {
        id
    }
}

private actor V240MockDataActor: SpinLabDataActing {
    func loadRegistrySnapshot(from xlsxURL: URL, previewRowCount: Int) async throws -> SampleRegistrySnapshot {
        SampleRegistrySnapshot.empty(sourceFilePath: xlsxURL.path)
    }

    func parseLibraryPreview(registryPath: String, settings: LibrarySettings) async throws -> LibraryPreviewParseSnapshot {
        LibraryPreviewParseSnapshot(
            index: LibraryIndex(
                createdAt: .now,
                updatedAt: .now,
                registryInternalPath: registryPath,
                registrySourcePath: settings.registrySourcePath,
                metadataColumnOrder: [],
                batches: [],
                samples: []
            ),
            warnings: []
        )
    }

    func searchWorkflowMeasurements(libraryRootPath: String, query: WorkflowSearchQuery, workflowDefinitions: [WorkflowDefinition]) async throws -> [WorkflowMeasurementSearchHit] {
        []
    }

    func lookupSampleNumericDisplay(libraryRootPath: String, sampleKey: String) async throws -> [String: String] {
        [:]
    }
}
