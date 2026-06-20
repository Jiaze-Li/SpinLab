import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.1.3 Inbox Closed Loop")
struct V213InboxClosedLoopTests {
    @Test("editing routing draft without save does not change route plan")
    func unsavedDraftDoesNotMutateRoutePlan() {
        let pending = makePending(idSeed: "A", fileName: "RT_1mA_ch2_PN41_STO001_AMR.dat", fileSampleKey: "PN41")
        let persistence = MockPersistenceForV213(pendingImports: [pending])
        let appState = makeAppState(persistence: persistence)

        let before = appState.pendingRoutePlan(for: pending)
        var draft = appState.routingDraft(for: pending)
        draft.fileSampleKey = "PN40"
        let after = appState.pendingRoutePlan(for: pending)

        #expect(before.targets.first?.sampleId == "PN41||STO|001")
        #expect(after.targets.first?.sampleId == "PN41||STO|001")
    }

    @Test("save routing draft updates route plan and status")
    func saveRoutingDraftUpdatesRoute() {
        let pending = makePending(idSeed: "A", fileName: "RT_1mA_ch2_PN41_STO001_AMR.dat", fileSampleKey: "PN41")
        let persistence = MockPersistenceForV213(pendingImports: [pending])
        let appState = makeAppState(persistence: persistence)
        installExistingDrawers(
            sampleDisplayNames: ["PN40 - STO(001)"],
            into: appState
        )

        var draft = appState.routingDraft(for: pending)
        draft.fileSampleKey = "PN40"
        appState.saveRoutingDraft(draft, for: pending.id)

        let plan = appState.pendingRoutePlan(for: pending)
        #expect(appState.pendingRouteStatus(for: pending) == .libraryMatched)
        #expect(plan.targets.first?.sampleId == "PN40||STO|001")
    }

    @Test("manual sample preview updates drawer match before save")
    func manualSamplePreviewUpdatesDrawerMatchBeforeSave() {
        let pending = SpinLabDomain.PendingImport(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            workflow: .amrPhe,
            fileName: "RT_preview_manual_sample.dat",
            sourceFilePath: "/tmp/RT_preview_manual_sample.dat",
            originalFilePath: nil,
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints(
                fileSampleKey: nil,
                channelHints: [],
                substrateTags: []
            )
        )
        let persistence = MockPersistenceForV213(pendingImports: [pending])
        let appState = makeAppState(persistence: persistence)
        installExistingDrawers(
            sampleDisplayNames: ["PN40 - STO(001)"],
            into: appState
        )

        var draft = appState.routingDraft(for: pending)
        draft.fileSampleKey = "PN40 - STO(001)"

        let preview = appState.pendingRoutingPreviewSnapshot(
            for: pending,
            routingDraft: draft,
            sampleName: "PN40 - STO(001)"
        )

        #expect(pending.parsedHints.fileSampleKey == nil)
        #expect(appState.pendingRouteStatus(for: pending) == .reviewRequired)
        #expect(preview.verdict == .libraryMatched)
        #expect(preview.scopes.first?.sampleId == "PN40||STO|001")
        #expect(preview.scopes.first?.matchedDrawer == "PN40||STO|001")

        appState.saveRoutingDraft(draft, for: pending.id)
        #expect(appState.pendingRouteStatus(for: pending) == .libraryMatched)
        #expect(appState.routingDraft(for: pending).fileSampleKey == "PN40 - STO(001)")
    }

    @Test("switching pending items keeps routing state isolated")
    func pendingRoutingIsolation() {
        let pendingA = makePending(idSeed: "A", fileName: "RT_1mA_ch2_PN41_STO001_AMR.dat", fileSampleKey: "PN41")
        let pendingB = makePending(idSeed: "B", fileName: "RT_1mA_ch2_PN48_STO111_AMR.dat", fileSampleKey: "PN48")
        let persistence = MockPersistenceForV213(pendingImports: [pendingA, pendingB])
        let appState = makeAppState(persistence: persistence)

        var draftA = appState.routingDraft(for: pendingA)
        draftA.fileSampleKey = "PN40"
        appState.saveRoutingDraft(draftA, for: pendingA.id)

        let planA = appState.pendingRoutePlan(for: pendingA)
        let planB = appState.pendingRoutePlan(for: pendingB)
        let draftB = appState.routingDraft(for: pendingB)

        #expect(planA.targets.first?.sampleId == "PN40||STO|001")
        let sampleIdB = planB.targets.first?.sampleId ?? ""
        #expect(sampleIdB.contains("PN48"))
        #expect(sampleIdB.contains("STO|111"))
        #expect(draftB.fileSampleKey == "PN48")
    }

