import Foundation
import Testing
@testable import SpinLabApp

/// Phase 3B / F4 hardening: `SampleSemanticDescriptor.init` now validates `material` and
/// `orientation` against the compiled substrate rules the same way it already validated
/// `processingTokens` — so a future 5th identity entry point (e.g. Obsidian) can't reintroduce
/// F4-style drift by skipping validation for these two fields. Trusted reconstruction paths
/// (`fromSampleKey`, `withPrevalidatedTokens`) must still bypass this validation so already
/// canonical/pre-classified values are preserved even if rules changed since.
// .serialized: every test in this suite mutates the process-global RuleLoader singleton
// (RuleLoader.configure) that SampleSemanticDescriptor's plain init reads from — running them
// concurrently races that shared state (one test's cleanup can clobber another's setup).
@Suite("V5.4.3 SampleSemanticDescriptor material/orientation validation", .serialized)
struct V543SampleSemanticDescriptorValidationTests {
    private func withBundledSingleton<T>(_ body: () throws -> T) rethrows -> T {
        let bundledDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SpinLabApp/config")
        let savedPaths = RuleLoader.currentBookPaths
        RuleLoader.configure(bookPaths: RulesConfigPaths(configDirectoryURL: bundledDir), internalPaths: AppInternalPaths())
        defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }
        return try body()
    }

    @Test("plain init rejects a material string that matches no configured rule")
    func plainInitRejectsUnrecognizedMaterial() throws {
        try withBundledSingleton {
            let descriptor = SampleSemanticDescriptor(batch: "PN1", material: "NotARealMaterial", orientation: nil)
            #expect(descriptor.material == nil)
        }
    }

    @Test("plain init accepts a material string recognized by a configured contains rule")
    func plainInitAcceptsRecognizedMaterial() throws {
        try withBundledSingleton {
            let descriptor = SampleSemanticDescriptor(batch: "PN1", material: "sto", orientation: nil)
            #expect(descriptor.material == "STO")
        }
    }

    @Test("plain init rejects an orientation string that matches no configured rule")
    func plainInitRejectsUnrecognizedOrientation() throws {
        try withBundledSingleton {
            let descriptor = SampleSemanticDescriptor(batch: "PN1", material: nil, orientation: "999")
            #expect(descriptor.orientation == nil)
        }
    }

    @Test("plain init resolves an equals-alias orientation to its canonical display name")
    func plainInitResolvesOrientationAlias() throws {
        try withBundledSingleton {
            // "100" is an equals-only alias for orientation "001" in the bundled config.
            let descriptor = SampleSemanticDescriptor(batch: "PN1", material: nil, orientation: "100")
            #expect(descriptor.orientation == "001")
        }
    }

    @Test("fromSampleKey bypasses rule validation and preserves the stored value verbatim")
    func fromSampleKeyPreservesLegacyValues() throws {
        try withBundledSingleton {
            // "LegacyMineral" is not a configured material anywhere — fromSampleKey must still
            // preserve it, because a stored canonical key predates (or postdates) the current
            // rule set and must not silently lose data on reconstruction.
            let descriptor = SampleSemanticDescriptor.fromSampleKey("PN1|o|LEGACYMINERAL|999")
            #expect(descriptor?.material == "LEGACYMINERAL")
            #expect(descriptor?.orientation == "999")
        }
    }

    @Test("withPrevalidatedTokens bypasses rule validation and preserves the given value verbatim")
    func withPrevalidatedTokensPreservesGivenValues() throws {
        try withBundledSingleton {
            let descriptor = SampleSemanticDescriptor.withPrevalidatedTokens(
                batch: "PN1",
                processingTokens: [],
                material: "AlreadyClassifiedMaterial",
                orientation: "AlreadyClassifiedOrientation"
            )
            #expect(descriptor.material == "ALREADYCLASSIFIEDMATERIAL")
            #expect(descriptor.orientation == "ALREADYCLASSIFIEDORIENTATION")
        }
    }

    @Test("UNKNOWN material/orientation still normalize to nil under validation")
    func unknownStillNormalizesToNil() throws {
        try withBundledSingleton {
            let descriptor = SampleSemanticDescriptor(batch: "PN1", material: "unknown", orientation: "UNKNOWN")
            #expect(descriptor.material == nil)
            #expect(descriptor.orientation == nil)
        }
    }
}
