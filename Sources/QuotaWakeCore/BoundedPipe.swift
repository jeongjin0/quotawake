import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Streams a child process pipe into a size-capped buffer without blocking the
/// child on a full pipe: the readability handler keeps draining even after the
/// cap is hit, and `stop()` collects any remainder once the process has exited.
/// `stop()` must only be called after `waitUntilExit()`. The final drain is
/// deadline-bounded: a grandchild that escaped process-tree termination (or a
/// backgrounded descendant of a zero-exit run) can keep the write end open
/// past the direct child's exit, and an unbounded read-to-EOF here would hang
/// the caller until that stray process dies.
final class BoundedPipeCollector: @unchecked Sendable {
    let pipe = Pipe()

    private let lock = NSLock()
    private let limitBytes: Int
    private let reachedEOF = DispatchSemaphore(value: 0)
    private var data = Data()
    #if !os(Windows)
    private let readerQueue = DispatchQueue(label: "com.jeongjin.quotawake.bounded-pipe", qos: .utility)
    private var stopRequested = false
    #endif

    init(limitBytes: Int) {
        self.limitBytes = limitBytes
    }

    func start() {
        #if os(Windows)
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                self?.reachedEOF.signal()
                return
            }
            self?.append(chunk)
        }
        #else
        readerQueue.async { [self] in
            readUntilEOFOrCancellation()
            reachedEOF.signal()
        }
        #endif
    }

    func stop(drainDeadlineSeconds: TimeInterval = 2.0) {
        try? pipe.fileHandleForWriting.close()
        if reachedEOF.wait(timeout: .now() + drainDeadlineSeconds) == .success {
            #if os(Windows)
            pipe.fileHandleForReading.readabilityHandler = nil
            #endif
            try? pipe.fileHandleForReading.close()
        } else {
            // Deadline hit: a stray writer still holds the pipe. The POSIX
            // reader checks this flag between 50ms poll intervals, avoiding
            // FileHandle handler replacement while a read is in flight.
            #if os(Windows)
            pipe.fileHandleForReading.readabilityHandler = nil
            #else
            requestStop()
            _ = reachedEOF.wait(timeout: .now() + .milliseconds(250))
            #endif
            try? pipe.fileHandleForReading.close()
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

    #if !os(Windows)
    private func readUntilEOFOrCancellation() {
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        let existingFlags = fcntl(descriptor, F_GETFL)
        if existingFlags >= 0 {
            _ = fcntl(descriptor, F_SETFL, existingFlags | O_NONBLOCK)
        }

        var pollDescriptor = pollfd(
            fd: descriptor,
            events: Int16(POLLIN | POLLHUP | POLLERR),
            revents: 0
        )
        while !isStopRequested() {
            pollDescriptor.revents = 0
            let result = poll(&pollDescriptor, 1, 50)
            if result < 0 {
                if errno == EINTR {
                    continue
                }
                return
            }
            if result == 0 {
                continue
            }

            let reachedEnd = drainAvailable(descriptor)
            if reachedEnd || (pollDescriptor.revents & Int16(POLLHUP | POLLERR)) != 0 {
                return
            }
        }
    }

    private func drainAvailable(_ descriptor: Int32) -> Bool {
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes -> Int in
                guard let baseAddress = bytes.baseAddress else { return 0 }
                return systemRead(descriptor, baseAddress, bytes.count)
            }
            if count > 0 {
                append(Data(buffer.prefix(count)))
                continue
            }
            if count == 0 {
                return true
            }
            if errno == EINTR {
                continue
            }
            if errno == EAGAIN || errno == EWOULDBLOCK {
                return false
            }
            return true
        }
    }

    private func systemRead(_ descriptor: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int {
        #if canImport(Darwin)
        return Darwin.read(descriptor, buffer, count)
        #else
        return Glibc.read(descriptor, buffer, count)
        #endif
    }

    private func requestStop() {
        lock.lock()
        stopRequested = true
        lock.unlock()
    }

    private func isStopRequested() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopRequested
    }
    #endif
}
