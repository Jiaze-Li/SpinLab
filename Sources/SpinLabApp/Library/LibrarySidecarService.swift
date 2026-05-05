import Foundation

struct LibrarySidecarService {
    let libraryStore: LibraryStore
    private let fileManager = FileManager.default
    private let logger: any AppLogging
    let reader: any LibrarySidecarReaderCapability
    let writer: any LibrarySidecarWriterCapability

    init(
        libraryStore: LibraryStore,
        logger: any AppLogging = AppLogger.shared,
        reader: (any LibrarySidecarReaderCapability)? = nil,
        writer: (any LibrarySidecarWriterCapability)? = nil
    ) {
        self.libraryStore = libraryStore
        self.logger = logger
        self.reader = reader ?? LibrarySidecarReader()
        self.writer = writer ?? LibrarySidecarWriter()
    }

    // MARK: - Recompute all

    func recomputeAllMeasurementSidecars(rootURL: URL) -> LibraryStore.BackfillSidecarsResult {
        libraryStore.ensureRoot(at: rootURL)
        let batchDirectories = libraryStore.discoverBatchDirectories(rootURL: rootURL)
        var scannedSampleCount = 0
        var scannedMeasurementFileCount = 0
        var createdSidecarCount = 0
        var updatedSidecarCount = 0
        var skippedExistingSidecarCount = 0
        var failedSidecarCount = 0

        let loadResult = SpinLabRuleProvider.shared.loadResult()

        for batchDirectory in batchDirectories {
            let batchJSONURL = batchDirectory.appending(path: "batch.json")
            guard let batch = libraryStore.decodeBatch(from: batchJSONURL) else { continue }

            for sample in libraryStore.decodeSamples(from: batchDirectory) {
                scannedSampleCount += 1
                let sampleDirectory = libraryStore.sampleDirectoryURL(rootURL, batchID: batch.id, sampleKey: sample.id)
                let result = recomputeSidecars(in: sampleDirectory, loadResult: loadResult)
                scannedMeasurementFileCount += result.scannedMeasurementFileCount
                createdSidecarCount += result.createdSidecarCount
                updatedSidecarCount += result.updatedSidecarCount
                skippedExistingSidecarCount += result.skippedExistingSidecarCount
                failedSidecarCount += result.failedSidecarCount
            }
        }

        return LibraryStore.BackfillSidecarsResult(
            scannedSampleCount: scannedSampleCount,
            scannedMeasurementFileCount: scannedMeasurementFileCount,
            createdSidecarCount: createdSidecarCount,
            updatedSidecarCount: updatedSidecarCount,
            skippedExistingSidecarCount: skippedExistingSidecarCount,
            failedSidecarCount: failedSidecarCount
        )
    }

    @available(*, deprecated, renamed: "recomputeAllMeasurementSidecars")
    func backfillMissingMeasurementSidecars(rootURL: URL) -> LibraryStore.BackfillSidecarsResult {
        recomputeAllMeasurementSidecars(rootURL: rootURL)
    }

    // MARK: - Dry-run diff

    func computeRecomputeDiff(rootURL: URL) -> [RecomputeDiffItem] {
        let loadResult = SpinLabRuleProvider.shared.loadResult()
        let parser = FilenameRuleParser(ruleSet: loadResult.ruleSet)
        var items: [RecomputeDiffItem] = []

        for sidecarURL in libraryStore.enumerateAllSidecarURLs(rootURL: rootURL) {
            guard let existing = reader.loadSidecar(at: sidecarURL) else { continue }
            items += buildDiffItemsForSidecar(
                sidecarURL: sidecarURL,
                existing: existing,
                loadResult: loadResult,
                parser: parser
            )
        }

        return items.sorted {
            if $0.sampleID != $1.sampleID { return $0.sampleID < $1.sampleID }
            if $0.workflow != $1.workflow { return $0.workflow < $1.workflow }
            if $0.sourceFileName != $1.sourceFileName { return $0.sourceFileName < $1.sourceFileName }
            return $0.fieldKey < $1.fieldKey
        }
    }

    // MARK: - Private helpers

    struct SidecarBackfillStats {
        var scannedMeasurementFileCount: Int = 0
        var createdSidecarCount: Int = 0
        var updatedSidecarCount: Int = 0
        var skippedExistingSidecarCount: Int = 0
        var failedSidecarCount: Int = 0
    }

