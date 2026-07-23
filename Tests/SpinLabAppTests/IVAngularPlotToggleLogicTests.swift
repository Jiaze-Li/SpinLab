import Testing
@testable import SpinLabApp

@Suite("IVAngularPlotToggle disable logic")
struct IVAngularPlotToggleLogicTests {

    @Test("Disabled when data doesn't support angular plotting and toggle is off")
    func disabledWhenUnsupportedAndOff() {
        #expect(IVAngularPlotToggleLogic.isDisabled(isEnabled: false, isOn: false))
    }

    @Test("Stays interactive when already on, even if data no longer supports it")
    func interactiveWhenOnDespiteUnsupportedData() {
        #expect(!IVAngularPlotToggleLogic.isDisabled(isEnabled: false, isOn: true))
    }

    @Test("Interactive when data supports angular plotting, regardless of on/off state")
    func interactiveWhenSupported() {
        #expect(!IVAngularPlotToggleLogic.isDisabled(isEnabled: true, isOn: false))
        #expect(!IVAngularPlotToggleLogic.isDisabled(isEnabled: true, isOn: true))
    }
}
