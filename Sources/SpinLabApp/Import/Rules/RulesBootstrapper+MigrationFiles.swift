import Foundation
import CryptoKit

extension RulesBootstrapper {

    static func writeMigrationState(
        to url: URL,
        sourceSHA: [String: String],
        targetSHA: [String: String],
        warnings: [String]
    ) {
        let body: [String: Any] = [
            "rules_schema_version": 7,
            "migrated_at": migrationDateString(),
            "source_sha256": sourceSHA,
            "target_sha256": targetSHA,
            "warnings": warnings
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.warning(.import, "RulesBootstrapper: failed to write migration_state (\(error.localizedDescription))")
        }
    }

    static func writeMigrationFailed(to url: URL, reason: String, warnings: [String]) {
        let body: [String: Any] = [
            "failed_at": migrationDateString(),
            "reason": reason,
            "warnings": warnings
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            AppLogger.shared.error(.import, "RulesBootstrapper migration verify failed", metadata: [
                "reason": reason
            ])
        } catch {
            AppLogger.shared.error(.import, "RulesBootstrapper migration verify failed; cannot persist failure file", metadata: [
                "reason": error.localizedDescription
            ])
        }
    }

    static func migrationTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    static func migrationDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.string(from: Date())
    }

    static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func cleanupTmpDirectory(_ tmpDir: URL, fileManager: FileManager) {
        guard fileManager.fileExists(atPath: tmpDir.path) else { return }
        do {
            try fileManager.removeItem(at: tmpDir)
        } catch {
            AppLogger.shared.warning(.import, "RulesBootstrapper migration tmp cleanup failed (\(error.localizedDescription))")
        }
    }
}
