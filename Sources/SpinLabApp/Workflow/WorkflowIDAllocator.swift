import Foundation

protocol WorkflowIDAllocating {
    func nextID(existingIDs: [String]) -> String
}

struct WorkflowIDPolicy: Codable {
    var preferredAlphabet: String
    var fallbackPrefix: String

    static let fallback = WorkflowIDPolicy(
        preferredAlphabet: "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        fallbackPrefix: "WF"
    )
}

struct DefaultWorkflowIDAllocator: WorkflowIDAllocating {
    private let policy: WorkflowIDPolicy

    init(policy: WorkflowIDPolicy = WorkflowIDPolicyLoader.load()) {
        self.policy = policy
    }

    func nextID(existingIDs: [String]) -> String {
        let existing = Set(existingIDs.map { $0.uppercased() })
        for letter in policy.preferredAlphabet.uppercased() where letter.isLetter {
            let candidate = String(letter)
            if !existing.contains(candidate) {
                return candidate
            }
        }

        var counter = 1
        while true {
            let candidate = "\(policy.fallbackPrefix)\(counter)"
            if !existing.contains(candidate.uppercased()) {
                return candidate
            }
            counter += 1
        }
    }
}

enum WorkflowIDPolicyLoader {
    static func load() -> WorkflowIDPolicy {
        let paths = RulesConfigPaths()
        // Runtime first, then bundle fallback
        let candidates: [URL] = [
            paths.workflowIDPolicyURL,
            bundleURL()
        ].compactMap { $0 }
        for url in candidates {
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(WorkflowIDPolicy.self, from: data) else { continue }
            let prefix = decoded.fallbackPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
            let alphabet = decoded.preferredAlphabet.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prefix.isEmpty, !alphabet.isEmpty else { continue }
            return WorkflowIDPolicy(preferredAlphabet: alphabet, fallbackPrefix: prefix)
        }
        return .fallback
    }

    private static func bundleURL() -> URL? {
        if let url = Bundle.module.url(forResource: "workflow_id_policy", withExtension: "json") {
            return url
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let dev = cwd.appendingPathComponent("Sources/SpinLabApp/config/workflow_id_policy.json")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }
}
