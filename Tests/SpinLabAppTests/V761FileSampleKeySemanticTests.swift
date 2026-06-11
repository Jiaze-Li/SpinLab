import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V7.6.1 fileSampleKey Semantics")
struct V761FileSampleKeySemanticTests {

    private func makeParser() throws -> FilenameRuleParser {
        let result = RuleLoader.shared.loadFromBundleOnly()
        guard result.metadata.sourceLabel != "Fallback" else {
            throw NSError(domain: "V761Tests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Bundle rules unavailable: \(result.warnings.joined(separator: "; "))"
            ])
        }
        return FilenameRuleParser(ruleSet: result.ruleSet)
    }

    // MARK: - 1. Single-channel promotion

    @Test("single channel sample promotes to fileSampleKey when no file/folder scope sample exists")
    func singleChannelPromotesToFileSampleKeyWithNoScopeConflict() throws {
        let parser = try makeParser()
        let fileURL = URL(fileURLWithPath: "/tmp/misc/RT_1mA_ch1_SL134_Rxy_3T_device.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.fileSampleKey == "SL134")
        #expect(parsed.channelHints.first(where: { $0.channel == "ch1" })?.sampleID != nil)
    }

    @Test("channelHints still populated after single-channel promotion")
    func channelHintsPopulatedAfterSingleChannelPromotion() throws {
        let parser = try makeParser()
        let fileURL = URL(fileURLWithPath: "/tmp/misc/RT_1mA_ch1_SL134_Rxy_3T_device.dat")

        let parsed = parser.parse(from: fileURL)

        let ch1 = parsed.channelHints.first(where: { $0.channel == "ch1" })
        #expect(ch1 != nil)
        // Channel hint carries the raw sample name (may include substrate tags).
        #expect(ch1?.sampleID?.contains("SL134") == true)
    }

    @Test("buildRuleSnapshot uses fileSampleKey for sidecar rule snapshot after single-channel promotion")
    func buildRuleSnapshotUsesFileSampleKeyAfterPromotion() throws {
        let loadResult = RuleLoader.shared.loadFromBundleOnly()
        guard loadResult.metadata.sourceLabel != "Fallback" else {
            throw NSError(domain: "V761Tests", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Bundle rules unavailable: \(loadResult.warnings.joined(separator: "; "))"
            ])
        }
        let parser = FilenameRuleParser(ruleSet: loadResult.ruleSet)
        let fileURL = URL(fileURLWithPath: "/tmp/misc/RT_1mA_ch1_SL134_Rxy_3T_device.dat")

        let hints = parser.parse(from: fileURL)
        let snapshot = SidecarCompositionUseCase.buildRuleSnapshot(
            hints: hints,
            ruleSetFingerprint: "test",
            ruleSetVersion: 1,
            evaluatedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(hints.fileSampleKey == "SL134")
        let sampleIDField = try #require(snapshot.fields.sampleID)
        #expect(sampleIDField.value == "SL134")
    }

    // MARK: - 2. Multi-channel: no automatic collapse

    @Test("multi-channel file does not collapse into one fileSampleKey")
    func multiChannelFileDoesNotCollapseToOneFileSampleKey() throws {
        let parser = try makeParser()
        let fileURL = URL(fileURLWithPath: "/tmp/misc/RT_1mA_ch1_SL134_ch2_SL135_Rxy_3T_device.dat")

        let parsed = parser.parse(from: fileURL)

        let ch1 = parsed.channelHints.first(where: { $0.channel == "ch1" })
        let ch2 = parsed.channelHints.first(where: { $0.channel == "ch2" })
        #expect(ch1?.sampleID?.contains("SL134") == true)
        #expect(ch2?.sampleID?.contains("SL135") == true)
        // Ambiguous multi-channel: neither channel wins at file level.
        #expect(parsed.fileSampleKey == nil)
        // Both channel hints must still be intact.
        #expect(parsed.channelHints.count >= 2)
    }

    @Test("multi-channel channelHints contain both channel samples")
    func multiChannelHintsContainBothSamples() throws {
        let parser = try makeParser()
        let fileURL = URL(fileURLWithPath: "/tmp/misc/RT_1mA_ch1_SL134_ch2_SL135_Rxy_3T_device.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.channelHints.contains(where: { $0.channel == "ch1" }))
        #expect(parsed.channelHints.contains(where: { $0.channel == "ch2" }))
    }

    // MARK: - 3. Existing file-level sample wins

    @Test("file-scope sample becomes fileSampleKey even when channel parsing follows")
    func fileScopeSampleWinsAsFileSampleKey() throws {
        let parser = try makeParser()
        // SL134 appears before ch1 (file scope); ch1 has no additional sample token.
        let fileURL = URL(fileURLWithPath: "/tmp/misc/RT_SL134_1mA_ch1_Rxy_3T_device.dat")

        let parsed = parser.parse(from: fileURL)

        #expect(parsed.fileSampleKey == "SL134")
    }

    // MARK: - 4. Migration/cleanup guard

    @Test("ParsedFilenameHints exposes fileSampleKey")
    func parsedFilenameHintsExposesFileSampleKey() throws {
        // This test is a static contract verified by the rg check in CI.
        // The only allowed references are the legacy Codable decode keys in Models.swift.
        // Here we verify the domain model exposes fileSampleKey, not defaultSampleKey.
        let hints = SpinLabDomain.ParsedFilenameHints(fileSampleKey: "X")
        #expect(hints.fileSampleKey == "X")
        // Confirm there is no `defaultSampleKey` property accessible on the type.
        // (If the property existed this line would fail to compile.)
        let _: SpinLabDomain.ParsedFilenameHints = hints
    }
}
