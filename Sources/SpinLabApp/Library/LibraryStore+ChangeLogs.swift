import Foundation

extension LibraryStore {
    func sampleChangeLog(for sample: LibrarySample, rootURL: URL) -> [LibrarySampleChangeLogEntry] {
        let sampleURL = sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        let logURL = sampleChangeLogURL(sampleURL: sampleURL)
        guard fileManager.fileExists(atPath: logURL.path),
              let data = try? Data(contentsOf: logURL) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = (try? decoder.decode([LibrarySampleChangeLogEntry].self, from: data)) ?? []
        return entries.sorted { $0.changedAt > $1.changedAt }
    }

    @discardableResult
    func appendSampleChangeLogIfNeeded(
        previous: LibrarySample?,
        updated: LibrarySample,
        source: String,
        sampleURL: URL
    ) -> [LibrarySampleChangeLogItem] {
        guard let previous, previous != updated else {
            return []
        }
        let changes = sampleChangeItems(old: previous, new: updated)
        guard !changes.isEmpty else {
            return []
        }

        let logURL = sampleChangeLogURL(sampleURL: sampleURL)
        guard var entries = loadSampleChangeLogEntries(from: logURL) else { return changes }
        entries.append(
            LibrarySampleChangeLogEntry(
                id: UUID(),
                sampleId: updated.id,
                batchId: updated.batchId,
                changedAt: .now,
                source: source,
                changes: changes
            )
        )
        writeJSON(entries, to: logURL)
        return changes
    }

    func appendBatchEditLogIfNeeded(
        changes: [LibrarySampleChangeLogItem],
        updated: LibrarySample,
        source: String,
        rootURL: URL
    ) {
        guard !changes.isEmpty else {
            return
        }
        let batchURL = resolvedBatchDirectoryURL(rootURL, batchID: updated.batchId)
        let logURL = batchEditLogURL(batchURL: batchURL)
        guard var entries = loadSampleChangeLogEntries(from: logURL) else { return }
        entries.append(
            LibrarySampleChangeLogEntry(
                id: UUID(),
                sampleId: updated.id,
                batchId: updated.batchId,
                changedAt: .now,
                source: source,
                changes: changes
            )
        )
        writeJSON(entries, to: logURL)
    }

    func loadSampleChangeLogEntries(from url: URL) -> [LibrarySampleChangeLogEntry]? {
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logger.error(.library, "Failed to read change log — skipping write to prevent data loss", metadata: [
                "path": url.path,
                "reason": error.localizedDescription
            ])
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([LibrarySampleChangeLogEntry].self, from: data)
        } catch {
            logger.error(.library, "Failed to decode change log — skipping write to prevent data loss", metadata: [
                "path": url.path,
                "reason": error.localizedDescription
            ])
            return nil
        }
    }

    func sampleChangeLogURL(sampleURL: URL) -> URL {
        sampleURL.appending(path: "sample_change_log.json")
    }

    func batchEditLogURL(batchURL: URL) -> URL {
        batchURL.appending(path: "edit_log.json")
    }

    func sampleChangeItems(old: LibrarySample, new: LibrarySample) -> [LibrarySampleChangeLogItem] {
        var items: [LibrarySampleChangeLogItem] = []

        addChange("displayName", old: old.displayName, new: new.displayName, into: &items)
        addChange("substrateRaw", old: old.substrateRaw, new: new.substrateRaw, into: &items)
        addChange("substrateDisplay", old: old.substrateDisplay, new: new.substrateDisplay, into: &items)
        addChange("substrateTags", old: old.substrateTags.joined(separator: ", "), new: new.substrateTags.joined(separator: ", "), into: &items)
        addChange("substrateTokens", old: old.substrateTokens.joined(separator: ", "), new: new.substrateTokens.joined(separator: ", "), into: &items)

        let metadataKeys = Set(old.metadata.keys).union(new.metadata.keys).sorted()
        for key in metadataKeys {
            addChange("metadata.\(key)", old: old.metadata[key], new: new.metadata[key], into: &items)
        }

        let numericKeys = Set(old.numericDisplay.keys).union(new.numericDisplay.keys).sorted()
        for key in numericKeys {
            addChange("numeric.\(key)", old: old.numericDisplay[key], new: new.numericDisplay[key], into: &items)
        }

        return items
    }

    func addChange(
        _ key: String,
        old oldValue: String?,
        new newValue: String?,
        into items: inout [LibrarySampleChangeLogItem]
    ) {
        let normalizedOld = normalizedLogValue(oldValue)
        let normalizedNew = normalizedLogValue(newValue)
        guard normalizedOld != normalizedNew else {
            return
        }
        items.append(
            LibrarySampleChangeLogItem(
                key: key,
                oldValue: normalizedOld,
                newValue: normalizedNew
            )
        )
    }

    func normalizedLogValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
