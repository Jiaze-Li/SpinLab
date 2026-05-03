import Foundation

protocol LibrarySidecarWriterCapability {
    @discardableResult
    func saveSidecar(_ sidecar: SpinLabFileSidecar, at url: URL) -> Bool
}

struct LibrarySidecarWriter: LibrarySidecarWriterCapability {
    @discardableResult
    func saveSidecar(_ sidecar: SpinLabFileSidecar, at url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(sidecar) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
