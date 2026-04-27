import Foundation

/// ruleRef grammar factory (s2 provenance schema §1.1)
/// Format: rule:<namespace>.<path><locator>
/// Locator: #<index> (array, 0-based) | @<key> (dict key) | .default (no explicit match)
enum RuleRef {

    // MARK: - sampleId namespace

    static func sampleIdBatchPrefix(index: Int) -> String {
        "rule:sampleId.batchPrefixes#\(index)"
    }

    static func sampleIdPattern(index: Int) -> String {
        "rule:sampleId.patterns#\(index)"
    }

    // MARK: - condition namespace

    static func conditionUnitSuffix(id: String, definitionIndex: Int) -> String {
        "rule:condition.\(id).unitSuffix#\(definitionIndex)"
    }

    static func conditionTokenMap(id: String, ruleIndex: Int) -> String {
        "rule:condition.\(id).tokenMap#\(ruleIndex)"
    }

    /// conditions.extraConditions[X] binding → unit pattern source
    static func conditionExtraPattern(id: String) -> String {
        "rule:condition.\(id).extraPattern@\(sanitizeKey(id))"
    }

    // MARK: - substrate namespace

    static func substrateMaterial(index: Int) -> String {
        "rule:substrate.materials#\(index)"
    }

    static func substrateOrientation(index: Int) -> String {
        "rule:substrate.orientations#\(index)"
    }

    static func substrateTreatment(index: Int) -> String {
        "rule:substrate.treatments#\(index)"
    }

    // MARK: - channel namespace

    static func channelAlias(normalizedKey: String) -> String {
        "rule:channel.aliases@\(sanitizeKey(normalizedKey))"
    }

    // MARK: - measurementName / measurementTag namespaces

    static func measurementNameRule(index: Int) -> String {
        "rule:measurementName.rules#\(index)"
    }

    static func measurementTagRule(index: Int) -> String {
        "rule:measurementTag.rules#\(index)"
    }

    // MARK: - fallback / migration namespaces

    static func fallback(fieldPath: String) -> String {
        "rule:fallback.\(fieldPath).default"
    }

    static func migrationV1(fieldPath: String) -> String {
        "rule:migration.v1.\(fieldPath).default"
    }

    // MARK: - @key length guard (spec §1.1: ≤160 chars; truncate + 8-char hex hash suffix)

    private static func sanitizeKey(_ key: String) -> String {
        guard key.count > 160 else { return key }
        let prefix = String(key.prefix(152))
        let hashSuffix = String(format: "%08x", UInt32(bitPattern: Int32(truncatingIfNeeded: key.hashValue)))
        return "\(prefix)\(hashSuffix)"
    }
}
