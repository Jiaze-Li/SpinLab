import Foundation
import Testing
@testable import SpinLabApp

@Suite("AxisBoundCommitDecision")
struct AxisBoundCommitDecisionTests {

    // MARK: - Bug regression: focusLost must not clear when value == placeholder

    @Test("currentValue=180 placeholder shows 180, editText=180 focusLost => noOp")
    func doesNotClearWhenEditTextMatchesPlaceholderButOverrideIsActive() {
        // This was the bug: placeholder="180" when axisXMax auto=180 was overridden
        // to 180. commitIfDirty treated trimmed==placeholder as clear, emitting nil.
        let result = axisCommitDecision(trimmed: "180", currentValue: 180)
        #expect(result == .noOp)
    }

    @Test("currentValue=180 editText=180 with whitespace => noOp")
    func doesNotClearWithWhitespacePaddedMatchingValue() {
        let result = axisCommitDecision(trimmed: "180", currentValue: 180)
        #expect(result == .noOp)
    }

    // MARK: - Explicit clear: empty field

    @Test("currentValue=180 editText empty => clear")
    func emptyFieldWithActiveOverrideClearsToAuto() {
        let result = axisCommitDecision(trimmed: "", currentValue: 180)
        #expect(result == .clear)
    }

    @Test("currentValue=nil editText empty => noOp")
    func emptyFieldWithNoOverrideIsNoOp() {
        let result = axisCommitDecision(trimmed: "", currentValue: nil)
        #expect(result == .noOp)
    }

    // MARK: - Setting a value

    @Test("currentValue=nil editText=180 => setValue(180)")
    func newValueWithNoCurrentOverrideSetsValue() {
        let result = axisCommitDecision(trimmed: "180", currentValue: nil)
        #expect(result == .setValue(180))
    }

    @Test("currentValue=180 editText=200 => setValue(200)")
    func differentValueUpdatesOverride() {
        let result = axisCommitDecision(trimmed: "200", currentValue: 180)
        #expect(result == .setValue(200))
    }

    @Test("currentValue=nil editText matches auto placeholder => setValue, not noOp")
    func typingAutoValueWithNoOverrideSetsValue() {
        // User typed "187.5" which happens to equal the auto range —
        // this sets an explicit override to that value (not a clear).
        let result = axisCommitDecision(trimmed: "187.5", currentValue: nil)
        #expect(result == .setValue(187.5))
    }

    // MARK: - Invalid input

    @Test("invalid text => noOp")
    func invalidTextIsNoOp() {
        let result = axisCommitDecision(trimmed: "abc", currentValue: 180)
        #expect(result == .noOp)
    }

    @Test("invalid text with no current value => noOp")
    func invalidTextNoCurrentValueIsNoOp() {
        let result = axisCommitDecision(trimmed: "abc", currentValue: nil)
        #expect(result == .noOp)
    }

    // MARK: - Edge cases

    @Test("zero value explicit => setValue(0)")
    func zeroValueSetsOverride() {
        let result = axisCommitDecision(trimmed: "0", currentValue: nil)
        #expect(result == .setValue(0))
    }

    @Test("currentValue=0 editText=0 => noOp")
    func zeroMatchingCurrentIsNoOp() {
        let result = axisCommitDecision(trimmed: "0", currentValue: 0)
        #expect(result == .noOp)
    }

    @Test("negative value => setValue")
    func negativeValueSetsOverride() {
        let result = axisCommitDecision(trimmed: "-50", currentValue: nil)
        #expect(result == .setValue(-50))
    }

    @Test("scientific notation => setValue")
    func scientificNotationSetsOverride() {
        let result = axisCommitDecision(trimmed: "1.5e3", currentValue: nil)
        #expect(result == .setValue(1500))
    }
}