    func recomputeSidecars(
        in sampleDirectory: URL,
        loadResult: RuleLoader.LoadResult
    ) -> SidecarBackfillStats {
        let measurementsURL = sampleDirectory.appending(path: "measurements", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: measurementsURL.path),
              let enumerator = fileManager.enumerator(
                at: measurementsURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return SidecarBackfillStats()
        }

        let parser = FilenameRuleParser(ruleSet: loadResult.ruleSet)
        var stats = SidecarBackfillStats()
        var mutated = false

        for case let url as URL in enumerator {
            guard !url.lastPathComponent.hasSuffix(".spinlab.json") else { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }

            stats.scannedMeasurementFileCount += 1

            let hints = parser.parse(from: url)
            let snapshot = SidecarCompositionUseCase.buildRuleSnapshot(
                hints: hints,
                ruleSetFingerprint: loadResult.ruleSetFingerprint,
                ruleSetVersion: loadResult.ruleSetVersion,
                evaluatedAt: .now
            )

            let sidecarURL = url.deletingPathExtension().appendingPathExtension(url.pathExtension + ".spinlab.json")

            if fileManager.fileExists(atPath: sidecarURL.path) {
                guard let existing = reader.loadSidecar(at: sidecarURL) else {
                    stats.skippedExistingSidecarCount += 1
                    logger.error(.library, "Sidecar read or decode failed — skipping",
                                 metadata: ["sidecarPath": sidecarURL.path])
                    continue
                }

                let updated = SidecarCompositionUseCase.composeSidecarV2(
                    base: SidecarCompositionBase(
                        workflow: existing.workflow,
                        workflowDisplayName: existing.workflowDisplayName,
                        channels: existing.channels,
                        sourceFilePath: existing.sourceFilePath,
                        existingSidecar: existing
                    ),
                    snapshot: snapshot,
                    preserveUserOverrides: true,
                    now: .now
                )
                if writer.saveSidecar(updated, at: sidecarURL) {
                    stats.updatedSidecarCount += 1
                    mutated = true
                } else {
                    stats.failedSidecarCount += 1
                    logger.error(.library, "Failed to recompute sidecar",
                                 metadata: ["sidecarPath": sidecarURL.path])
                }
            } else {
                let workflow = inferredWorkflow(forMeasurementFile: url, measurementsRoot: measurementsURL)
                let sidecar = SidecarCompositionUseCase.composeSidecarV2(
                    base: SidecarCompositionBase(
                        workflow: workflow,
                        workflowDisplayName: workflow,
                        channels: [],
                        sourceFilePath: url.path,
                        existingSidecar: nil
                    ),
                    snapshot: snapshot,
                    preserveUserOverrides: false,
                    now: .now
                )
                if writer.saveSidecar(sidecar, at: sidecarURL) {
                    stats.createdSidecarCount += 1
                    mutated = true
                } else {
                    stats.failedSidecarCount += 1
                    logger.error(.library, "Failed to create sidecar",
                                 metadata: ["measurementPath": url.path, "sidecarPath": sidecarURL.path])
                }
            }
        }

        if mutated {
            libraryStore.invalidateNodeCache(at: sampleDirectory)
        }
        return stats
    }

    private func inferredWorkflow(forMeasurementFile fileURL: URL, measurementsRoot: URL) -> String {
        let components = fileURL.pathComponents
        guard let measurementsIndex = components.lastIndex(of: "measurements") else {
            return "General"
        }
        let workflowIndex = measurementsIndex + 1
        guard workflowIndex < components.count - 1 else {
            return "General"
        }
        return components[workflowIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? "General"
    }

    private func buildDiffItemsForSidecar(
        sidecarURL: URL,
        existing: SpinLabFileSidecar,
        loadResult: RuleLoader.LoadResult,
        parser: FilenameRuleParser
    ) -> [RecomputeDiffItem] {
        let sidecarName = sidecarURL.lastPathComponent
        let sourceName = sidecarName.replacingOccurrences(of: ".spinlab.json", with: "")
        let sourceURL = sidecarURL.deletingLastPathComponent().appending(path: sourceName)

        let hints = parser.parse(from: sourceURL)
        let newSnapshot = SidecarCompositionUseCase.buildRuleSnapshot(
            hints: hints,
            ruleSetFingerprint: loadResult.ruleSetFingerprint,
            ruleSetVersion: loadResult.ruleSetVersion,
            evaluatedAt: .now
        )

        let sampleIDValue = existing.effectiveSampleID ?? ""
        let sourceFileName = URL(fileURLWithPath: existing.sourceFilePath).lastPathComponent.nilIfEmpty ?? sourceName

        return buildDiffItems(
            sidecarPath: sidecarURL.path,
            sampleID: sampleIDValue,
            workflow: existing.workflow,
            sourceFileName: sourceFileName,
            existing: existing,
            newSnapshot: newSnapshot
        )
    }

    private func buildDiffItems(
        sidecarPath: String,
        sampleID: String,
        workflow: String,
        sourceFileName: String,
        existing: SpinLabFileSidecar,
        newSnapshot: SidecarRuleSnapshot
    ) -> [RecomputeDiffItem] {
        var items: [RecomputeDiffItem] = []

        if let item = diffSourcedValue(
            sidecarPath: sidecarPath, sampleID: sampleID, workflow: workflow,
            sourceFileName: sourceFileName, fieldKey: "sampleID",
            old: existing.ruleSnapshot.fields.sampleID,
            new: newSnapshot.fields.sampleID
        ) { items.append(item) }

        let allConditionKeys = Set(existing.ruleSnapshot.fields.conditions.keys)
            .union(newSnapshot.fields.conditions.keys)
            .union(existing.userOverrides.conditions.keys)

        for key in allConditionKeys.sorted() {
            let fieldKey = "conditions.\(key)"
            if let override = existing.userOverrides.conditions[key] {
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withFullDate, .withDashSeparatorInDate]
                let dateStr = fmt.string(from: override.at)
                items.append(RecomputeDiffItem(
                    id: "\(sidecarPath)|\(fieldKey)",
                    sidecarPath: sidecarPath,
                    sampleID: sampleID,
                    workflow: workflow,
                    sourceFileName: sourceFileName,
                    fieldKey: fieldKey,
                    oldValue: override.value,
                    newValue: override.value,
                    oldSource: "manual @ \(dateStr)",
                    newSource: "manual @ \(dateStr)",
                    status: .manualOverride
                ))
                continue
            }
            if let item = diffSourcedValue(
                sidecarPath: sidecarPath, sampleID: sampleID, workflow: workflow,
                sourceFileName: sourceFileName, fieldKey: fieldKey,
                old: existing.ruleSnapshot.fields.conditions[key],
                new: newSnapshot.fields.conditions[key]
            ) { items.append(item) }
        }

        let oldTags = existing.ruleSnapshot.fields.substrateTags
        let newTags = newSnapshot.fields.substrateTags
        for i in 0..<max(oldTags.count, newTags.count) {
            let old = i < oldTags.count ? oldTags[i] : nil
            let new = i < newTags.count ? newTags[i] : nil
            if let item = diffSourcedValue(
                sidecarPath: sidecarPath, sampleID: sampleID, workflow: workflow,
                sourceFileName: sourceFileName, fieldKey: "substrateTags[\(i)]",
                old: old, new: new
            ) { items.append(item) }
        }

        return items
    }

