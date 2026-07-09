import CryptoKit
import Foundation

// MARK: - AnalysisPackProviding

/// Shell-level protocol for workflow stores that support save/load/vault integration.
///
/// Conformers provide workflow-specific config+result types; the protocol
/// extension supplies all common save/load/dirty-check logic.
///
/// What the protocol handles (shell):
/// - Finding existing packs by fingerprint
/// - Creating / updating packs in the vault
/// - Dirty-check (SHA256 comparison)
/// - Loading and decoding packs
///
/// What conformers provide (workflow):
/// - What to save: `buildPackConfig()` / `buildPackResult()`
/// - How to restore: `restoreFromPack(config:result:pack:restoreSearchState:)`
/// - Identity: `packWorkflowID`, `packInputFiles`, `packSampleKeys`
/// - Display label: `autoPackLabel()`
@MainActor
protocol AnalysisPackProviding: AnyObject {
    associatedtype PackConfig: Codable
    associatedtype PackResult: Codable

    // MARK: - Storage (stored properties on conformer)

    var vault: AnalysisVault? { get set }
    var activePackID: AnalysisPack.ID? { get set }
    var analysisMessage: String? { get set }

    // MARK: - Workflow identity

    var packWorkflowID: String { get }

    // MARK: - Snapshot builders (workflow-specific)

    func buildPackConfig() -> PackConfig
    func buildPackResult() -> PackResult
    func autoPackLabel() -> String

    // MARK: - Fingerprint inputs

    var packInputFiles: [String] { get }
    var packSampleKeys: [String] { get }
    /// Non-nil for workflows that include an RT file in fingerprint (3ω).
    var packRTFilePath: String? { get }

    // MARK: - Guard: does the workflow have a result worth saving?

    var hasAnalysisResult: Bool { get }

    // MARK: - Restore (workflow-specific)

    /// Decode pack blobs and restore all workflow state. Called by default `loadPack`.
    /// `activePackID` and `analysisMessage` are set by the caller — do not set them here.
    func restoreFromPack(config: PackConfig, result: PackResult, pack: AnalysisPack,
                         restoreSearchState: @escaping ([WorkflowMeasurementSearchHit], String) -> Void,
                         seedSelection: @escaping (Set<String>, [WorkflowMeasurementSearchHit]) -> Void)

    // MARK: - Warnings

    // MARK: - Re-analysis after load

    func runAnalysis()

    // MARK: - Pre-load teardown (workflow-specific)

    /// Cancel in-flight tasks before loading a pack. Default does nothing.
    func cancelInflightWork()
}

// MARK: - SearchQueryTextInjectable

/// Opt-in protocol for pack config types that carry a `searchQueryText` field.
/// Used by the default `saveAnalysis` to inject the search query from WorkbenchFeatureStore.
protocol SearchQueryTextInjectable {
    var searchQueryText: String { get set }
}

@MainActor
protocol PackRestoreFailureReporting {
    var packRestoreErrorMessage: String? { get set }
}

// MARK: - Default Implementations

extension AnalysisPackProviding {

    var packRTFilePath: String? { nil }

    func cancelInflightWork() {}

    // MARK: - Computed

    var sourceFingerprint: String {
        AnalysisPack.makeFingerprint(inputFiles: packInputFiles, rtFilePath: packRTFilePath)
    }

    var matchingVaultPack: AnalysisPack? {
        guard hasAnalysisResult, let vault else { return nil }
        return vault.pack(forWorkflow: packWorkflowID, fingerprint: sourceFingerprint)
            ?? activePackID.flatMap { vault.get(id: $0) }
    }

    var hasUnsavedAnalysis: Bool {
        guard hasAnalysisResult else { return false }
        guard let packID = activePackID, let vault, let pack = vault.get(id: packID) else {
            return true
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let cc = try? encoder.encode(buildPackConfig()),
              let cr = try? encoder.encode(buildPackResult()) else { return true }
        var current = cc; current.append(cr)
        var stored = pack.config; stored.append(pack.result)
        return SHA256.hash(data: current) != SHA256.hash(data: stored)
    }

    // MARK: - Save

    func saveAnalysis(searchQueryText: String = "") {
        guard let vault else { analysisMessage = "Vault not available."; return }
        guard hasAnalysisResult else { analysisMessage = "No analysis to save."; return }

        var config = buildPackConfig()
        if var injectable = config as? (any SearchQueryTextInjectable) {
            injectable.searchQueryText = searchQueryText
            // Safe: injectable was obtained from config (same concrete type).
            config = injectable as! PackConfig  // swiftlint:disable:this force_cast
        }
        let result = buildPackResult()
        let fp = sourceFingerprint

        let existing = vault.pack(forWorkflow: packWorkflowID, fingerprint: fp)
            ?? activePackID.flatMap { vault.get(id: $0) }

        if let existing {
            do {
                var pack = existing
                let enc = JSONEncoder()
                enc.outputFormatting = .sortedKeys
                pack.config = try enc.encode(config)
                pack.result = try enc.encode(result)
                pack.filePaths = packInputFiles
                pack.sampleKeys = packSampleKeys
                pack.sourceFingerprint = fp
                vault.update(pack)
                activePackID = pack.id
                analysisMessage = "Updated: \(pack.label)"
            } catch {
                analysisMessage = "Save failed: \(error.localizedDescription)"
            }
        } else {
            do {
                let pack = try AnalysisPack(
                    label: autoPackLabel(),
                    workflowID: packWorkflowID,
                    filePaths: packInputFiles,
                    sampleKeys: packSampleKeys,
                    sourceFingerprint: fp,
                    config: config,
                    result: result
                )
                vault.add(pack)
                activePackID = pack.id
                analysisMessage = "Analysis saved: \(pack.label)"
            } catch {
                analysisMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Load

    func loadPack(id: AnalysisPack.ID,
                  restoreSearchState: @escaping ([WorkflowMeasurementSearchHit], String) -> Void,
                  seedSelection: @escaping (Set<String>, [WorkflowMeasurementSearchHit]) -> Void = { _, _ in }) {
        cancelInflightWork()
        guard let vault, let pack = vault.get(id: id) else {
            analysisMessage = "Pack not found."
            return
        }
        let config: PackConfig
        let result: PackResult
        do {
            config = try pack.decodeConfig(PackConfig.self)
            result = try pack.decodeResult(PackResult.self)
        } catch {
            analysisMessage = "Failed to decode pack data: \(error)"
            print("[SpinLab][Pack] Decode failed for \(id): \(error)")
            return
        }
        restoreFromPack(config: config, result: result, pack: pack,
                        restoreSearchState: restoreSearchState,
                        seedSelection: seedSelection)
        if let reporter = self as? any PackRestoreFailureReporting,
           let restoreError = reporter.packRestoreErrorMessage {
            activePackID = nil
            analysisMessage = restoreError
            return
        }
        // Re-assign after restore — some workflows clear activePackID inside runAnalysis.
        activePackID = id
        analysisMessage = "Loaded: \(pack.label)"
    }
}
