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

private enum WorkflowIDPolicyLoader {
    static func load(bundle: Bundle = .main) -> WorkflowIDPolicy {
        guard let url = bundle.url(forResource: "workflow_id_policy", withExtension: "json", subdirectory: "config"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(WorkflowIDPolicy.self, from: data) else {
            return .fallback
        }
        let normalizedPrefix = decoded.fallbackPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let alphabet = decoded.preferredAlphabet.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedPrefix.isEmpty || alphabet.isEmpty {
            return .fallback
        }
        return WorkflowIDPolicy(preferredAlphabet: alphabet, fallbackPrefix: normalizedPrefix)
    }
}
