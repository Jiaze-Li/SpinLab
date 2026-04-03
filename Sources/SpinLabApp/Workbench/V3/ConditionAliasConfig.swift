import Foundation

struct ConditionAliasConfig: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var conditionAliases: [String: [String]]
}

struct ConditionAliasBook: Hashable, Sendable {
    private let aliasToCanonical: [String: String]
    private let canonicalToAliases: [String: [String]]

    init(config: ConditionAliasConfig) {
        var aliasMap: [String: String] = [:]
        var canonicalMap: [String: [String]] = [:]

        for (canonicalRaw, aliasesRaw) in config.conditionAliases {
            let canonical = normalizeField(canonicalRaw)
            let aliases = aliasesRaw
                .map(normalizeField)
                .filter { !$0.isEmpty }
                .sorted()

            canonicalMap[canonical] = aliases
            aliasMap[canonical] = canonical
            for alias in aliases {
                aliasMap[alias] = canonical
            }
        }

        aliasToCanonical = aliasMap
        canonicalToAliases = canonicalMap
    }

    func resolve(_ field: String) -> String {
        let normalized = normalizeField(field)
        return aliasToCanonical[normalized] ?? normalized
    }

    func aliases(for canonicalField: String) -> [String] {
        canonicalToAliases[normalizeField(canonicalField)] ?? []
    }

    func displayLabel(for field: String) -> String {
        let canonical = resolve(field)
        if canonical == normalizeField(field) {
            return canonical
        }
        return "\(canonical) (alias: \(normalizeField(field)))"
    }
}

final class ConditionAliasConfigLoader {
    private let decoder: JSONDecoder
    private let supportedSchemaVersion: Int

    init(supportedSchemaVersion: Int = 1) {
        self.supportedSchemaVersion = supportedSchemaVersion
        decoder = JSONDecoder()
    }

    func load(from fileURL: URL) throws -> ConditionAliasBook {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw AppError.io("Failed to read condition alias config: \(error.localizedDescription)")
        }

        return try load(from: data)
    }

    func load(from data: Data) throws -> ConditionAliasBook {
        let config: ConditionAliasConfig
        do {
            config = try decoder.decode(ConditionAliasConfig.self, from: data)
        } catch {
            throw AppError.validation("Invalid condition alias config JSON: \(error.localizedDescription)")
        }

        guard config.schemaVersion == supportedSchemaVersion else {
            throw AppError.validation(
                "Unsupported condition alias schema v\(config.schemaVersion). Supported: v\(supportedSchemaVersion)."
            )
        }

        return ConditionAliasBook(config: config)
    }
}

private func normalizeField(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}
