import Foundation

struct LoadedChartArtifact: Sendable {
    var imageData: Data
    var manifest: WorkbenchRunManifest
    var manifestPath: String
}

struct LoadLatestChartArtifactUseCase {
    let pathResolver: LibraryPathResolver

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Returns the most recently generated artifact for the given sampleKey,
    /// or nil if no index exists, the index is unreadable, or the files are missing.
    func execute(sampleKey: String) -> LoadedChartArtifact? {
        let indexRelPath = "samples/\(sampleKey)/_spinlab/results_index.json"
        guard let indexURL = try? pathResolver.absoluteURL(for: indexRelPath),
              let indexData = try? Data(contentsOf: indexURL),
              let index = try? Self.decoder.decode(WorkbenchResultsIndex.self, from: indexData),
              !index.references.isEmpty else {
            return nil
        }

        // Most recent by generatedAt
        let latest = index.references.max(by: { $0.generatedAt < $1.generatedAt })!

        guard let imageURL = try? pathResolver.absoluteURL(for: latest.chartImagePath),
              let imageData = try? Data(contentsOf: imageURL),
              let manifestURL = try? pathResolver.absoluteURL(for: latest.manifestPath),
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? Self.decoder.decode(WorkbenchRunManifest.self, from: manifestData) else {
            return nil
        }

        return LoadedChartArtifact(
            imageData: imageData,
            manifest: manifest,
            manifestPath: latest.manifestPath
        )
    }
}
