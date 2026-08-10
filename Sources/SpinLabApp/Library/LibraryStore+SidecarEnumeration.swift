import Foundation

extension LibraryStore {
    func scanAppliedMeasurements(in sampleDirectory: URL) -> [AppliedMeasurement] {
        let measurementsURL = sampleDirectory.appending(path: "measurements", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: measurementsURL.path),
              let enumerator = fileManager.enumerator(
                at: measurementsURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let reader = LibrarySidecarReader()
        var results: [AppliedMeasurement] = []
        results.reserveCapacity(16)

        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasSuffix(".spinlab.json") else { continue }
            let sidecar: SpinLabFileSidecar
            switch reader.loadSidecar(at: url) {
            case .success(let loaded):
                sidecar = loaded
            case .failure(let error):
                logger.warning(.library, "Skipping unreadable or corrupt sidecar",
                                metadata: ["path": url.path, "reason": String(describing: error)])
                continue
            }

            let normalizedSourceFileName = URL(fileURLWithPath: sidecar.sourceFilePath).lastPathComponent
            let sourceFileName: String
            if normalizedSourceFileName.isEmpty {
                sourceFileName = url.lastPathComponent.replacingOccurrences(of: ".spinlab.json", with: "")
            } else {
                sourceFileName = normalizedSourceFileName
            }
            let resolvedWorkflow = sidecar.resolvedWorkflow
            // For sidecars written before workflowDisplayName was added, fall back to the resolved id.
            let displayName = sidecar.workflowDisplayName.isEmpty
                ? resolvedWorkflow
                : sidecar.workflowDisplayName
            results.append(
                AppliedMeasurement(
                    id: url.path,
                    workflow: resolvedWorkflow,
                    workflowDisplayName: displayName,
                    conditions: sidecar.effectiveConditions,
                    appliedAt: sidecar.appliedAt,
                    sourceFileName: sourceFileName
                )
            )
        }

        return results.sorted { $0.appliedAt > $1.appliedAt }
    }

    func sidecarSignatures(in sampleDirectory: URL) -> [String] {
        let measurementsURL = sampleDirectory.appending(path: "measurements", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: measurementsURL.path),
              let enumerator = fileManager.enumerator(
                at: measurementsURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var signatures: [String] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasSuffix(".spinlab.json") else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modifiedAt = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let fileSize = values?.fileSize ?? 0
            signatures.append("\(url.path)|\(modifiedAt)|\(fileSize)")
        }

        return signatures.sorted()
    }

    func enumerateAllSidecarURLs(rootURL: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasSuffix(".spinlab.json"),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            urls.append(url)
        }
        return urls
    }
}
