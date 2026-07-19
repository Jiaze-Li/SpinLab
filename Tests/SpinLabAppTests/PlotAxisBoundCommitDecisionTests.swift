import Foundation
import Testing
@testable import SpinLabApp

/// Validator tests for `plotAxisBoundCommitDecision`, the pure commit-decision
/// function shared by every Cartesian XY and Dual Axis `PlotAxisBoundField`
/// leaf (see `PlotAxisBoundField.swift`). Supersedes the old
/// `AxisBoundCommitDecision`/`axisCommitDecision` suite pinned to the deleted
/// Cartesian-only `AxisBoundField`.
@Suite("plotAxisBoundCommitDecision")
struct PlotAxisBoundCommitDecisionTests {

    // MARK: - Bug regression: focusLost must not clear when value == placeholder

    @Test("currentValue=180 editText=180 => noOp")
    func doesNotClearWhenEditTextMatchesPlaceholderButOverrideIsActive() {
        // This was the bug: placeholder="180" when axisXMax auto=180 was overridden
        // to 180. commitIfDirty treated trimmed==placeholder as clear, emitting nil.
        let result = plotAxisBoundCommitDecision(trimmed: "180", currentValue: 180, role: .upper, effectiveOppositeBound: nil)
        #expect(result == .noOp)
    }

    // MARK: - Explicit clear: empty field

    @Test("currentValue=180 editText empty => clear")
    func emptyFieldWithActiveOverrideClearsToAuto() {
        let result = plotAxisBoundCommitDecision(trimmed: "", currentValue: 180, role: .upper, effectiveOppositeBound: nil)
        #expect(result == .clear)
    }

    @Test("currentValue=nil editText empty => noOp (nil -> nil never fires a callback)")
    func emptyFieldWithNoOverrideIsNoOp() {
        let result = plotAxisBoundCommitDecision(trimmed: "", currentValue: nil, role: .upper, effectiveOppositeBound: nil)
        #expect(result == .noOp)
    }

    // MARK: - Setting a value

    @Test("currentValue=nil editText=180 => setValue(180)")
    func newValueWithNoCurrentOverrideSetsValue() {
        let result = plotAxisBoundCommitDecision(trimmed: "180", currentValue: nil, role: .upper, effectiveOppositeBound: nil)
        #expect(result == .setValue(180))
    }

    @Test("currentValue=180 editText=200 => setValue(200)")
    func differentValueUpdatesOverride() {
        let result = plotAxisBoundCommitDecision(trimmed: "200", currentValue: 180, role: .upper, effectiveOppositeBound: nil)
        #expect(result == .setValue(200))
    }

    @Test("currentValue=nil editText matches auto placeholder => setValue, not noOp")
    func typingAutoValueWithNoOverrideSetsValue() {
        // User typed "187.5" which happens to equal the auto range —
        // this sets an explicit override to that value (not a clear).
        let result = plotAxisBoundCommitDecision(trimmed: "187.5", currentValue: nil, role: .upper, effectiveOppositeBound: nil)
        #expect(result == .setValue(187.5))
    }

    // MARK: - Invalid input

    @Test("invalid text => noOp")
    func invalidTextIsNoOp() {
        let result = plotAxisBoundCommitDecision(trimmed: "abc", currentValue: 180, role: .upper, effectiveOppositeBound: nil)
        #expect(result == .noOp)
    }

    @Test("invalid text with no current value => noOp")
    func invalidTextNoCurrentValueIsNoOp() {
        let result = plotAxisBoundCommitDecision(trimmed: "abc", currentValue: nil, role: .upper, effectiveOppositeBound: nil)
        #expect(result == .noOp)
    }

    // MARK: - Non-finite input: NaN, +Infinity, -Infinity

    @Test("nan => noOp")
    func nanIsRejected() {
        let result = plotAxisBoundCommitDecision(trimmed: "nan", currentValue: nil, role: .upper, effectiveOppositeBound: nil)
        #expect(result == .noOp)
    }

    @Test("inf => noOp")
    func positiveInfinityIsRejected() {
        let result = plotAxisBoundCommitDecision(trimmed: "inf", currentValue: nil, role: .upper, effectiveOppositeBound: nil)
        #expect(result == .noOp)
    }

    @Test("-inf => noOp")
    func negativeInfinityIsRejected() {
        let result = plotAxisBoundCommitDecision(trimmed: "-inf", currentValue: nil, role: .lower, effectiveOppositeBound: nil)
        #expect(result == .noOp)
    }

