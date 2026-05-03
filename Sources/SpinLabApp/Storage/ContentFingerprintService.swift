import CryptoKit
import Foundation

struct ContentFingerprintService: Sendable {
    func contentFingerprint(for url: URL) -> String? {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        } catch {
            let code = (error as NSError).code
            if code != NSFileReadNoSuchFileError && code != NSFileNoSuchFileError {
                fputs("[ContentFingerprintService] Failed to read fingerprint for \(url.lastPathComponent): \(error.localizedDescription)\n", stderr)
            }
            return nil
        }
    }
}