    @Test("clear imports only clears pending queue")
    func clearImportsOnlyClearsPending() {
        let pending = makePending(idSeed: "A", fileName: "RT_1mA_ch2_PN41_STO001_AMR.dat", fileSampleKey: "PN41")
        let persistence = MockPersistenceForV213(pendingImports: [pending])
        persistence.archivedRecordsValue = [makeArchivedRecord()]
        let appState = makeAppState(persistence: persistence)

        appState.clearPendingImports()

        #expect(appState.inbox.pendingImports.isEmpty)
        #expect(appState.workbench.archivedRecords.count == 1)
    }

    @Test("batch recompute route refreshes parsed hints")
    func batchRecomputeRouteRefreshesHints() {
        let stale = SpinLabDomain.PendingImport(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            workflow: .amrPhe,
            fileName: "MR_10K_1mA_ch1_PN38_ch2_PN40_STO111_ch3_PN40_HF_STO111_wafer.dat",
            sourceFilePath: "/tmp/MR_10K_1mA_ch1_PN38_ch2_PN40_STO111_ch3_PN40_HF_STO111_wafer.dat",
            originalFilePath: "/Users/jack/Library/CloudStorage/OneDrive-NationalUniversityofSingapore/Desktop/Y1 MRAM/experiment results/sample data/sample from PN/MR/MR_10K_1mA_ch1_PN38_ch2_PN40_STO111_ch3_PN40_HF_STO111_wafer.dat",
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints(
                fileSampleKey: "PN41",
                channelHints: [SpinLabDomain.ParsedChannelHint(channel: "ch2", sampleID: nil, tags: ["STO001"])],
                substrateTags: ["STO001"]
            )
        )
        let persistence = MockPersistenceForV213(pendingImports: [stale])
        let appState = makeAppState(persistence: persistence)
        // SpinLabAppState.init resets RuleLoader — configure bundled rules after init
        let bundledDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SpinLabApp/config")
        RuleLoader.configure(bookPaths: RulesConfigPaths(configDirectoryURL: bundledDir), internalPaths: AppInternalPaths())
        defer { RuleLoader.configure(bookPaths: nil, internalPaths: AppInternalPaths()) }

        appState.recomputeAllPendingParsedHints()
        guard let updated = appState.inbox.pendingImports.first(where: { $0.id == stale.id }) else {
            Issue.record("Updated pending import not found")
            return
        }
        let plan = appState.pendingRoutePlan(for: updated)

        #expect(updated.parsedHints.fileSampleKey != "PN41")
        let targetSampleKeys = Set(plan.targets.map(\.sampleId))
        #expect(targetSampleKeys.contains { $0.contains("PN38") || $0.contains("PN40") })
    }

    @Test("file-level queue is library matched when mapped drawer exists")
    func fileLevelQueueMatchesByDrawerMapping() {
        let pending = SpinLabDomain.PendingImport(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            workflow: .amrPhe,
            fileName: "RT_PN41_STO001.dat",
            sourceFilePath: "/tmp/RT_PN41_STO001.dat",
            originalFilePath: nil,
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints(
                fileSampleKey: "PN41 - STO(001)",
                channelHints: [],
                substrateTags: []
            )
        )
        let persistence = MockPersistenceForV213(pendingImports: [pending])
        let appState = makeAppState(persistence: persistence)
        installExistingDrawers(
            sampleDisplayNames: ["PN41 - STO(001)"],
            into: appState
        )

        #expect(appState.pendingDrawerMatchByID[pending.id] == true)
    }

