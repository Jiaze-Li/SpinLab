import CryptoKit
import Darwin
import Foundation

/// Process-lifetime write lease for the one Library this SpinLab process has open.
///
/// Only one local SpinLab process may write to a given Library (task 3). The lease is an
/// exclusive, non-blocking `flock` on a lock file that lives OUTSIDE the Library, keyed by the
/// canonical (symlink-resolved) Library path. The OS releases it when the process exits or
/// crashes, so there is no cleanup logic. This is not multi-user or multi-device coordination.
///
/// Fail-closed: if the lease cannot be taken for any reason, this process is read-only for that
/// Library. Writes inside a read-only Library are refused by `ensureWritable(_:)`, which the
/// persistence boundaries call before touching disk. Paths outside the current Library are
/// never affected.
final class LibraryWriteLease: @unchecked Sendable {
    static let shared = LibraryWriteLease()

    enum State: Equatable {
        /// No Library has been opened by this process yet.
        case none
        case writable
        case readOnly(reason: String)
    }

    static let readOnlyMessage = "这个 Library 已在另一个 SpinLab 中打开，当前为只读"

    private let lock = NSLock()
    /// Injectable for tests; nil resolves the per-user data directory.
    var lockDirectory: URL?
    private var canonicalRootPath: String?
    private var lockDescriptor: Int32 = -1
    private var currentState: State = .none

    /// `lockDirectory` is injectable for tests; nil resolves the per-user data directory.
    init(lockDirectory: URL? = nil) {
        self.lockDirectory = lockDirectory
    }

    deinit {
        if lockDescriptor >= 0 { close(lockDescriptor) }
    }

    var state: State {
        lock.lock(); defer { lock.unlock() }
        return currentState
    }

    var isReadOnly: Bool {
        if case .readOnly = state { return true }
        return false
    }

    /// Releases any previously held lease, then evaluates `rootURL`. Performs no write inside the
    /// Library and does not create the Library folder. Call before any Library write on open or
    /// when switching Library.
    @discardableResult
    func acquire(rootURL: URL?) -> State {
        lock.lock(); defer { lock.unlock() }
        releaseLocked()
        guard let rootURL else {
            currentState = .none
            return currentState
        }
        let canonical = Self.canonicalPath(of: rootURL)
        canonicalRootPath = canonical
        let directory = lockDirectory ?? Self.defaultLockDirectory()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            currentState = .readOnly(reason: "Could not prepare the lock folder: \(error.localizedDescription)")
            return currentState
        }
        let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        let lockPath = directory.appending(path: "library-\(digest.prefix(32)).lock").path
        let fd = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            currentState = .readOnly(reason: "Could not open the lock file: \(String(cString: strerror(errno)))")
            return currentState
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(fd)
            currentState = .readOnly(reason: code == EWOULDBLOCK || code == EAGAIN
                ? Self.readOnlyMessage
                : "Could not lock the Library: \(String(cString: strerror(code)))")
            return currentState
        }
        lockDescriptor = fd
        currentState = .writable
        return currentState
    }

    func release() {
        lock.lock(); defer { lock.unlock() }
        releaseLocked()
        canonicalRootPath = nil
        currentState = .none
    }

    private func releaseLocked() {
        if lockDescriptor >= 0 {
            flock(lockDescriptor, LOCK_UN)
            close(lockDescriptor)
            lockDescriptor = -1
        }
    }

    /// True only when this lease currently holds the writable lock for exactly `rootURL`.
    /// Stricter than `ensureWritable`, which also passes when no lease exists at all.
    func holdsWritableLease(for rootURL: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard case .writable = currentState, let root = canonicalRootPath else { return false }
        return root == Self.canonicalPath(of: rootURL)
    }

    /// Throws when `url` lies inside the Library this process holds read-only.
    func ensureWritable(_ url: URL) throws {
        let snapshot: (State, String?) = {
            lock.lock(); defer { lock.unlock() }
            return (currentState, canonicalRootPath)
        }()
        guard case let .readOnly(reason) = snapshot.0, let root = snapshot.1 else { return }
        let target = Self.canonicalPath(of: url)
        if target == root || target.hasPrefix(root + "/") {
            throw AppError.state(reason)
        }
    }

    /// For writes to files that belong to the Library's data but may live outside its folder
    /// (the Registry workbook can sit in a cloud folder): refused whenever this process is
    /// read-only for its Library, whatever the file's path.
    func ensureLibraryWritable() throws {
        if case let .readOnly(reason) = state { throw AppError.state(reason) }
    }

    /// Non-throwing form for Bool-returning writers.
    func allowsWrite(to url: URL) -> Bool {
        (try? ensureWritable(url)) != nil
    }

    /// Symlink-resolved absolute path. Resolves the deepest existing ancestor so paths that do
    /// not exist yet still compare equal to their real location.
    static func canonicalPath(of url: URL) -> String {
        var existing = url.standardizedFileURL
        var tail: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            tail.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        var resolved = existing.resolvingSymlinksInPath().standardizedFileURL
        for component in tail { resolved.append(path: component) }
        return resolved.path
    }

    static func defaultLockDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        return AppInternalPaths.userDataDirectory(in: appSupport).appending(path: "locks", directoryHint: .isDirectory)
    }
}
