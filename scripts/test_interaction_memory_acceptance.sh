#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/4] Build project"
swift build >/dev/null

echo "[2/4] Static guard checks"
rg -n "struct InboxPendingWorkspaceState" Sources/SpinLabApp/App/SpinLabAppState.swift >/dev/null
rg -n "snapshotSafe\\(" Sources/SpinLabApp/App/SpinLabAppState.swift >/dev/null
rg -n "InboxPendingWorkspaceState\\.snapshotSafe\\(" Sources/SpinLabApp/Features/Inbox/InboxView.swift >/dev/null
rg -n "final class InteractionMemoryStore" Sources/SpinLabApp/App/InteractionMemoryStore.swift >/dev/null
rg -n "private let interactionMemory: InteractionMemoryStore" Sources/SpinLabApp/App/SpinLabAppState.swift >/dev/null

echo "[3/4] Runtime acceptance checks (memory behavior + isolation)"
HARNESS_DIR="$(mktemp -d)"
trap 'rm -rf "$HARNESS_DIR"' EXIT

cat > "$HARNESS_DIR/harness.swift" <<'SWIFT'
import Foundation

enum AppArea: String, Codable {
    case inbox
    case workbench
    case library
}

enum LibrarySelectionSource: String, Codable {
    case browser
    case drawer
}

struct PendingImportConfirmationDraft: Codable, Equatable {
    static let noProjectOption = "None"
    var batchName: String
    var sampleName: String
    var measurementName: String
    var deviceName: String
    var temperature: String
    var selectedExistingProjectName: String
    var newProjectName: String
}

struct SidebarInteractionState: Codable, Equatable {
    var isLibraryTreeExpanded: Bool = true
    var expandedPrefixes: Set<String> = []
}

struct LibraryInteractionState: Codable, Equatable {
    var selectedPrefix: String?
    var selectedBatchId: String?
    var selectedSampleId: String?
    var isLibrarySettingsExpanded: Bool = true
    var isRegistryWorkspaceExpanded: Bool = true
    var isSearchWorkspaceExpanded: Bool = true
    var searchBatchIdText: String = ""
    var searchSubstrateText: String = ""
    var searchKeywordText: String = ""
    var searchThicknessText: String = ""
    var searchOxygenText: String = ""
    var searchTemperatureText: String = ""
    var searchEnergyText: String = ""
    var searchHasExecuted: Bool = false
}

struct InboxPendingWorkspaceState: Codable, Equatable {
    var draft: PendingImportConfirmationDraft
    var editableFileContents: String
    var hasEditableFileContents: Bool
}

struct SpinLabInteractionSnapshot: Codable, Equatable {
    var selectedArea: AppArea = .inbox
    var selectedPendingImportID: UUID?
    var selectedArchivedRecordID: UUID?
    var workbenchResultDraft: String = ""
    var libraryActiveSelectionSource: LibrarySelectionSource = .browser
    var librarySelectedPrefix: String?
    var librarySelectedBatchId: String?
    var librarySelectedSampleId: String?
    var inboxWorkspaceByPendingID: [String: InboxPendingWorkspaceState] = [:]
    var sidebar: SidebarInteractionState = SidebarInteractionState()
    var libraryView: LibraryInteractionState = LibraryInteractionState()
}

enum SpinLabDomain {
    struct PendingImport {}
    struct ArchivedRecord {}
    struct Project {}
}

protocol SpinLabPersistence {
    func loadPendingImports() -> [SpinLabDomain.PendingImport]
    func savePendingImports(_ imports: [SpinLabDomain.PendingImport])
    func loadArchivedRecords() -> [SpinLabDomain.ArchivedRecord]
    func saveArchivedRecords(_ records: [SpinLabDomain.ArchivedRecord])
    func loadProjects() -> [SpinLabDomain.Project]
    func saveProjects(_ projects: [SpinLabDomain.Project])
    func loadInteractionSnapshot() -> SpinLabInteractionSnapshot
    func saveInteractionSnapshot(_ snapshot: SpinLabInteractionSnapshot)
}

final class MockPersistence: SpinLabPersistence {
    var snapshot = SpinLabInteractionSnapshot()
    var saveCount = 0
    func loadPendingImports() -> [SpinLabDomain.PendingImport] { [] }
    func savePendingImports(_ imports: [SpinLabDomain.PendingImport]) {}
    func loadArchivedRecords() -> [SpinLabDomain.ArchivedRecord] { [] }
    func saveArchivedRecords(_ records: [SpinLabDomain.ArchivedRecord]) {}
    func loadProjects() -> [SpinLabDomain.Project] { [] }
    func saveProjects(_ projects: [SpinLabDomain.Project]) {}
    func loadInteractionSnapshot() -> SpinLabInteractionSnapshot { snapshot }
    func saveInteractionSnapshot(_ snapshot: SpinLabInteractionSnapshot) {
        self.snapshot = snapshot
        saveCount += 1
    }
}

@inline(__always)
func wait(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

@inline(__always)
func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("ASSERTION FAILED: \(message)\n", stderr)
        exit(1)
    }
}

func testDebounceAndLatestWrite() {
    let persistence = MockPersistence()
    persistence.snapshot.selectedArea = .library
    let store = InteractionMemoryStore(persistence: persistence, saveDebounceInterval: 0.05)

    store.restore { _ in }
    store.markReady()
    store.captureIfReady { $0.selectedArea = .inbox }
    store.captureIfReady { $0.selectedArea = .workbench }
    wait(0.15)

    assertTrue(persistence.saveCount == 1, "debounce should coalesce saves")
    assertTrue(persistence.snapshot.selectedArea == .workbench, "latest state should be saved")
}

func testSectionIsolation() {
    let persistence = MockPersistence()
    persistence.snapshot.libraryView.isSearchWorkspaceExpanded = false
    persistence.snapshot.inboxWorkspaceByPendingID["p1"] = InboxPendingWorkspaceState(
        draft: PendingImportConfirmationDraft(
            batchName: "B",
            sampleName: "S",
            measurementName: "M",
            deviceName: "D",
            temperature: "300",
            selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
            newProjectName: ""
        ),
        editableFileContents: "abc",
        hasEditableFileContents: true
    )

    let baselineLibrary = persistence.snapshot.libraryView
    let baselineInbox = persistence.snapshot.inboxWorkspaceByPendingID

    let store = InteractionMemoryStore(persistence: persistence, saveDebounceInterval: 0.01)
    store.restore { _ in }
    store.markReady()
    store.updateValue(\.sidebar, to: SidebarInteractionState(isLibraryTreeExpanded: false, expandedPrefixes: []))
    wait(0.05)

    assertTrue(persistence.snapshot.sidebar.isLibraryTreeExpanded == false, "sidebar should update")
    assertTrue(persistence.snapshot.libraryView == baselineLibrary, "library section should remain unchanged")
    assertTrue(persistence.snapshot.inboxWorkspaceByPendingID == baselineInbox, "inbox section should remain unchanged")
}

@main
struct AcceptanceRunner {
    static func main() {
        testDebounceAndLatestWrite()
        testSectionIsolation()
        print("ACCEPTANCE_OK")
    }
}
SWIFT

swiftc \
  "$ROOT_DIR/Sources/SpinLabApp/App/InteractionMemoryStore.swift" \
  "$HARNESS_DIR/harness.swift" \
  -o "$HARNESS_DIR/acceptance_runner"

"$HARNESS_DIR/acceptance_runner" | rg "ACCEPTANCE_OK" >/dev/null

echo "[4/4] Acceptance checks passed"
