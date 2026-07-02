import Foundation

/// Streams a child process pipe into a size-capped buffer without blocking the
/// child on a full pipe: the readability handler keeps draining even after the
/// cap is hit, and `stop()` collects any remainder once the process has exited.
/// `stop()` must only be called after `waitUntilExit()` — it reads to EOF.
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

    func stop() {
        pipe.fileHandleForReading.readabilityHandler = nil
        try? pipe.fileHandleForWriting.close()
        let remainder = pipe.fileHandleForReading.readDataToEndOfFile()
        if !remainder.isEmpty {
            append(remainder)
        }
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
