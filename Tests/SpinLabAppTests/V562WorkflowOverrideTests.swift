import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.6.2 Workflow Override")
struct V562WorkflowOverrideTests {

    @Test("workflow with zero sets still exposes fallback and New Set")
    func workflowWithZeroSetsStillExposesFallbackItem() {
        let items = LibraryMeasurementsDoneSection.workflowOverrideMenuItems(
            for: "IV",
            measurementSets: []
        )
        #expect(items.count == 2)
        #expect(items.first?.title == "Uncategorized")
        #expect(items.first?.kind == .fallback)
        #expect(items.last?.title == "New Set\u{2026}")
        #expect(items.last?.kind == .newSet)
    }

    @Test("workflow submenu keeps fallback, existing set titles, and New Set at end")
    func workflowSubmenuKeepsFallbackAndExistingSets() {
        let items = LibraryMeasurementsDoneSection.workflowOverrideMenuItems(
            for: "3w",
            measurementSets: [
                MeasurementSet(
                    id: "set-a",
                    name: "Set A",
                    workflow: "3w",
                    memberFileNames: [],
                    createdAt: .init(timeIntervalSince1970: 1)
                ),
                MeasurementSet(
                    id: "set-b",
                    name: "Set B",
                    workflow: "3w",
                    memberFileNames: [],
                    createdAt: .init(timeIntervalSince1970: 2)
                )
            ]
        )
        #expect(items.map(\.title) == ["Uncategorized", "Set A", "Set B", "New Set\u{2026}"])
        #expect(items.first?.kind == .fallback)
        let middle = Array(items.dropFirst().dropLast())
        #expect(middle.allSatisfy { $0.kind == .existingSet })
        #expect(items.last?.kind == .newSet)
    }

    @Test("Measurements Done sorts angle sets by semantic angle order")
    func measurementsDoneSortsAngleSetsBySemanticAngleOrder() {
        let sets: [MeasurementSet] = [
            MeasurementSet(
                id: "set-0",
                name: "0deg",
                workflow: "3w",
                memberFileNames: [],
                createdAt: .init(timeIntervalSince1970: 1)
            ),
            MeasurementSet(
                id: "set-30",
                name: "30deg",
                workflow: "3w",
                memberFileNames: [],
                createdAt: .init(timeIntervalSince1970: 2)
            ),
            MeasurementSet(
                id: "set-90",
                name: "90deg",
                workflow: "3w",
                memberFileNames: [],
                createdAt: .init(timeIntervalSince1970: 3)
            ),
            MeasurementSet(
                id: "set-120",
                name: "120deg",
                workflow: "3w",
                memberFileNames: [],
                createdAt: .init(timeIntervalSince1970: 4)
            ),
            MeasurementSet(
                id: "set-180",
                name: "180deg",
                workflow: "3w",
                memberFileNames: [],
                createdAt: .init(timeIntervalSince1970: 5)
            ),
            MeasurementSet(
                id: "set-60",
                name: "60deg",
                workflow: "3w",
                memberFileNames: [],
                createdAt: .init(timeIntervalSince1970: 6)
            ),
            MeasurementSet(
                id: "set-150",
                name: "150deg",
                workflow: "3w",
                memberFileNames: [],
                createdAt: .init(timeIntervalSince1970: 7)
            )
        ]

        let ordered = LibraryMeasurementsDoneSection.sortedSetsForWorkflow("3w", measurementSets: sets)
        #expect(ordered.map(\.name) == ["0deg", "30deg", "60deg", "90deg", "120deg", "150deg", "180deg"])
    }

