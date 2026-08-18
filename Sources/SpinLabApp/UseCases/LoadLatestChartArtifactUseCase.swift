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
        let layout = LibraryArtifactLayout(pathResolver: pathResolver)
        let indexURL: URL
        do {
            indexURL = try layout.resultsIndexURL(sampleKey: sampleKey)
        } catch {
            fputs("[SpinLab] [LoadLatestChartArtifact] resolver failed for \(sampleKey): \(error)\n", stderr)
            return nil
        }

        let index: WorkbenchResultsIndex
        do {
            let data = try Data(contentsOf: indexURL)
            index = try Self.decoder.decode(WorkbenchResultsIndex.self, from: data)
        } catch let nsErr as NSError where nsErr.domain == NSCocoaErrorDomain && nsErr.code == NSFileReadNoSuchFileError {
            return nil
        } catch {
            fputs("[SpinLab] [LoadLatestChartArtifact] index corrupt at \(indexURL.path): \(error)\n", stderr)
            return nil
        }
        guard !index.references.isEmpty,
              let latest = index.references.max(by: { $0.generatedAt < $1.generatedAt }) else {
            return nil
        }

        let imageURL: URL
        let manifestURL: URL
        do {
            imageURL = try pathResolver.absoluteURL(for: latest.chartImagePath)
            manifestURL = try pathResolver.absoluteURL(for: latest.manifestPath)
        } catch {
            fputs("[SpinLab] [LoadLatestChartArtifact] path resolve failed: \(error)\n", stderr)
            return nil
        }

        let imageData: Data
        let manifestData: Data
        do {
            imageData = try Data(contentsOf: imageURL)
            manifestData = try Data(contentsOf: manifestURL)
        } catch let nsErr as NSError where nsErr.domain == NSCocoaErrorDomain && nsErr.code == NSFileReadNoSuchFileError {
            return nil
        } catch {
            fputs("[SpinLab] [LoadLatestChartArtifact] artifact read failed at \(imageURL.path): \(error)\n", stderr)
            return nil
        }

        do {
            let manifest = try Self.decoder.decode(WorkbenchRunManifest.self, from: manifestData)
            return LoadedChartArtifact(
                imageData: imageData,
                manifest: manifest,
                manifestPath: latest.manifestPath
            )
        } catch {
            fputs("[SpinLab] [LoadLatestChartArtifact] manifest decode failed: \(error)\n", stderr)
            return nil
        }
    }
}
