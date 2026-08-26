import Foundation

/// Minimal, deliberately non-general frontmatter reader for the real vault's
/// observed shape: `key: scalar`, `key:` (empty), `key: "quoted"`, and
/// `key:\n  - item\n  - item` lists. Not a YAML implementation — the real
/// vault never nests beyond one level, so a full YAML parser would be scope
/// creep (see Phase 4 spec §3 "不要为了未来通用建立复杂 framework").
enum ObsidianFrontmatterValue: Hashable, Sendable {
    case scalar(String)
    case list([String])
}

struct ObsidianFrontmatterParser {
    /// Returns nil if the note has no `---`-delimited frontmatter block at
    /// all — such notes are out of scope for this phase (see
    /// `ObsidianDiagnosticKind.noFrontmatter`) rather than an error.
    static func parse(_ contents: String) -> [(key: String, value: ObsidianFrontmatterValue)]? {
        var lines = contents.components(separatedBy: .newlines)[...]
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }
        lines = lines.dropFirst()

        var body: [String] = []
        var closed = false
        while let line = lines.first {
            lines = lines.dropFirst()
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                closed = true
                break
            }
            body.append(line)
        }
        guard closed else {
            return nil
        }

        var result: [(key: String, value: ObsidianFrontmatterValue)] = []
        var index = 0
        while index < body.count {
            let line = body[index]
            guard let colonRange = line.range(of: ":") else {
                index += 1
                continue
            }
            let key = String(line[line.startIndex..<colonRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                index += 1
                continue
            }
            let inlineValue = String(line[colonRange.upperBound...])
                .trimmingCharacters(in: .whitespaces)

            if inlineValue.isEmpty {
                // Possible list on following indented `- ` lines.
                var items: [String] = []
                var lookahead = index + 1
                while lookahead < body.count {
                    let candidate = body[lookahead]
                    let trimmed = candidate.trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(" ") || candidate.hasPrefix("\t"), trimmed.hasPrefix("- ") || trimmed == "-" else {
                        break
                    }
                    let item = trimmed.hasPrefix("- ")
                        ? String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                        : ""
                    if !item.isEmpty {
                        items.append(unquote(item))
                    }
                    lookahead += 1
                }
                if !items.isEmpty {
                    result.append((key, .list(items)))
                    index = lookahead
                    continue
                }
                result.append((key, .scalar("")))
                index += 1
                continue
            }

            result.append((key, .scalar(unquote(inlineValue))))
            index += 1
        }
        return result
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2,
              (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'"))
        else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}
