import Foundation

protocol AuditLogging {
    func logImportEvent(_ event: AuditEvent, libraryRootURL: URL)
    func logRuleWriteEvent(action: String, result: String, sourceFilePath: String, metadata: [String: String])
}

extension AuditLogger: AuditLogging {}
