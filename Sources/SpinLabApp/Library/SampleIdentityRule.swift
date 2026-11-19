import Foundation

/// L1: the single definition of the permanent Sample identity (`smp_…`): prefix, random generation,
/// deterministic conversion of a phone submission id, and format validation. Nothing else in the
/// code base may spell the prefix or build / validate a Sample UID.
enum SampleIdentityRule {
    static let prefix = "smp_"

    static func makeRandomUID() -> String {
        prefix + UUID().uuidString.lowercased()
    }

    /// Deterministic UID of the substrate at `index` (0 is the first) of one phone submission. The first
    /// keeps the plain submission UID, later ones get a stable "-2", "-3" suffix, so a repeated pickup
    /// finds every sample already there.
    static func uid(forSubmissionId submissionId: String, index: Int = 0) -> String {
        uid(baseUID: prefix + submissionId.lowercased(), index: index)
    }

    /// The UID of the substrate at `index` for an already-built base UID (first one unchanged).
    static func uid(baseUID: String, index: Int) -> String {
        index <= 0 ? baseUID : "\(baseUID)-\(index + 1)"
    }

    /// A UID is path-safe by construction: `smp_` + lowercase hex / dash only.
    static func isValidUID(_ value: String) -> Bool {
        guard value.hasPrefix(prefix), value.count > prefix.count else { return false }
        return value.dropFirst(prefix.count).allSatisfy { ($0.isASCII && $0.isNumber) || ("a"..."f").contains($0) || $0 == "-" }
    }
}

/// L2: the single issuing entry for Sample UIDs.
enum SampleIDIssuer {
    enum LegacyIssue: Equatable {
        case alreadyIssued(String)
        case issued(String)
    }

    /// Reuses a valid UID the caller already holds (form opened, phone submission); otherwise issues a new one.
    static func issueForNewSample(preferredUID: String? = nil) -> String {
        if let preferred = preferredUID?.trimmingCharacters(in: .whitespacesAndNewlines),
           SampleIdentityRule.isValidUID(preferred) {
            return preferred
        }
        return SampleIdentityRule.makeRandomUID()
    }

    /// Skips samples that already carry a valid permanent UID; otherwise issues a new one.
    static func issueForLegacyBackfill(sample: LibrarySample) -> LegacyIssue {
        if let existing = sample.sampleUID, SampleIdentityRule.isValidUID(existing) {
            return .alreadyIssued(existing)
        }
        return .issued(SampleIdentityRule.makeRandomUID())
    }
}

/// L3: the single place that records and looks up the `smp_` <-> legacy Sample Key correspondence.
/// The record lives on each sample (`sampleUID` + `legacySampleKey` inside its own `sample.json`).
enum SampleLegacyKeyMapping {
    /// What a Registry row's old key is recorded as: always the legacy cue, never a primary key.
    static func record(cue: String, on sample: LibrarySample) -> LibrarySample {
        var result = sample
        result.legacySampleKey = cue
        return result
    }

    /// The legacy key a stored sample answers to (its recorded key, or its old id for un-backfilled samples).
    static func legacyKey(of sample: LibrarySample) -> String {
        if let key = sample.legacySampleKey, !key.isEmpty { return key }
        return sample.id
    }

    /// Finds the existing Registry-managed (non-native) sample an incoming Registry row refers to.
    /// Native / manual samples are never matched.
    static func findRegistryMatch(forIncomingCue cue: String, batchId: String? = nil, in samples: [LibrarySample]) -> LibrarySample? {
        samples.first { sample in
            guard !sample.isNativeOrManual else { return false }
            if let batchId, sample.batchId != batchId { return false }
            return sample.legacySampleKey == cue || sample.id == cue
        }
    }

    static func findRegistryMatch(forIncomingCue cue: String, batchId: String? = nil, in index: LibraryIndex) -> LibrarySample? {
        findRegistryMatch(forIncomingCue: cue, batchId: batchId, in: index.samples)
    }
}
