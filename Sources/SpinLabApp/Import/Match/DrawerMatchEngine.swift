import Foundation

struct DrawerMatchIndex {
    struct Candidate {
        var sampleID: String
        var sampleKeyTokens: Set<String>
    }

    var candidates: [Candidate] = []
    var sampleIDsByCanonicalKey: [String: [String]] = [:]
}

struct DrawerMatchEngine {
    func makeIndex(from samples: [LibrarySample]) -> DrawerMatchIndex {
        var index = DrawerMatchIndex()
        index.candidates = samples.map { sample in
            DrawerMatchIndex.Candidate(
                sampleID: sample.id,
                sampleKeyTokens: Set(sampleKeyTokens(from: sample))
            )
        }

        for sample in samples {
            guard let canonical = SampleSemanticDescriptor.fromSampleKey(sample.id)?.canonicalKey else {
                continue
            }
            index.sampleIDsByCanonicalKey[canonical, default: []].append(sample.id)
        }

        return index
    }

    func match(sampleInput: String, index: DrawerMatchIndex) -> String? {
        let trimmed = sampleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let canonical = canonicalKey(fromSampleInput: trimmed),
           let exactMatches = index.sampleIDsByCanonicalKey[canonical],
           exactMatches.count == 1 {
            return exactMatches[0]
        }

        guard !index.candidates.isEmpty else {
            return nil
        }

        let inputTokens = Set(SampleTokenization.matchingTokens(from: trimmed))
        guard !inputTokens.isEmpty else {
            return nil
        }

        let matched = index.candidates.filter { candidate in
            inputTokens.isSubset(of: candidate.sampleKeyTokens)
        }
        guard matched.count == 1, let unique = matched.first else {
            return nil
        }
        return unique.sampleID
    }

    private func canonicalKey(fromSampleInput value: String) -> String? {
        if let exact = SampleSemanticDescriptor.fromSampleKey(value)?.canonicalKey {
            return exact
        }

        let rules = FileRoutingRuleBook()
        guard let descriptor = rules.resolvedDescriptor(sampleInput: value, sampleTags: [], fallback: nil) else {
            return nil
        }
        return descriptor.canonicalKey
    }

    private func sampleKeyTokens(from sample: LibrarySample) -> [String] {
        if sample.id.contains("|") {
            let parts = sample.id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            return parts.flatMap { SampleTokenization.matchingTokens(from: $0) }
        }
        return SampleTokenization.matchingTokens(from: [
            sample.id,
            sample.batchId,
            sample.substrateTokens.joined(separator: " ")
        ].joined(separator: " "))
    }
}