    @Test("channel-level queue requires all reported channels to map drawers")
    func channelLevelQueueRequiresAllChannelsMapped() {
        let pending = SpinLabDomain.PendingImport(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
            workflow: .amrPhe,
            fileName: "RT_ch1_PN41_STO001_ch2_PN42_STO001.dat",
            sourceFilePath: "/tmp/RT_ch1_PN41_STO001_ch2_PN42_STO001.dat",
            originalFilePath: nil,
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints(
                fileSampleKey: nil,
                channelHints: [
                    SpinLabDomain.ParsedChannelHint(channel: "ch1", sampleID: "PN41 - STO(001)", tags: []),
                    SpinLabDomain.ParsedChannelHint(channel: "ch2", sampleID: "PN42 - STO(001)", tags: [])
                ],
                substrateTags: []
            )
        )

        let partialPersistence = MockPersistenceForV213(pendingImports: [pending])
        let partialState = makeAppState(persistence: partialPersistence)
        installExistingDrawers(
            sampleDisplayNames: ["PN41 - STO(001)"],
            into: partialState
        )
        #expect(partialState.pendingDrawerMatchByID[pending.id] == false)

        let fullPersistence = MockPersistenceForV213(pendingImports: [pending])
        let fullState = makeAppState(persistence: fullPersistence)
        installExistingDrawers(
            sampleDisplayNames: ["PN41 - STO(001)", "PN42 - STO(001)"],
            into: fullState
        )
        #expect(fullState.pendingDrawerMatchByID[pending.id] == true)
    }

    @Test("manual channel override preview updates drawer match before save")
    func manualChannelOverridePreviewUpdatesDrawerMatchBeforeSave() {
        let pending = SpinLabDomain.PendingImport(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
            workflow: .amrPhe,
            fileName: "RT_ch2_manual_override.dat",
            sourceFilePath: "/tmp/RT_ch2_manual_override.dat",
            originalFilePath: nil,
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints(
                fileSampleKey: nil,
                channelHints: [
                    SpinLabDomain.ParsedChannelHint(channel: "ch2", sampleID: nil, tags: ["STO001"])
                ],
                substrateTags: ["STO001"]
            )
        )
        let persistence = MockPersistenceForV213(pendingImports: [pending])
        let appState = makeAppState(persistence: persistence)
        installExistingDrawers(
            sampleDisplayNames: ["PN14 - STO(001)"],
            into: appState
        )

        var draft = appState.routingDraft(for: pending)
        draft.channelSampleKeyOverrides["ch2"] = "PN14 - STO(001)"

        let preview = appState.pendingRoutingPreviewSnapshot(
            for: pending,
            routingDraft: draft,
            sampleName: ""
        )

        #expect(preview.scopes.first?.scope == "ch2")
        #expect(preview.scopes.first?.sampleId == "PN14||STO|001")
        #expect(preview.scopes.first?.matchedDrawer == "PN14||STO|001")
        #expect(appState.pendingRouteStatus(for: pending) == .reviewRequired)
    }

    @Test("single-sample multi-channel routing collapses to file-level and remains library matched")
    func singleSampleMultiChannelCollapsesToFileLevelMapping() {
        let pending = SpinLabDomain.PendingImport(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000016")!,
            workflow: .amrPhe,
            fileName: "PN32_origin_STO_wafer_ch2_AMR_ch3_PHE.dat",
            sourceFilePath: "/tmp/PN32_origin_STO_wafer_ch2_AMR_ch3_PHE.dat",
            originalFilePath: nil,
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints(
                fileSampleKey: "PN32 - o STO",
                channelHints: [
                    SpinLabDomain.ParsedChannelHint(channel: "ch2", sampleID: nil, tags: [], testInfoTags: ["AMR"]),
                    SpinLabDomain.ParsedChannelHint(channel: "ch3", sampleID: nil, tags: [], testInfoTags: ["PHE"])
                ],
                substrateTags: ["o", "STO"]
            )
        )
        let persistence = MockPersistenceForV213(pendingImports: [pending])
        let appState = makeAppState(persistence: persistence)
        installExistingDrawers(
            sampleDisplayNames: ["PN32 - o STO(111)"],
            into: appState
        )

        let snapshot = appState.pendingRoutingSnapshot(for: pending)
        #expect(snapshot.mode == .fileLevel)
        #expect(snapshot.verdict == .libraryMatched)
        #expect(snapshot.scopes.count == 1)
        #expect(snapshot.scopes.first?.scope == "file")
        #expect(snapshot.scopes.first?.matchedDrawer == "PN32|o|STO|111")
        #expect(snapshot.unresolvedScopes.isEmpty)
        #expect(appState.pendingRoutePlan(for: pending).unresolvedChannels.isEmpty)
        #expect(appState.pendingDrawerMatchByID[pending.id] == true)
    }

