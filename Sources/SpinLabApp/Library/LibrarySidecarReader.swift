import Foundation

/// Distinguishes why a sidecar failed to load, so callers can react differently
/// to a malformed file versus one written by an older/incompatible schema.
enum SidecarReadError: Error, Equatable, Sendable {
    /// The file exists but its JSON is malformed (truncated, invalid syntax, etc).
    case corrupted
    /// The JSON parsed but doesn't match `SpinLabFileSidecar`'s expected shape
    /// (missing key, wrong type) — typically an older or incompatible schema version.
    case schemaMismatch
    /// Anything else: file missing/unreadable, permissions, or an unrecognized decode failure.
    case other(String)
}

protocol LibrarySidecarReaderCapability {
    func loadSidecar(atPath path: String) -> Result<SpinLabFileSidecar, SidecarReadError>
    func loadSidecar(at url: URL) -> Result<SpinLabFileSidecar, SidecarReadError>
}

struct LibrarySidecarReader: LibrarySidecarReaderCapability {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func loadSidecar(atPath path: String) -> Result<SpinLabFileSidecar, SidecarReadError> {
        loadSidecar(at: URL(fileURLWithPath: path))
    }

    func loadSidecar(at url: URL) -> Result<SpinLabFileSidecar, SidecarReadError> {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .failure(.other(error.localizedDescription))
        }
        do {
            return .success(try decoder.decode(SpinLabFileSidecar.self, from: data))
        } catch let error as DecodingError {
            switch error {
            case .dataCorrupted:
                return .failure(.corrupted)
            case .keyNotFound, .typeMismatch, .valueNotFound:
                return .failure(.schemaMismatch)
            @unknown default:
                return .failure(.other(String(describing: error)))
            }
        } catch {
            return .failure(.other(error.localizedDescription))
        }
    }
}
