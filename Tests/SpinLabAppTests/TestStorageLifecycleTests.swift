import Foundation
import Testing
@testable import SpinLabApp

@Suite("Test storage lifecycle")
struct TestStorageLifecycleTests {
    private let fm = FileManager.default
    private let now = Date()

    private func withBase(_ body: (URL) throws -> Void) throws {
        let base = fm.temporaryDirectory.appendingPathComponent("SL-lifecycle-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        try body(base)
    }

    @discardableResult
    private func makeFolder(_ base: URL, pid: Int, entries: [String] = ["interaction_snapshot.json"], age: TimeInterval = 7200) throws -> URL {
        let dir = base.appendingPathComponent("com.spinlab.tests.\(pid)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for entry in entries {
            try Data("x".utf8).write(to: dir.appendingPathComponent(entry))
        }
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: dir.path)
        return dir
    }

    @Test("a dead process's old folder is reaped; live, young, own, unknown-content and look-alike folders are kept")
    func reapsOnlyProvenStaleFolders() throws {
        try withBase { base in
            let stale = try makeFolder(base, pid: 1001)
            let alive = try makeFolder(base, pid: 1002)
            let young = try makeFolder(base, pid: 1003, age: 60)
            let own = try makeFolder(base, pid: 1004)
            let foreign = try makeFolder(base, pid: 1005, entries: ["interaction_snapshot.json", "thesis.docx"])
            let lookAlike = base.appendingPathComponent("com.spinlab.tests.abc", isDirectory: true)
            try fm.createDirectory(at: lookAlike, withIntermediateDirectories: true)
            let real = base.appendingPathComponent("SpinLab", isDirectory: true)
            try fm.createDirectory(at: real, withIntermediateDirectories: true)
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-99999)], ofItemAtPath: real.path)
            let target = base.appendingPathComponent("target", isDirectory: true)
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            let link = base.appendingPathComponent("com.spinlab.tests.1006")
            try fm.createSymbolicLink(at: link, withDestinationURL: target)

            let result = TestStorageLifecycle.reapStale(
                in: base, currentPID: 1004, now: now, isProcessAlive: { $0 == 1002 }
            )

            #expect(result.removed == ["com.spinlab.tests.1001"])
            #expect(!fm.fileExists(atPath: stale.path))
            for kept in [alive, young, own, foreign, lookAlike, real, target] {
                #expect(fm.fileExists(atPath: kept.path), "\(kept.lastPathComponent) must be kept")
            }
            #expect((try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil)
        }
    }

    @Test("dry run reports without deleting")
    func dryRunDeletesNothing() throws {
        try withBase { base in
            let stale = try makeFolder(base, pid: 2001)
            let result = TestStorageLifecycle.reapStale(
                in: base, currentPID: 1, now: now, isProcessAlive: { _ in false }, dryRun: true
            )
            #expect(result.removed == ["com.spinlab.tests.2001"])
            #expect(fm.fileExists(atPath: stale.path))
        }
    }

    @Test("diagnostic-only folders: expired ones go, and only the newest fresh one is kept")
    func diagnosticLogsAreRetainedLonger() throws {
        try withBase { base in
            let logsOnly = try makeFolder(base, pid: 3001, entries: [], age: 7200)
            try fm.createDirectory(at: logsOnly.appendingPathComponent("logs"), withIntermediateDirectories: true)
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-7200)], ofItemAtPath: logsOnly.path)
            let tooOld = try makeFolder(base, pid: 3002, entries: [], age: 90000)
            try fm.createDirectory(at: tooOld.appendingPathComponent("logs"), withIntermediateDirectories: true)
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-90000)], ofItemAtPath: tooOld.path)

            let newer = try makeFolder(base, pid: 3003, entries: [], age: 600)
            try fm.createDirectory(at: newer.appendingPathComponent("logs"), withIntermediateDirectories: true)
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-600)], ofItemAtPath: newer.path)

            let result = TestStorageLifecycle.reapStale(
                in: base, currentPID: 1, now: now, isProcessAlive: { _ in false }
            )
            // Past retention goes; of the fresh diagnostic folders only the newest survives.
            #expect(result.removed == ["com.spinlab.tests.3001", "com.spinlab.tests.3002"])
            #expect(!fm.fileExists(atPath: logsOnly.path))
            #expect(fm.fileExists(atPath: newer.path))
        }
    }

    @Test("only strictly numeric pids are recognised")
    func parsesFolderNames() {
        #expect(TestStorageLifecycle.pid(fromFolderName: "com.spinlab.tests.123") == 123)
        #expect(TestStorageLifecycle.pid(fromFolderName: "com.spinlab.tests.") == nil)
        #expect(TestStorageLifecycle.pid(fromFolderName: "com.spinlab.tests.1/../x") == nil)
        #expect(TestStorageLifecycle.pid(fromFolderName: "SpinLab") == nil)
    }

    @Test("a folder of a live test process is never reaped, however old it is")
    func longRunningProcessFolderIsKept() throws {
        try withBase { base in
            let monthOld = try makeFolder(base, pid: 4001, age: 30 * 24 * 3600)
            let logsOnlyMonthOld = try makeFolder(base, pid: 4002, entries: [], age: 30 * 24 * 3600)
            try fm.createDirectory(at: logsOnlyMonthOld.appendingPathComponent("logs"), withIntermediateDirectories: true)
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-30 * 24 * 3600)], ofItemAtPath: logsOnlyMonthOld.path)

            let result = TestStorageLifecycle.reapStale(
                in: base, currentPID: 1, now: now, isProcessAlive: { _ in true }
            )
            #expect(result.removed.isEmpty)
            #expect(fm.fileExists(atPath: monthOld.path))
            #expect(fm.fileExists(atPath: logsOnlyMonthOld.path))
        }
    }

    @Test("every base this process used is cleaned at exit; other pids and unknown content are untouched")
    func exitCleansAllBases() throws {
        try withBase { baseA in
            try withBase { baseB in
                let own = Int(ProcessInfo.processInfo.processIdentifier)
                let a = try makeFolder(baseA, pid: own, entries: ["pending_imports.json", "projects.json"])
                let b = try makeFolder(baseB, pid: own, entries: ["interaction_snapshot.json"])
                let otherPID = try makeFolder(baseA, pid: own + 1)
                let bystander = baseA.appendingPathComponent("SpinLab", isDirectory: true) // look-alike of the real folder
                try fm.createDirectory(at: bystander, withIntermediateDirectories: true)
                let withError = try makeFolder(baseB.appendingPathComponent("nested", isDirectory: true), pid: own, entries: [])
                try fm.createDirectory(at: withError.appendingPathComponent("logs"), withIntermediateDirectories: true)
                try Data("{\"level\":\"error\"}".utf8).write(to: withError.appendingPathComponent("logs/app_events.log"))
                try Data("x".utf8).write(to: withError.appendingPathComponent("projects.json"))
                let foreignContent = try makeFolder(baseA.appendingPathComponent("other", isDirectory: true), pid: own, entries: ["thesis.docx"])

                TestStorageLifecycle.cleanUpOwnFolders(in: [
                    baseA, baseB, baseB.appendingPathComponent("nested"), baseA.appendingPathComponent("other")
                ])

                #expect(!fm.fileExists(atPath: a.path))
                #expect(!fm.fileExists(atPath: b.path))
                #expect(fm.fileExists(atPath: otherPID.path))
                #expect(fm.fileExists(atPath: bystander.path))
                #expect(fm.fileExists(atPath: foreignContent.path))
                // A run that logged an error keeps only its logs.
                #expect(fm.fileExists(atPath: withError.appendingPathComponent("logs/app_events.log").path))
                #expect(!fm.fileExists(atPath: withError.appendingPathComponent("projects.json").path))
            }
        }
    }

    @Test("pid liveness: reused system programs and dead pids are stale; test hosts and unknown state are not")
    func processLivenessDecision() throws {
        // Pure decision, including the fail-closed unknown case.
        #expect(TestStorageLifecycle.mayBeTestProcess(executablePath: nil))
        #expect(TestStorageLifecycle.mayBeTestProcess(executablePath: "/Applications/Xcode.app/Contents/SharedFrameworks/xctest"))
        #expect(TestStorageLifecycle.mayBeTestProcess(executablePath: "/usr/libexec/swift/pm/swiftpm-testing-helper"))
        #expect(TestStorageLifecycle.mayBeTestProcess(executablePath: "/Users/x/SpinLab.app/Contents/MacOS/SpinLab"))
        #expect(!TestStorageLifecycle.mayBeTestProcess(executablePath: "/usr/sbin/cfprefsd"))
        #expect(!TestStorageLifecycle.mayBeTestProcess(executablePath: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"))

        // Real processes: this test process is alive; a different live program holding a pid is a reused pid;
        // a pid that has exited is dead.
        #expect(TestStorageLifecycle.processIsAlive(ProcessInfo.processInfo.processIdentifier))
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        let childPID = child.processIdentifier
        #expect(!TestStorageLifecycle.processIsAlive(childPID))
        child.terminate()
        child.waitUntilExit()
        #expect(!TestStorageLifecycle.processIsAlive(childPID))
    }
}