    @Test("channel sample token drives verdict when it does not match a drawer")
    func channelSampleTokenDrivesVerdict() {
        let pending = SpinLabDomain.PendingImport(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000019")!,
            workflow: .amrPhe,
            fileName: "PN32_conflict_ch2_AMR.dat",
            sourceFilePath: "/tmp/PN32_conflict_ch2_AMR.dat",
            originalFilePath: nil,
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints(
                sampleName: "PN32 - b STO(111)",
                fileSampleKey: "PN32 - b STO(111)",
                channelHints: [
                    SpinLabDomain.ParsedChannelHint(channel: "ch2", sampleID: nil, tags: ["o", "STO111"])
                ],
                substrateTags: ["b", "STO111"]
            )
        )
        let persistence = MockPersistenceForV213(pendingImports: [pending])
        let appState = makeAppState(persistence: persistence)
        // SpinLabAppState.init resets RuleLoader — configure bundled rules after init
        let bundledDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SpinLabApp/config")
        RuleLoader.configure(bookPaths: RulesConfigPaths(configDirectoryURL: bundledDir), internalPaths: AppInternalPaths())
        defer { RuleLoader.configure(bookPaths: nil, internalPaths: AppInternalPaths()) }

        installExistingDrawers(
            sampleDisplayNames: ["PN32 - b STO(111)"],
            into: appState
        )

        let plan = appState.pendingRoutePlan(for: pending)
        #expect(plan.conflicts.isEmpty)
        #expect(plan.unresolvedChannels.isEmpty)

        let snapshot = appState.pendingRoutingSnapshot(for: pending)
        #expect(snapshot.scopes.first?.sampleId == "PN32|b+o|STO|111")
        #expect(snapshot.scopes.first?.matchedDrawer == nil)
        #expect(snapshot.verdict == .reviewRequired)
        #expect(appState.pendingDrawerMatchByID[pending.id] == false)
    }

    @Test("channel-level queue follows displayed sample mapping when route fallback is generic")
    func channelLevelQueueUsesDisplayedSampleFallback() {
        let pending = SpinLabDomain.PendingImport(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000017")!,
            workflow: .amrPhe,
            fileName: "PN32_baked_STO_wafer_ch2_AMR_ch3_PHE_8T_1mA_170K.dat",
            sourceFilePath: "/tmp/PN32_baked_STO_wafer_ch2_AMR_ch3_PHE_8T_1mA_170K.dat",
            originalFilePath: nil,
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints(
                sampleName: "PN32 - b STO(111)",
                fileSampleKey: "PN32",
                sampleIDs: ["PN32"],
                channelHints: [
                    SpinLabDomain.ParsedChannelHint(channel: "ch2", sampleID: nil, tags: [], testInfoTags: ["AMR"]),
                    SpinLabDomain.ParsedChannelHint(channel: "ch3", sampleID: nil, tags: [], testInfoTags: ["PHE"])
                ],
                substrateTags: ["b", "STO"]
            )
        )
        let persistence = MockPersistenceForV213(pendingImports: [pending])
        let appState = makeAppState(persistence: persistence)
        // SpinLabAppState.init resets RuleLoader — configure bundled rules after init
        let bundledDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SpinLabApp/config")
        RuleLoader.configure(bookPaths: RulesConfigPaths(configDirectoryURL: bundledDir), internalPaths: AppInternalPaths())
        defer { RuleLoader.configure(bookPaths: nil, internalPaths: AppInternalPaths()) }

        installExistingDrawers(
            sampleDisplayNames: [
                "PN32 - o STO(111)",
                "PN32 - b STO(111)"
            ],
            into: appState
        )

        let displayDraft = appState.pendingDisplayDraft(for: pending)
        #expect(displayDraft.sampleName == "PN32 - b STO(111)")
        #expect(appState.pendingDrawerMatchByID[pending.id] == true)
    }

