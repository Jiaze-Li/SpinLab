import Foundation

struct DrawerMatchIndex {
    struct Candidate {
        var sampleID: String
        var sampleKeyTokens: Set<String>
        var batch: String?
        var material: String?
        var orientation: String?
    }

    var candidates: [Candidate] = []
    var sampleIDsByCanonicalKey: [String: [String]] = [:]
}

struct DrawerMatchEngine {
    private let sampleKeyNormalizer = SampleKeyNormalizer()

    func makeIndex(from samples: [LibrarySample]) -> DrawerMatchIndex {
        var index = DrawerMatchIndex()
        index.candidates = samples.map { sample in
            let descriptor = sampleKeyNormalizer.descriptor(
                from: sample.id,
                fallbackBatchID: sample.batchId,
                fallbackSampleTags: sample.substrateTokens
            )
            return DrawerMatchIndex.Candidate(
                sampleID: sample.id,
                sampleKeyTokens: Set(sampleKeyTokens(from: sample, descriptor: descriptor)),
                batch: descriptor?.batch,
                material: descriptor?.material,
                orientation: descriptor?.orientation
            )
        }

        for sample in samples {
            guard let canonical = sampleKeyNormalizer.canonicalKey(
                from: sample.id,
                fallbackBatchID: sample.batchId,
                fallbackSampleTags: sample.substrateTokens
            ) else {
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

        let inputDescriptor = sampleKeyNormalizer.descriptor(from: trimmed)

        let matched = index.candidates.filter { candidate in
            guard inputTokens.isSubset(of: candidate.sampleKeyTokens) else {
                return false
            }
            // Flat-token subset alone can't tell a batch identifier's own digits
            // (e.g. batch "PN110") apart from an unrelated candidate whose
            // orientation/material/*different* batch happens to contain the same
            // digits or letters (e.g. batch "PN102" with an STO(110) orientation).
            // Once both sides have a definitively resolved field, require them to
            // be compatible; if either side couldn't resolve a field, stay silent
            // on it so legacy/unparsable sample records keep matching as before.
            guard !batchConflicts(inputDescriptor?.batch, candidate.batch) else {
                return false
            }
            guard !fieldsConflict(inputDescriptor?.orientation, candidate.orientation) else {
                return false
            }
            guard !fieldsConflict(inputDescriptor?.material, candidate.material) else {
                return false
            }
            return true
        }
        guard matched.count == 1, let unique = matched.first else {
            return nil
        }
        return unique.sampleID
    }

    /// Batch names admit partial input (a filename may only carry "PN110" while the
    /// library batch is "PN110/SRO5"), so this is a token-subset check rather than
    /// strict equality: every token the input's batch resolves to must appear among
    /// the candidate's batch tokens.
    private func batchConflicts(_ inputBatch: String?, _ candidateBatch: String?) -> Bool {
        guard let inputBatch, let candidateBatch else {
            return false
        }
        let inputBatchTokens = Set(SampleTokenization.matchingTokens(from: inputBatch))
        guard !inputBatchTokens.isEmpty else {
            return false
        }
        let candidateBatchTokens = Set(SampleTokenization.matchingTokens(from: candidateBatch))
        return !inputBatchTokens.isSubset(of: candidateBatchTokens)
    }

    private func fieldsConflict(_ inputValue: String?, _ candidateValue: String?) -> Bool {
        guard let inputValue, let candidateValue else {
            return false
        }
        return inputValue != candidateValue
    }

    private func canonicalKey(fromSampleInput value: String) -> String? {
        sampleKeyNormalizer.canonicalKey(from: value)
    }

    private func sampleKeyTokens(from sample: LibrarySample, descriptor: SampleSemanticDescriptor?) -> [String] {
        var tokens: [String] = []
        if let canonical = descriptor?.canonicalKey {
            let canonicalParts = canonical.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            tokens.append(contentsOf: canonicalParts.flatMap { SampleTokenization.matchingTokens(from: $0) })
        }

        if sample.id.contains("|") {
            let parts = sample.id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            tokens.append(contentsOf: parts.flatMap { SampleTokenization.matchingTokens(from: $0) })
            return tokens
        }
        tokens.append(contentsOf: SampleTokenization.matchingTokens(from: [
            sample.id,
            sample.batchId,
            sample.substrateTokens.joined(separator: " ")
        ].joined(separator: " ")))
        return tokens
    }
}
