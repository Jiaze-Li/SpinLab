import Foundation

/// Keeps the phone page (the web library) in step with the desktop: when the Rules Book changes in a
/// way the phone page shows (its option lists), the web library is published again on its own.
///
/// Several saves in a row become one publish (`delay` after the last one). A save that lands while a
/// publish is already running is not lost: one more publish runs as soon as that one ends, because
/// the running export may have read the rules before the save.
@MainActor
final class WebLibraryAutoPublisher {
    private let delay: Duration
    private let isPublishing: () -> Bool
    private let startPublish: () -> Void
    private let sleep: (Duration) async throws -> Void

    private var pending = false
    private var timerActive = false
    private var timer: Task<Void, Never>?

    init(
        delay: Duration = .seconds(5),
        isPublishing: @escaping () -> Bool,
        startPublish: @escaping () -> Void,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.delay = delay
        self.isPublishing = isPublishing
        self.startPublish = startPublish
        self.sleep = sleep
    }

    /// Call after a successful save that changes what the phone page shows.
    func requestPublish() {
        pending = true
        timer?.cancel()
        timerActive = true
        timer = Task { [weak self] in
            guard let self else { return }
            do { try await self.sleep(self.delay) } catch { return }
            self.timerActive = false
            self.fireIfDue()
        }
    }

    /// Call when any publish (automatic or the manual button) has ended.
    func publishFinished() {
        // A save that arrived while that publish was running is still owed one; if the wait timer is
        // still counting down it will take care of it.
        if pending, !timerActive { fireIfDue() }
    }

    private func fireIfDue() {
        guard pending else { return }
        guard !isPublishing() else { return } // publishFinished() will come back for it
        pending = false
        startPublish()
    }
}
