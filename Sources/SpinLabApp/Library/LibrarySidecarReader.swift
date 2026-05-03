import Foundation

protocol LibrarySidecarReaderCapability {
    func loadSidecar(atPath path: String) -> SpinLabFileSidecar?
    func loadSidecar(at url: URL) -> SpinLabFileSidecar?
}

struct LibrarySidecarReader: LibrarySidecarReaderCapability {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func loadSidecar(atPath path: String) -> SpinLabFileSidecar? {
        loadSidecar(at: URL(fileURLWithPath: path))
    }

    func loadSidecar(at url: URL) -> SpinLabFileSidecar? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(SpinLabFileSidecar.self, from: data)
    }
}
