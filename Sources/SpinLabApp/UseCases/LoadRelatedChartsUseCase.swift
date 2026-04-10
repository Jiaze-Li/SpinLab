import Foundation

/// Loads all persisted chart manifests for the given samples and groups them
/// by canonical inputFiles key. This enables lookup of "which other charts
/// share the exact same set of source files as the current tab?"
///
/// Stateless UseCase — no stored properties, no side effects beyond reads.
struct LoadRelatedChartsUseCase {

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Returns charts grouped by canonical inputFiles key.
    /// Key: `InputFilesCanonicalKey.make(from:)` of the manifest's `inputFiles`.
    /// Value: matching `WorkbenchResultReference` list, sorted by `generatedAt` descending.
    func execute(
        sampleKeys: [String],
        libraryRootURL: URL
    ) -> [String: [WorkbenchResultReference]] {
        let pathResolver = LibraryPathResolver(libraryRootURL: libraryRootURL)
        let loadResults = LoadWorkbenchResultsUseCase(pathResolver: pathResolver)

        // Collect all references across samples (deduplicate by chartIdentityKey)
        var seen = Set<String>()
        var allRefs: [WorkbenchResultReference] = []
        for sk in sampleKeys {
            guard let index = loadResults.execute(sampleKey: sk) else { continue }
            for ref in index.references where seen.insert(ref.chartIdentityKey).inserted {
                allRefs.append(ref)
            }
        }

        // Load each manifest, extract inputFiles, group by canonical key
        var grouped: [String: [WorkbenchResultReference]] = [:]
        for ref in allRefs {
            guard let manifestURL = try? pathResolver.absoluteURL(for: ref.manifestPath),
                  let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? Self.decoder.decode(WorkbenchRunManifest.self, from: data) else {
                continue
            }
            let key = InputFilesCanonicalKey.make(from: manifest.inputFiles)
            grouped[key, default: []].append(ref)
        }

        // Sort each group by tab rank (ascending), then generatedAt (ascending) — same as Library
        let rankMap = ThreeOmegaWorkbenchTab.stableKeyRank
        let fallbackRank = rankMap.count
        for key in grouped.keys {
            grouped[key]?.sort { a, b in
                let rankA = a.resolvedTabKey.flatMap { rankMap[$0] } ?? fallbackRank
                let rankB = b.resolvedTabKey.flatMap { rankMap[$0] } ?? fallbackRank
                if rankA != rankB { return rankA < rankB }
                return a.generatedAt < b.generatedAt
            }
        }

        return grouped
    }
}
