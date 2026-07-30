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
    private let reachedEOF = DispatchSemaphore(value: 0)
    private var data = Data()

    init(limitBytes: Int) {
        self.limitBytes = limitBytes
    }

    func start() {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                self?.reachedEOF.signal()
                return
            }
            self?.append(chunk)
        }
    }

    func stop(drainDeadlineSeconds: TimeInterval = 2.0) {
        try? pipe.fileHandleForWriting.close()
        if reachedEOF.wait(timeout: .now() + drainDeadlineSeconds) == .success {
            try? pipe.fileHandleForReading.close()
        } else {
            // Deadline hit: a stray writer still holds the pipe. Do not
            // replace or clear the readability handler from this thread:
            // swift-corelibs-foundation can block that assignment until the
            // inherited writer closes. The handler clears itself on eventual
            // EOF and only weakly retains this collector.
        }
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
