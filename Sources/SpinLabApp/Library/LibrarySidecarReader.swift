import Foundation

/// Distinguishes why a sidecar failed to load, so callers can react differently
/// to a malformed file versus one written by an older/incompatible schema.
enum SidecarReadError: Error, Equatable, Sendable {
    /// The file exists but its JSON is malformed (truncated, invalid syntax, etc).
    case corrupted
    /// The JSON parsed but doesn't match `SpinLabFileSidecar`'s expected shape
    /// (missing key, wrong type, unknown enum value, invalid date, etc) — typically
    /// an older or incompatible schema version.
    case schemaMismatch
    /// Anything else: file missing/unreadable, permissions, or an unexpected failure.
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

        // Keep syntax validation separate from model decoding. `JSONDecoder` may
        // report semantic/schema failures (for example an unknown enum raw value
        // or an invalid ISO-8601 date) as `DecodingError.dataCorrupted`, so using
        // that case alone cannot reliably distinguish malformed JSON from schema drift.
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            return .failure(.corrupted)
        }

        do {
            return .success(try decoder.decode(SpinLabFileSidecar.self, from: data))
        } catch is DecodingError {
            return .failure(.schemaMismatch)
        } catch {
            return .failure(.other(error.localizedDescription))
        }
    }
}
