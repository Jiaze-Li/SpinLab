import Foundation

enum LibraryDestinationSubpath {
    static func subpath(workflowName: String?) -> String {
        let sanitized = workflowName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "_")
        if let workflow = sanitized, !workflow.isEmpty {
            return "measurements/\(workflow)"
        }
        return "measurements/General"
    }
}
