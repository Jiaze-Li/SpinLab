import Foundation

struct RulesPersistenceHook {
    var didPersist: ((_ sectionID: String, _ runtimeURL: URL, _ schemaVersion: Int, _ checksum: String, _ outcome: DualWriteOutcome) -> Void)?
}
