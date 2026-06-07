import Foundation

struct RulesPersistenceHook {
    var didPersist: ((_ sectionID: String, _ url: URL, _ schemaVersion: Int, _ checksum: String) -> Void)?
}
