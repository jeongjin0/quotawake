import Foundation

/// Streams a child process pipe into a size-capped buffer without blocking the
/// child on a full pipe: the readability handler keeps draining even after the
/// cap is hit, and `stop()` collects any remainder once the process has exited.
/// `stop()` must only be called after `waitUntilExit()`. The final drain is
/// deadline-bounded: a grandchild that escaped process-tree termination (or a
/// backgrounded descendant of a zero-exit run) can keep the write end open
/// past the direct child's exit, and an unbounded read-to-EOF here would hang
/// the caller until that stray process dies.
final class BoundedPipeCollector {
    let pipe = Pipe()

    private let lock = NSLock()
    private let limitBytes: Int
    private var data = Data()

    init(limitBytes: Int) {
        self.limitBytes = limitBytes
    }

    func start() {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                return
            }
            self?.append(chunk)
        }
    }

    func stop(drainDeadlineSeconds: TimeInterval = 2.0) {
        try? pipe.fileHandleForWriting.close()
        let reachedEOF = DispatchSemaphore(value: 0)
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                reachedEOF.signal()
            } else {
                self?.append(chunk)
            }
        }
        _ = reachedEOF.wait(timeout: .now() + drainDeadlineSeconds)
        pipe.fileHandleForReading.readabilityHandler = nil
        try? pipe.fileHandleForReading.close()
    }

    func string() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }

    private func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }

        let remainingCapacity = max(0, limitBytes - data.count)
        guard remainingCapacity > 0 else {
            return
        }
        data.append(chunk.prefix(remainingCapacity))
    }
}
