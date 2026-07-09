import Testing
@testable import SpinLabApp

@Suite("ThreeOmegaWorkspaceStore — RAHE method tab coverage")
@MainActor
struct ThreeOmegaRAHEMethodTabCoverageTests {

    // MARK: - activeRAHEMethod

    @Test("activeRAHEMethod returns nil for non-RAHE tab")
    func nonRAHETab() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.tabs.activeTab = .fieldSweep1omega
        #expect(store.activeRAHEMethod == nil)
    }

    @Test("activeRAHEMethod returns rahe1omegaVsDeviceMethod for rahe1omegaVsDevice")
    func rahe1VsDevice() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.rahe1omegaVsDeviceMethod = .window
        store.tabs.activeTab = .rahe1omegaVsDevice
        #expect(store.activeRAHEMethod == .window)
    }

    @Test("activeRAHEMethod returns rahe3omegaVsDeviceMethod for rahe3omegaVsDevice")
    func rahe3VsDevice() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.rahe3omegaVsDeviceMethod = .window
        store.tabs.activeTab = .rahe3omegaVsDevice
        #expect(store.activeRAHEMethod == .window)
    }

    // MARK: - updateRAHEMethod dispatches to correct backing property

    @Test("updateRAHEMethod on rahe1omegaVsDevice updates rahe1omegaVsDeviceMethod")
    func updateRAHE1Device() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.tabs.activeTab = .rahe1omegaVsDevice
        store.updateRAHEMethod(.window)
        #expect(store.rahe1omegaVsDeviceMethod == .window)
        #expect(store.rahe1omegaMethod == .highField, "other methods must not be affected")
    }

    @Test("updateRAHEMethod on rahe3omegaVsDevice updates rahe3omegaVsDeviceMethod")
    func updateRAHE3Device() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.tabs.activeTab = .rahe3omegaVsDevice
        store.updateRAHEMethod(.window)
        #expect(store.rahe3omegaVsDeviceMethod == .window)
        #expect(store.rahe3omegaMethod == .highField, "other methods must not be affected")
    }

    @Test("updateRAHEMethod is no-op when method unchanged")
    func updateRAHENoop() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.tabs.activeTab = .rahe1omegaVsDevice
        store.rahe1omegaVsDeviceMethod = .highField
        store.updateRAHEMethod(.highField)
        #expect(store.rahe1omegaVsDeviceMethod == .highField)
    }

    @Test("updateRAHEMethod is no-op on non-RAHE tab")
    func updateRAHENonRaheTab() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.tabs.activeTab = .scaling
        store.updateRAHEMethod(.window)
        #expect(store.rahe1omegaMethod == .highField)
        #expect(store.rahe3omegaMethod == .highField)
        #expect(store.rahe1omegaVsDeviceMethod == .highField)
        #expect(store.rahe3omegaVsDeviceMethod == .highField)
    }

    // MARK: - Stable key coverage

    @Test("device RAHE tabs have distinct stable keys")
    func distinctStableKeys() {
        let keys = [
            ThreeOmegaWorkbenchTab.rahe1omegaVsDevice.stableKey,
            ThreeOmegaWorkbenchTab.rahe3omegaVsDevice.stableKey,
        ]
        #expect(Set(keys).count == 2, "each device RAHE tab must have a unique stable key")
    }

    @Test("new tabs have expected stable keys")
    func expectedStableKeys() {
        #expect(ThreeOmegaWorkbenchTab.rahe1omegaVsDevice.stableKey == "rahe1omegaVsDevice")
        #expect(ThreeOmegaWorkbenchTab.rahe3omegaVsDevice.stableKey == "rahe3omegaVsDevice")
    }
}
