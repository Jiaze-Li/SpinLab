import Foundation
import Testing
@testable import SpinLabApp

/// Cross-suite isolation for tests that touch the process-global `RuleLoader` state
/// (configured Rules Book, internal paths, cache) — directly, via `SpinLabAppState`, or via
/// `RuleLoader.shared` / `SpinLabRuleProvider.shared` readers.
///
/// `.serialized` only orders tests *inside* one suite; different suites still run
/// concurrently and overwrite each other's `RuleLoader.configure(...)`. This trait makes every
/// test case of a tagged suite hold one process-wide async gate for its whole body (across
/// `await`s), and restores the complete loader state captured at entry when the test ends, so
/// no test can leak or restore another test's (possibly already deleted) configuration.
///
/// Apply as `@Suite("...", .rulesGlobalState)`. Re-entrant per task, so nested/sub suites that
/// are also tagged do not deadlock.
struct RulesGlobalStateTrait: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        guard testCase != nil, !RulesGlobalStateGate.isHeldByCurrentTask else {
            try await function()
            return
        }
        await RulesGlobalStateGate.shared.acquire()
        let savedBookPaths = RuleLoader.currentBookPaths
        let savedInternalPaths = RuleLoader.currentInternalPaths
        do {
            try await RulesGlobalStateGate.$isHeldByCurrentTask.withValue(true) {
                try await function()
            }
        } catch {
            RuleLoader.configure(bookPaths: savedBookPaths, internalPaths: savedInternalPaths)
            await RulesGlobalStateGate.shared.release()
            throw error
        }
        RuleLoader.configure(bookPaths: savedBookPaths, internalPaths: savedInternalPaths)
        await RulesGlobalStateGate.shared.release()
    }
}

extension Trait where Self == RulesGlobalStateTrait {
    static var rulesGlobalState: Self { Self() }
}

actor RulesGlobalStateGate {
    static let shared = RulesGlobalStateGate()
    @TaskLocal static var isHeldByCurrentTask = false

    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isHeld {
            isHeld = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