    private func diffSourcedValue(
        sidecarPath: String,
        sampleID: String,
        workflow: String,
        sourceFileName: String,
        fieldKey: String,
        old: SourcedValue?,
        new: SourcedValue?
    ) -> RecomputeDiffItem? {
        if old == nil && new == nil { return nil }

        let valUnchanged = old?.value == new?.value
        let srcUnchanged = old?.source == new?.source

        let status: RecomputeDiffStatus
        if valUnchanged && srcUnchanged {
            status = .noChange
        } else if old == nil {
            status = .added
        } else if new == nil {
            status = .ruleRemoved
        } else if old?.source.hasPrefix("rule:migration.v1") == true {
            status = .migration
        } else {
            status = .willUpdate
        }

        return RecomputeDiffItem(
            id: "\(sidecarPath)|\(fieldKey)",
            sidecarPath: sidecarPath,
            sampleID: sampleID,
            workflow: workflow,
            sourceFileName: sourceFileName,
            fieldKey: fieldKey,
            oldValue: old?.value,
            newValue: new?.value,
            oldSource: old?.source,
            newSource: new?.source,
            status: status
        )
    }

    // MARK: - Stale count

    func computeStaleCount(rootURL: URL, currentFingerprint: String) -> Int {
        let loadResult = SpinLabRuleProvider.shared.loadResult()
        let parser = FilenameRuleParser(ruleSet: loadResult.ruleSet)

        return libraryStore.enumerateAllSidecarURLs(rootURL: rootURL).reduce(into: 0) { count, url in
            guard let sidecar = reader.loadSidecar(at: url) else { return }
            if sidecar.ruleSnapshot.ruleSetFingerprint != currentFingerprint {
                let diffItems = buildDiffItemsForSidecar(
                    sidecarURL: url,
                    existing: sidecar,
                    loadResult: loadResult,
                    parser: parser
                )
                if diffItems.contains(where: { $0.status.isActionable }) {
                    count += 1
                }
            }
        }
    }

    // MARK: - Single sidecar load

    func loadSidecar(atPath path: String) -> SpinLabFileSidecar? {
        reader.loadSidecar(atPath: path)
    }

    // MARK: - Condition override write-back

    @discardableResult
    func saveConditionOverride(sidecarPath: String, conditionId: String, value: String) -> Bool {
        let url = URL(fileURLWithPath: sidecarPath)
        guard var sidecar = reader.loadSidecar(at: url) else { return false }
        if value == sidecar.ruleSnapshot.fields.conditions[conditionId]?.value {
            sidecar.userOverrides.conditions.removeValue(forKey: conditionId)
        } else {
            sidecar.userOverrides.conditions[conditionId] = ManualValueOverride(value: value, reason: "manual", at: Date())
        }
        return writer.saveSidecar(sidecar, at: url)
    }

    @discardableResult
    func removeConditionOverride(sidecarPath: String, conditionId: String) -> Bool {
        let url = URL(fileURLWithPath: sidecarPath)
        guard var sidecar = reader.loadSidecar(at: url) else { return false }
        guard sidecar.userOverrides.conditions[conditionId] != nil else { return true }
        sidecar.userOverrides.conditions.removeValue(forKey: conditionId)
        return writer.saveSidecar(sidecar, at: url)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