    // MARK: - Edge cases

    @Test("zero value explicit => setValue(0)")
    func zeroValueSetsOverride() {
        let result = plotAxisBoundCommitDecision(trimmed: "0", currentValue: nil, role: .upper, effectiveOppositeBound: nil)
        #expect(result == .setValue(0))
    }

    @Test("currentValue=0 editText=0 => noOp")
    func zeroMatchingCurrentIsNoOp() {
        let result = plotAxisBoundCommitDecision(trimmed: "0", currentValue: 0, role: .upper, effectiveOppositeBound: nil)
        #expect(result == .noOp)
    }

    @Test("negative value => setValue")
    func negativeValueSetsOverride() {
        let result = plotAxisBoundCommitDecision(trimmed: "-50", currentValue: nil, role: .lower, effectiveOppositeBound: nil)
        #expect(result == .setValue(-50))
    }

    @Test("negative bounds: lower -50 against effective opposite -10 => setValue(-50)")
    func negativeBoundsWithinCrossingCheckAccepted() {
        let result = plotAxisBoundCommitDecision(trimmed: "-50", currentValue: nil, role: .lower, effectiveOppositeBound: -10)
        #expect(result == .setValue(-50))
    }

    @Test("scientific notation => setValue")
    func scientificNotationSetsOverride() {
        let result = plotAxisBoundCommitDecision(trimmed: "1.5e3", currentValue: nil, role: .upper, effectiveOppositeBound: nil)
        #expect(result == .setValue(1500))
    }

    // MARK: - Effective-opposite-bound crossing

    @Test("lower field: submitted value below effective opposite (max) => setValue")
    func lowerBelowEffectiveOppositeAccepted() {
        let result = plotAxisBoundCommitDecision(trimmed: "5", currentValue: nil, role: .lower, effectiveOppositeBound: 10)
        #expect(result == .setValue(5))
    }

    @Test("lower field: submitted value equal to effective opposite (max) => noOp (not strictly below)")
    func lowerEqualToEffectiveOppositeRejected() {
        let result = plotAxisBoundCommitDecision(trimmed: "10", currentValue: nil, role: .lower, effectiveOppositeBound: 10)
        #expect(result == .noOp)
    }

    @Test("lower field: submitted value above effective opposite (max) => noOp")
    func lowerAboveEffectiveOppositeRejected() {
        let result = plotAxisBoundCommitDecision(trimmed: "15", currentValue: nil, role: .lower, effectiveOppositeBound: 10)
        #expect(result == .noOp)
    }

    @Test("upper field: submitted value above effective opposite (min) => setValue")
    func upperAboveEffectiveOppositeAccepted() {
        let result = plotAxisBoundCommitDecision(trimmed: "15", currentValue: nil, role: .upper, effectiveOppositeBound: 10)
        #expect(result == .setValue(15))
    }

    @Test("upper field: submitted value equal to effective opposite (min) => noOp")
    func upperEqualToEffectiveOppositeRejected() {
        let result = plotAxisBoundCommitDecision(trimmed: "10", currentValue: nil, role: .upper, effectiveOppositeBound: 10)
        #expect(result == .noOp)
    }

    @Test("upper field: submitted value below effective opposite (min) => noOp")
    func upperBelowEffectiveOppositeRejected() {
        let result = plotAxisBoundCommitDecision(trimmed: "5", currentValue: nil, role: .upper, effectiveOppositeBound: 10)
        #expect(result == .noOp)
    }

    @Test("effective opposite bound is whatever the caller resolved (override wins over auto)")
    func effectiveOppositeBoundReflectsCallerResolvedOverride() {
        // The field itself doesn't know about "override vs. auto" — it only sees
        // whatever effectiveOppositeBound the caller resolved (override ?? layout).
        // This documents that a caller passing an explicit override of 6 rejects
        // an 8, even if some other auto value would have allowed it.
        let result = plotAxisBoundCommitDecision(trimmed: "8", currentValue: nil, role: .lower, effectiveOppositeBound: 6)
        #expect(result == .noOp, "8 must be rejected against the caller-resolved effective opposite bound of 6")
    }

    @Test("nil effective opposite bound skips the crossing check entirely")
    func nilEffectiveOppositeBoundSkipsCrossingCheck() {
        let result = plotAxisBoundCommitDecision(trimmed: "1000000", currentValue: nil, role: .lower, effectiveOppositeBound: nil)
        #expect(result == .setValue(1_000_000))
    }
}
