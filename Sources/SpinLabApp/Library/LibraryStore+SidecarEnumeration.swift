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

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var results: [AppliedMeasurement] = []
        results.reserveCapacity(16)

        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasSuffix(".spinlab.json") else { continue }
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                logger.warning(.library, "Failed to read sidecar", metadata: [
                    "path": url.path,
                    "reason": error.localizedDescription
                ])
                continue
            }
            let sidecar: SpinLabFileSidecar
            do {
                sidecar = try decoder.decode(SpinLabFileSidecar.self, from: data)
            } catch {
                logger.warning(.library, "Failed to decode sidecar", metadata: [
                    "path": url.path,
                    "reason": error.localizedDescription
                ])
                continue
            }

            let normalizedSourceFileName = URL(fileURLWithPath: sidecar.sourceFilePath).lastPathComponent
            let sourceFileName: String
            if normalizedSourceFileName.isEmpty {
                sourceFileName = url.lastPathComponent.replacingOccurrences(of: ".spinlab.json", with: "")
            } else {
                sourceFileName = normalizedSourceFileName
            }
            // For sidecars written before workflowDisplayName was added, fall back to id.
            let displayName = sidecar.workflowDisplayName.isEmpty
                ? sidecar.workflow
                : sidecar.workflowDisplayName
            results.append(
                AppliedMeasurement(
                    id: url.path,
                    workflow: sidecar.workflow,
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

    func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