    @Test("Add to 3ω context menu sorts angle sets by semantic angle order")
    func addToThreeOmegaContextMenuSortsAngleSetsBySemanticAngleOrder() {
        let items = LibraryMeasurementsDoneSection.workflowOverrideMenuItems(
            for: "3w",
            measurementSets: [
                MeasurementSet(
                    id: "set-0",
                    name: "0deg",
                    workflow: "3w",
                    memberFileNames: [],
                    createdAt: .init(timeIntervalSince1970: 1)
                ),
                MeasurementSet(
                    id: "set-30",
                    name: "30deg",
                    workflow: "3w",
                    memberFileNames: [],
                    createdAt: .init(timeIntervalSince1970: 2)
                ),
                MeasurementSet(
                    id: "set-90",
                    name: "90deg",
                    workflow: "3w",
                    memberFileNames: [],
                    createdAt: .init(timeIntervalSince1970: 3)
                ),
                MeasurementSet(
                    id: "set-120",
                    name: "120deg",
                    workflow: "3w",
                    memberFileNames: [],
                    createdAt: .init(timeIntervalSince1970: 4)
                ),
                MeasurementSet(
                    id: "set-180",
                    name: "180deg",
                    workflow: "3w",
                    memberFileNames: [],
                    createdAt: .init(timeIntervalSince1970: 5)
                ),
                MeasurementSet(
                    id: "set-60",
                    name: "60deg",
                    workflow: "3w",
                    memberFileNames: [],
                    createdAt: .init(timeIntervalSince1970: 6)
                ),
                MeasurementSet(
                    id: "set-150",
                    name: "150deg",
                    workflow: "3w",
                    memberFileNames: [],
                    createdAt: .init(timeIntervalSince1970: 7)
                )
            ]
        )

        #expect(items.map(\.title) == [
            "Uncategorized",
            "0deg",
            "30deg",
            "60deg",
            "90deg",
            "120deg",
            "150deg",
            "180deg",
            "New Set\u{2026}"
        ])
    }

    @Test("Add to 3ω existing 60deg set updates workflow and set membership")
    func addToThreeOmegaExistingSetUpdatesWorkflowAndMembership() throws {
        try assertExistingSetSelectionUpdatesWorkflowAndMembership(
            sampleID: "PN15",
            workflowID: "3w",
            workflowFolder: "3w",
            fileName: "pn15_3w.dat",
            setName: "60deg",
            workflowOverride: "3w"
        )
    }

    @Test("Add to IV existing set updates workflow and set membership")
    func addToIVExistingSetUpdatesWorkflowAndMembership() throws {
        try assertExistingSetSelectionUpdatesWorkflowAndMembership(
            sampleID: "PN16",
            workflowID: "IV",
            workflowFolder: "IV",
            fileName: "pn16_iv.dat",
            setName: "IV Set A",
            workflowOverride: "IV"
        )
    }

    @Test("Add to 3ω Uncategorized updates workflow only")
    func addToThreeOmegaUncategorizedUpdatesWorkflowOnly() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN17"])
        defer { fixture.cleanup() }

        _ = try fixture.writeMeasurement(
            sampleID: "PN17",
            workflowFolder: "3w",
            fileName: "pn17_3w.dat",
            sidecar: Fixture.makeSidecar(
                workflow: "3w",
                autoDetectedWorkflow: "3w",
                workflowDisplayName: "3ω",
                conditions: ["temperature": "80K"],
                channels: ["ch1"],
                sourceFilePath: "/tmp/pn17_3w.dat",
                appliedAt: .init(timeIntervalSince1970: 1_700_000_600)
            )
        )
        try fixture.saveMeasurementSets(
            sampleID: "PN17",
            sets: [
                MeasurementSet(
                    id: "set-empty",
                    name: "60deg",
                    workflow: "3w",
                    memberFileNames: [],
                    createdAt: .init(timeIntervalSince1970: 1)
                )
            ]
        )

        let sample = try fixture.sample(withID: "PN17")
        let measurement = try #require(fixture.libraryStore.loadAppliedMeasurements(for: sample, rootURL: fixture.libraryRootURL).first)
        let items = LibraryMeasurementsDoneSection.workflowOverrideMenuItems(
            for: "3w",
            measurementSets: fixture.libraryStore.loadMeasurementSets(for: sample, rootURL: fixture.libraryRootURL)
        )
        let fallback = try #require(items.first(where: { $0.kind == .fallback }))

        let sidecarService = LibrarySidecarService(libraryStore: fixture.libraryStore)
        LibraryMeasurementsDoneSection.handleWorkflowOverrideMenuSelection(
            fallback,
            measurement: measurement,
            workflowID: "3w",
            onSetWorkflowOverride: { measurement, workflowID in
                _ = sidecarService.saveWorkflowOverride(
                    sidecarPath: measurement.id,
                    workflowOverride: workflowID
                )
            }
        )

        let updatedSidecar = try #require(sidecarService.loadSidecar(atPath: measurement.id))
        #expect(updatedSidecar.workflowOverride == "3w")
        #expect(updatedSidecar.workflowSource == .manual)

        let sets = fixture.libraryStore.loadMeasurementSets(for: sample, rootURL: fixture.libraryRootURL)
        #expect(sets.count == 1)
        #expect(sets[0].memberFileNames.isEmpty)
    }

    @Test("New Set creates workflow-scoped set and writes workflow override")
    func newSetCreatesWorkflowScopedSetAndWritesWorkflowOverride() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN18"])
        defer { fixture.cleanup() }

        _ = try fixture.writeMeasurement(
            sampleID: "PN18",
            workflowFolder: "IV",
            fileName: "pn18_iv.dat",
            sidecar: Fixture.makeSidecar(
                workflow: "IV",
                autoDetectedWorkflow: "IV",
                workflowDisplayName: "IV",
                conditions: ["temperature": "293K"],
                channels: ["ch1"],
                sourceFilePath: "/tmp/pn18_iv.dat",
                appliedAt: .init(timeIntervalSince1970: 1_700_000_700)
            )
        )

        let sample = try fixture.sample(withID: "PN18")
        let measurement = try #require(fixture.libraryStore.loadAppliedMeasurements(for: sample, rootURL: fixture.libraryRootURL).first)
        let sidecarService = LibrarySidecarService(libraryStore: fixture.libraryStore)

        LibraryMeasurementsDoneSection.handleNewSetCreation(
            name: "IV Set New",
            workflowID: "IV",
            measurement: measurement,
            onCreateSet: { name, workflow, initialMember in
                var sets = fixture.libraryStore.loadMeasurementSets(for: sample, rootURL: fixture.libraryRootURL)
                sets.append(
                    MeasurementSet(
                        id: "iv-new-set",
                        name: name,
                        workflow: workflow,
                        memberFileNames: initialMember.map { [$0] } ?? [],
                        createdAt: .init(timeIntervalSince1970: 2)
                    )
                )
                try? fixture.libraryStore.saveMeasurementSets(sets, for: sample, rootURL: fixture.libraryRootURL)
            },
            onSetWorkflowOverride: { measurement, workflowID in
                _ = sidecarService.saveWorkflowOverride(
                    sidecarPath: measurement.id,
                    workflowOverride: workflowID
                )
            }
        )

        let updatedSidecar = try #require(sidecarService.loadSidecar(atPath: measurement.id))
        #expect(updatedSidecar.workflowOverride == "IV")
        #expect(updatedSidecar.workflowSource == .manual)

        let sets = fixture.libraryStore.loadMeasurementSets(for: sample, rootURL: fixture.libraryRootURL)
        #expect(sets.count == 1)
        #expect(sets[0].workflow == "IV")
        #expect(sets[0].memberFileNames == ["pn18_iv.dat"])
    }

    @Test("New Set... is present in every workflow submenu after workflow menu refactor")
    func newSetIsPresentInEveryWorkflowSubmenu() {
        let workflowIDs = ["3w", "IV", "XY"]
        for wfID in workflowIDs {
            let items = LibraryMeasurementsDoneSection.workflowOverrideMenuItems(
                for: wfID,
                measurementSets: []
            )
            #expect(items.contains { $0.title == "New Set\u{2026}" && $0.kind == .newSet },
                    "Expected New Set... in submenu for \(wfID)")
        }
    }

    private func assertExistingSetSelectionUpdatesWorkflowAndMembership(
        sampleID: String,
        workflowID: String,
        workflowFolder: String,
        fileName: String,
        setName: String,
        workflowOverride: String
    ) throws {
        let fixture = try Fixture.make(sampleIDs: [sampleID])
        defer { fixture.cleanup() }

        _ = try fixture.writeMeasurement(
            sampleID: sampleID,
            workflowFolder: workflowFolder,
            fileName: fileName,
            sidecar: Fixture.makeSidecar(
                workflow: workflowID,
                autoDetectedWorkflow: workflowID,
                workflowDisplayName: workflowID == "3w" ? "3ω" : workflowID,
                conditions: ["temperature": "80K"],
                channels: ["ch1"],
                sourceFilePath: "/tmp/\(fileName)",
                appliedAt: .init(timeIntervalSince1970: 1_700_000_500)
            )
        )
        try fixture.saveMeasurementSets(
            sampleID: sampleID,
            sets: [
                MeasurementSet(
                    id: "\(workflowID)-set-a",
                    name: setName,
                    workflow: workflowID,
                    memberFileNames: [],
                    createdAt: .init(timeIntervalSince1970: 1)
                )
            ]
        )

        let sample = try fixture.sample(withID: sampleID)
        let measurements = fixture.libraryStore.loadAppliedMeasurements(for: sample, rootURL: fixture.libraryRootURL)
        #expect(measurements.count == 1)
        let measurement = try #require(measurements.first)

        let items = LibraryMeasurementsDoneSection.workflowOverrideMenuItems(
            for: workflowID,
            measurementSets: fixture.libraryStore.loadMeasurementSets(for: sample, rootURL: fixture.libraryRootURL)
        )
        let existingSet = try #require(items.first(where: { $0.kind == .existingSet }))
        #expect(existingSet.title == setName)

        let sidecarService = LibrarySidecarService(libraryStore: fixture.libraryStore)
        LibraryMeasurementsDoneSection.handleWorkflowOverrideMenuSelection(
            existingSet,
            measurement: measurement,
            workflowID: workflowID,
            onSetWorkflowOverride: { measurement, workflowID in
                _ = sidecarService.saveWorkflowOverride(
                    sidecarPath: measurement.id,
                    workflowOverride: workflowID
                )
            },
            onAddToSet: { setID, fileName in
                var sets = fixture.libraryStore.loadMeasurementSets(for: sample, rootURL: fixture.libraryRootURL)
                guard let index = sets.firstIndex(where: { $0.id == setID }) else {
                    Issue.record("Expected set \(setID) to exist.")
                    return
                }
                if !sets[index].memberFileNames.contains(fileName) {
                    sets[index].memberFileNames.append(fileName)
                }
                try? fixture.libraryStore.saveMeasurementSets(sets, for: sample, rootURL: fixture.libraryRootURL)
            }
        )

        let updatedSidecar = try #require(sidecarService.loadSidecar(atPath: measurement.id))
        #expect(updatedSidecar.workflowOverride == workflowOverride)
        #expect(updatedSidecar.workflowSource == .manual)
        let updatedSets = fixture.libraryStore.loadMeasurementSets(for: sample, rootURL: fixture.libraryRootURL)
        #expect(updatedSets.count == 1)
        #expect(updatedSets[0].memberFileNames == [fileName])
    }

    @Test("normal 3w file auto resolves to 3ω")
    func normalThreeWFileAutoResolvesToThreeOmega() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN10"])
        defer { fixture.cleanup() }

        _ = try fixture.writeMeasurement(
            sampleID: "PN10",
            workflowFolder: "3w",
            fileName: "pn10_3w.dat",
            sidecar: Fixture.makeSidecar(
                workflow: "3w",
                autoDetectedWorkflow: "3w",
                workflowDisplayName: "3ω",
                conditions: ["temperature": "80K"],
                channels: ["ch1"],
                sourceFilePath: "/tmp/pn10_3w.dat",
                appliedAt: .init(timeIntervalSince1970: 1_700_000_000)
            )
        )

        try fixture.assertResolvedWorkflow(
            sampleID: "PN10",
            expectedWorkflowID: "3w",
            expectedDisplayName: "3ω",
            expectedConditionSummary: "temperature=80K"
        )
    }

    @Test("normal 3w file manually Add to IV resolves to IV")
    func normalThreeWFileManualOverrideToIVResolvesToIV() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN11"])
        defer { fixture.cleanup() }

        _ = try fixture.writeMeasurement(
            sampleID: "PN11",
            workflowFolder: "3w",
            fileName: "pn11_3w.dat",
            sidecar: Fixture.makeSidecar(
                workflow: "3w",
                autoDetectedWorkflow: "3w",
                workflowOverride: "IV",
                workflowSource: .manual,
                workflowDisplayName: "3ω",
                conditions: ["temperature": "80K"],
                channels: ["ch1"],
                sourceFilePath: "/tmp/pn11_3w.dat",
                appliedAt: .init(timeIntervalSince1970: 1_700_000_100)
            )
        )

        try fixture.assertResolvedWorkflow(
            sampleID: "PN11",
            expectedWorkflowID: "IV",
            expectedDisplayName: "IV",
            expectedConditionSummary: "temperature=80K"
        )
    }

    @Test("IV_3w file auto resolves to IV with harmonic=3w")
    func ivThreeWFileAutoResolvesToIVWithHarmonic() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN12"])
        defer { fixture.cleanup() }

        _ = try fixture.writeMeasurement(
            sampleID: "PN12",
            workflowFolder: "IV",
            fileName: "pn12_iv_3w.dat",
            sidecar: Fixture.makeSidecar(
                workflow: "IV",
                autoDetectedWorkflow: "IV",
                workflowDisplayName: "IV",
                conditions: ["harmonic": "3w", "temperature": "293K"],
                channels: ["ch1"],
                sourceFilePath: "/tmp/pn12_iv_3w.dat",
                appliedAt: .init(timeIntervalSince1970: 1_700_000_200)
            )
        )

        try fixture.assertResolvedWorkflow(
            sampleID: "PN12",
            expectedWorkflowID: "IV",
            expectedDisplayName: "IV",
            expectedConditionSummary: "harmonic=3w, temperature=293K"
        )
    }

    @Test("IV_3w file manually Add to 3ω resolves to 3ω")
    func ivThreeWFileManualOverrideToThreeOmegaResolvesToThreeOmega() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN13"])
        defer { fixture.cleanup() }

        _ = try fixture.writeMeasurement(
            sampleID: "PN13",
            workflowFolder: "IV",
            fileName: "pn13_iv_3w.dat",
            sidecar: Fixture.makeSidecar(
                workflow: "IV",
                autoDetectedWorkflow: "IV",
                workflowOverride: "3w",
                workflowSource: .manual,
                workflowDisplayName: "IV",
                conditions: ["harmonic": "3w", "temperature": "293K"],
                channels: ["ch1"],
                sourceFilePath: "/tmp/pn13_iv_3w.dat",
                appliedAt: .init(timeIntervalSince1970: 1_700_000_300)
            )
        )

        try fixture.assertResolvedWorkflow(
            sampleID: "PN13",
            expectedWorkflowID: "3w",
            expectedDisplayName: "3ω",
            expectedConditionSummary: "harmonic=3w, temperature=293K"
        )
    }

    @Test("Revert to Auto returns to filename auto inference")
    func revertToAutoReturnsToFilenameInference() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN14"])
        defer { fixture.cleanup() }

        let sidecarURL = try fixture.writeMeasurement(
            sampleID: "PN14",
            workflowFolder: "IV",
            fileName: "pn14_auto_3w.dat",
            sidecar: Fixture.makeSidecar(
                workflow: "IV",
                autoDetectedWorkflow: "3w",
                workflowOverride: "IV",
                workflowSource: .manual,
                workflowDisplayName: "IV",
                conditions: ["temperature": "80K"],
                channels: ["ch1"],
                sourceFilePath: "/tmp/pn14_auto_3w.dat",
                appliedAt: .init(timeIntervalSince1970: 1_700_000_400)
            )
        )

        let service = LibrarySidecarService(libraryStore: fixture.libraryStore)
        #expect(service.clearWorkflowOverride(sidecarPath: sidecarURL.path))

        try fixture.assertResolvedWorkflow(
            sampleID: "PN14",
            expectedWorkflowID: "3w",
            expectedDisplayName: "3ω",
            expectedConditionSummary: "temperature=80K"
        )
    }
}

