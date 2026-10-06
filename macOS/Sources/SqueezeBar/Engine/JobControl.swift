import Foundation

/// Pause/cancel switch shared between the UI and a running encode. Safe to use from any thread.
public final class JobControl: @unchecked Sendable {
    private let condition = NSCondition()
    private var paused = false
    private var cancelled = false

    public var isPaused: Bool {
        condition.lock()
        defer { condition.unlock() }
        return paused
    }

    public var isCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return cancelled
    }

    public func pause() {
        condition.lock()
        if !cancelled { paused = true }
        condition.unlock()
    }

    public func resume() {
        condition.lock()
        paused = false
        condition.broadcast()
        condition.unlock()
    }

    public func cancel() {
        condition.lock()
        cancelled = true
        paused = false
        condition.broadcast()
        condition.unlock()
    }

    /// Blocks the calling thread while paused. Returns false once the job has been cancelled, meaning the caller should stop.
    /// Only call this from encode queues, never from the main thread or the engine actor.
    public func checkpoint() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        while paused && !cancelled {
            condition.wait()
        }
        return !cancelled
    }
}

/// Lookup of per-job controls so the UI can pause or cancel a job without going through the engine actor.
public final class JobControlRegistry: @unchecked Sendable {
    public static let shared = JobControlRegistry()

    private let lock = NSLock()
    private var controls: [UUID: JobControl] = [:]

    private init() {}

    public func control(for id: UUID) -> JobControl {
        lock.lock()
        defer { lock.unlock() }
        if let existing = controls[id] { return existing }
        let created = JobControl()
        controls[id] = created
        return created
    }

    public func remove(_ id: UUID) {
        lock.lock()
        controls.removeValue(forKey: id)
        lock.unlock()
    }
}