    @Test("drawer matching uses per-drawer substrate tokens and ignores shared substrate raw text")
    func drawerMatchingUsesPerDrawerSubstrateTokens() {
        let pending = SpinLabDomain.PendingImport(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000018")!,
            workflow: .amrPhe,
            fileName: "PN32_baked_STO_wafer_ch2_AMR_ch3_PHE.dat",
            sourceFilePath: "/tmp/PN32_baked_STO_wafer_ch2_AMR_ch3_PHE.dat",
            originalFilePath: nil,
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints(
                sampleName: "PN32 b STO",
                fileSampleKey: "PN32",
                sampleIDs: ["PN32"],
                channelHints: [
                    SpinLabDomain.ParsedChannelHint(channel: "ch2", sampleID: nil, tags: [], testInfoTags: ["AMR"]),
                    SpinLabDomain.ParsedChannelHint(channel: "ch3", sampleID: nil, tags: [], testInfoTags: ["PHE"])
                ],
                substrateTags: ["b", "STO"]
            )
        )
        let persistence = MockPersistenceForV213(pendingImports: [pending])
        let appState = makeAppState(persistence: persistence)

        guard var hf = makeLibrarySample(displayName: "PN32 - HF STO(111)"),
              var b = makeLibrarySample(displayName: "PN32 - b STO(111)"),
              var origin = makeLibrarySample(displayName: "PN32 - o STO(111)") else {
            Issue.record("Failed to construct PN32 drawer samples")
            return
        }
        let sharedRaw = "HF STO (111), original STO (111), b STO (111)"
        hf.substrateRaw = sharedRaw
        b.substrateRaw = sharedRaw
        origin.substrateRaw = sharedRaw
        hf.substrateTokens = ["HF", "STO", "111"]
        b.substrateTokens = ["b", "STO", "111"]
        origin.substrateTokens = ["o", "STO", "111"]

        installExistingLibrarySamples([hf, b, origin], into: appState)
        let matched = appState.matchedExistingLibraryDrawer(sampleInput: "PN32 b STO")

        #expect(matched == "PN32|b|STO|111")
    }

    private func makeAppState(persistence: MockPersistenceForV213) -> SpinLabAppState {
        SpinLabAppState(
            persistence: persistence,
            libraryArchiveScan: LibraryArchiveScanService(
                rootURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("spinlab-v213-\(UUID().uuidString)", isDirectory: true)
            )
        )
    }

    private func installExistingDrawers(sampleDisplayNames: [String], into appState: SpinLabAppState) {
        let samples = sampleDisplayNames.compactMap(makeLibrarySample(displayName:))
        installExistingLibrarySamples(samples, into: appState)
    }

    private func installExistingLibrarySamples(_ samples: [LibrarySample], into appState: SpinLabAppState) {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-v213-library-\(UUID().uuidString)", isDirectory: true)
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let batchesRoot = rootURL.appendingPathComponent("batches", isDirectory: true)
        try? fileManager.createDirectory(at: batchesRoot, withIntermediateDirectories: true)

        var samplesByBatch: [String: [LibrarySample]] = [:]
        for sample in samples {
            samplesByBatch[sample.batchId, default: []].append(sample)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        for (batchID, batchSamples) in samplesByBatch {
            let batchURL = batchesRoot.appendingPathComponent(batchID, isDirectory: true)
            let samplesURL = batchURL.appendingPathComponent("samples", isDirectory: true)
            try? fileManager.createDirectory(at: samplesURL, withIntermediateDirectories: true)

            let batch = LibraryBatch(
                id: batchID,
                displayName: batchID,
                sheetName: "TestSheet",
                metadata: [:],
                numericTags: [:],
                numericDisplay: [:],
                sampleKeys: batchSamples.map(\.id).sorted(),
                updatedAt: .now
            )
            if let batchData = try? encoder.encode(batch) {
                try? batchData.write(to: batchURL.appendingPathComponent("batch.json"), options: .atomic)
            }

            for sample in batchSamples {
                let sampleURL = samplesURL.appendingPathComponent(sample.id, isDirectory: true)
                try? fileManager.createDirectory(at: sampleURL, withIntermediateDirectories: true)
                if let sampleData = try? encoder.encode(sample) {
                    try? sampleData.write(to: sampleURL.appendingPathComponent("sample.json"), options: .atomic)
                }
            }
        }

        appState.library.librarySettings.rootPath = rootURL.path
        appState.loadExistingDrawers()
        appState.refreshPendingDrawerMatches()
    }

    private func makeLibrarySample(displayName: String) -> LibrarySample? {
        let parts = displayName.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return nil
        }

        let batchID = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let substrate = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !batchID.isEmpty, !substrate.isEmpty else {
            return nil
        }

        let upper = substrate.uppercased()
        let tokens = upper
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let treatment: String = {
            if upper.contains("HF") { return "HF" }
            if upper.contains("BAKE") || tokens.contains("B") { return "b" }
            if upper.contains("ORIGIN") || upper.contains(" O ") || upper.hasPrefix("O ") { return "o" }
            return ""
        }()
        let material: String = {
            if upper.contains("STO") { return "STO" }
            if upper.contains("NGO") { return "NGO" }
            if upper.contains("MAO") { return "MAO" }
            return "UNKNOWN"
        }()
        let orientation: String = {
            if upper.contains("111") { return "111" }
            if upper.contains("110") { return "110" }
            if upper.contains("001") || upper.contains("100") { return "001" }
            return "UNKNOWN"
        }()

        let sampleKey = "\(batchID)|\(treatment)|\(material)|\(orientation)"
        let substrateTokens = [treatment, material, orientation].filter { !$0.isEmpty && $0 != "UNKNOWN" }

        return LibrarySample(
            id: sampleKey,
            displayName: displayName,
            batchId: batchID,
            substrateRaw: substrate,
            substrateDisplay: substrate,
            substrateTokens: substrateTokens,
            substrateTags: [],
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            updatedAt: .now
        )
    }