private struct Fixture {
    let rootURL: URL
    let libraryRootURL: URL
    let libraryStore: LibraryStore
    let samplesByID: [String: LibrarySample]
    let defaultBatch: LibraryBatch

    static func make(sampleIDs: [String]) throws -> Fixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-v562-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let libraryRootURL = rootURL.appendingPathComponent("library", isDirectory: true)
        let libraryStore = LibraryStore()
        libraryStore.ensureRoot(at: libraryRootURL)

        let batch = LibraryBatch(
            id: "PN",
            displayName: "PN",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: [],
            updatedAt: .now
        )

        var samplesByID: [String: LibrarySample] = [:]
        for sampleID in sampleIDs {
            let sample = LibrarySample(
                id: sampleID,
                displayName: sampleID,
                batchId: batch.id,
                substrateRaw: "STO(111)",
                substrateDisplay: "STO(111)",
                substrateTokens: ["STO", "111"],
                substrateTags: ["STO", "111"],
                metadata: [:],
                numericTags: [:],
                numericDisplay: [:],
                updatedAt: .now
            )
            samplesByID[sampleID] = sample
            try libraryStore.createDrawer(for: sample, batch: batch, rootURL: libraryRootURL)
        }

        return Fixture(
            rootURL: rootURL,
            libraryRootURL: libraryRootURL,
            libraryStore: libraryStore,
            samplesByID: samplesByID,
            defaultBatch: batch
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func sample(withID sampleID: String) throws -> LibrarySample {
        guard let sample = samplesByID[sampleID] else {
            throw NSError(domain: "Fixture", code: 2)
        }
        return sample
    }

    static func makeSidecar(
        workflow: String,
        autoDetectedWorkflow: String,
        workflowOverride: String? = nil,
        workflowSource: WorkflowSource? = nil,
        workflowDisplayName: String,
        conditions: [String: String],
        channels: [String],
        sourceFilePath: String,
        appliedAt: Date
    ) -> SpinLabFileSidecar {
        let conditionFields = conditions.mapValues { value in
            SourcedValue(value: value, source: "test:fixture")
        }
        return SpinLabFileSidecar(
            workflow: workflow,
            autoDetectedWorkflow: autoDetectedWorkflow,
            workflowOverride: workflowOverride,
            workflowSource: workflowSource,
            workflowDisplayName: workflowDisplayName,
            channels: channels,
            sourceFilePath: sourceFilePath,
            appliedAt: appliedAt,
            ruleSnapshot: SidecarRuleSnapshot(
                ruleSetVersion: 0,
                ruleSetFingerprint: "test:fixture",
                appliedAt: appliedAt,
                fields: SidecarRuleFields(sampleID: nil, conditions: conditionFields, substrateTags: [])
            )
        )
    }

    func writeMeasurement(
        sampleID: String,
        workflowFolder: String,
        fileName: String,
        sidecar: SpinLabFileSidecar
    ) throws -> URL {
        guard let sample = samplesByID[sampleID] else {
            throw NSError(domain: "Fixture", code: 1)
        }
        let drawerRoot = libraryStore.drawerRootURL(for: sample, rootURL: libraryRootURL)
        let folderURL = drawerRoot
            .appending(path: "measurements", directoryHint: .isDirectory)
            .appendingPathComponent(workflowFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let measurementURL = folderURL.appendingPathComponent(fileName, isDirectory: false)
        try Data("x,y\n1,2\n".utf8).write(to: measurementURL)

        let sidecarURL = folderURL.appendingPathComponent(fileName + ".spinlab.json", isDirectory: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(sidecar).write(to: sidecarURL)
        return sidecarURL
    }

    func saveMeasurementSets(sampleID: String, sets: [MeasurementSet]) throws {
        guard let sample = samplesByID[sampleID] else {
            throw NSError(domain: "Fixture", code: 3)
        }
        try libraryStore.saveMeasurementSets(sets, for: sample, rootURL: libraryRootURL)
    }

    func assertResolvedWorkflow(
        sampleID: String,
        expectedWorkflowID: String,
        expectedDisplayName: String,
        expectedConditionSummary: String
    ) throws {
        guard let sample = samplesByID[sampleID] else {
            Issue.record("Expected fixture sample \(sampleID).")
            return
        }

        let measurements = libraryStore.loadAppliedMeasurements(for: sample, rootURL: libraryRootURL)
        #expect(measurements.count == 1)
        #expect(measurements[0].workflow == expectedWorkflowID)

        let useCase = SearchWorkflowMeasurementsUseCase()
        let hits = try useCase.execute(
            query: WorkflowSearchQuery(rawText: ""),
            libraryRootURL: libraryRootURL,
            workflowDefinitions: [
                WorkflowDefinition(id: "3w", displayName: "3ω", conditionFields: []),
                WorkflowDefinition(id: "IV", displayName: "IV", conditionFields: []),
                WorkflowDefinition(id: "XY", displayName: "XY Rotation", conditionFields: [])
            ]
        )
        guard let hit = hits.first else {
            Issue.record("Expected a search hit for \(sampleID).")
            return
        }

        #expect(hit.workflowID == expectedWorkflowID)
        #expect(hit.workflowDisplayName == expectedDisplayName)
        #expect(hit.conditionSummary == expectedConditionSummary)
    }
}
