import Foundation
@testable import SpinLabApp

/// Test-only helpers for Rules-dependent tests.
///
/// The goal is to make every Rules test declare its rule source explicitly:
/// bundled fixture rules, an isolated temporary Rules Book, or no configured
/// Rules Book. This avoids ad-hoc RuleLoader.configure/restore sequences and
/// reduces global singleton/cache ambiguity during debugging.

@discardableResult
func withBundledRules<T>(
    _ body: (_ provider: InlineRuleProvider) throws -> T
) rethrows -> T {
    let provider = InlineRuleProvider(loadResult: RuleLoader().loadFromBundleOnly())
    return try body(provider)
}

@discardableResult
func withUnconfiguredRules<T>(
    _ body: () throws -> T
) rethrows -> T {
    let savedPaths = RuleLoader.currentBookPaths
    RuleLoader.configure(bookPaths: nil, internalPaths: AppInternalPaths())
    defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }
    return try body()
}

@discardableResult
func withTempRulesDirectory<T>(
    prefix: String = "SL-rules-dir",
    _ body: (_ directoryURL: URL, _ paths: RulesConfigPaths) throws -> T
) throws -> T {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    let paths = RulesConfigPaths(configDirectoryURL: directoryURL)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    return try body(directoryURL, paths)
}

@discardableResult
func withTempRulesBook<T>(
    prefix: String = "SL-rules-book",
    batchPrefix: String = "S",
    supportedExtensions: [String] = ["dat"],
    _ body: (_ paths: RulesConfigPaths, _ provider: InlineRuleProvider) throws -> T
) throws -> T {
    let savedPaths = RuleLoader.currentBookPaths
    return try withTempRulesDirectory(prefix: prefix) { directoryURL, paths in
        try writeMinimalRulesBook(
            to: paths,
            batchPrefix: batchPrefix,
            supportedExtensions: supportedExtensions
        )
        let internalPaths = AppInternalPaths(appSupportDirectoryURL: directoryURL)
        RuleLoader.configure(bookPaths: paths, internalPaths: internalPaths)
        let loadResult = RuleLoader.shared.reloadCached()
        let provider = InlineRuleProvider(loadResult: loadResult)
        defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }
        return try body(paths, provider)
    }
}

func writeMinimalRulesBook(
    to paths: RulesConfigPaths,
    batchPrefix: String = "S",
    supportedExtensions: [String] = ["dat"]
) throws {
    let encodedExtensions = supportedExtensions
        .map { "\"\($0)\"" }
        .joined(separator: ",")

    try """
    {"version":1,"import":{"supportedFileExtensions":[\(encodedExtensions)],"ignoredFileExtensions":[]}}
    """.data(using: .utf8)!.write(to: paths.importFiltersURL)

    try """
    {"version":1,"tokenization":{"separators":"_","caseFold":"preserve"},"sources":["file"],"channel":{"aliases":{}}}
    """.data(using: .utf8)!.write(to: paths.filenameTokenizationURL)

    try """
    {"version":4,"sampleId":{"batchPrefixes":["\(batchPrefix)"]},"substrate":{"materials":[],"treatments":[],"orientations":[]}}
    """.data(using: .utf8)!.write(to: paths.sampleIdentificationURL)

    try """
    {"version":1,"workflows":[],"measurementTagRules":[]}
    """.data(using: .utf8)!.write(to: paths.workflowURL)

    try """
    {"version":2,"conditionDefinitions":[]}
    """.data(using: .utf8)!.write(to: paths.measuringConditionURL)
}