    private func makePending(idSeed: String, fileName: String, fileSampleKey: String) -> SpinLabDomain.PendingImport {
        let id: UUID
        switch idSeed {
        case "A":
            id = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        case "B":
            id = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        default:
            id = UUID()
        }

        let substrateTag = fileName.lowercased().contains("sto111") ? "STO111" : "STO001"
        return SpinLabDomain.PendingImport(
            id: id,
            workflow: .amrPhe,
            fileName: fileName,
            sourceFilePath: "/tmp/\(fileName)",
            originalFilePath: nil,
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints(
                fileSampleKey: fileSampleKey,
                channelHints: [SpinLabDomain.ParsedChannelHint(channel: "ch2", sampleID: nil, tags: [substrateTag])],
                substrateTags: [substrateTag]
            )
        )
    }

    private func makeArchivedRecord() -> SpinLabDomain.ArchivedRecord {
        let sample = SpinLabDomain.Sample(name: "PN40 - STO(001)")
        let measurement = SpinLabDomain.Measurement(
            name: "RT",
            sampleID: sample.id,
            sourceFilePath: "/tmp/RT.dat"
        )
        let dataset = SpinLabDomain.Dataset(
            measurementID: measurement.id,
            sourceFilePath: "/tmp/RT.dat",
            columns: ["x", "y"],
            series: []
        )
        return SpinLabDomain.ArchivedRecord(
            workflow: .amrPhe,
            project: nil,
            batch: SpinLabDomain.Batch(name: "PN40"),
            sample: sample,
            device: nil,
            measurement: measurement,
            dataset: dataset,
            latestResult: nil
        )
    }
}

private final class MockPersistenceForV213: SpinLabPersistence {
    var pendingImportsValue: [SpinLabDomain.PendingImport]
    var archivedRecordsValue: [SpinLabDomain.ArchivedRecord] = []
    var projectsValue: [SpinLabDomain.Project] = []
    var interactionSnapshotValue: SpinLabInteractionSnapshot = SpinLabInteractionSnapshot()

    init(pendingImports: [SpinLabDomain.PendingImport]) {
        self.pendingImportsValue = pendingImports
    }

    func loadPendingImports() -> [SpinLabDomain.PendingImport] { pendingImportsValue }
    func savePendingImports(_ imports: [SpinLabDomain.PendingImport]) { pendingImportsValue = imports }
    func loadArchivedRecords() -> [SpinLabDomain.ArchivedRecord] { archivedRecordsValue }
    func saveArchivedRecords(_ records: [SpinLabDomain.ArchivedRecord]) { archivedRecordsValue = records }
    func loadProjects() -> [SpinLabDomain.Project] { projectsValue }
    func saveProjects(_ projects: [SpinLabDomain.Project]) { projectsValue = projects }
    func loadInteractionSnapshot() -> SpinLabInteractionSnapshot { interactionSnapshotValue }
    func saveInteractionSnapshot(_ snapshot: SpinLabInteractionSnapshot) { interactionSnapshotValue = snapshot }
}
