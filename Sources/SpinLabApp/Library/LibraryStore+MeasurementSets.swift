import Foundation

extension LibraryStore {
    // MARK: - Measurement Sets

    static let measurementSetsFileName = "measurement_sets.json"

    func loadMeasurementSets(for sample: LibrarySample, rootURL: URL) -> [MeasurementSet] {
        let sampleDir = sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        let fileURL = sampleDir.appending(path: Self.measurementSetsFileName)
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            logger.error(.library, "Failed to read measurement sets", metadata: [
                "path": fileURL.path,
                "reason": error.localizedDescription
            ])
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([MeasurementSet].self, from: data)
        } catch {
            logger.error(.library, "Failed to decode measurement sets", metadata: [
                "path": fileURL.path,
                "reason": error.localizedDescription
            ])
            return []
        }
    }

    func saveMeasurementSets(_ sets: [MeasurementSet], for sample: LibrarySample, rootURL: URL) throws {
        let sampleDir = sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        let fileURL = sampleDir.appending(path: Self.measurementSetsFileName)
        if sets.isEmpty {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(sets)
        try data.write(to: fileURL, options: .atomic)
    }
}
