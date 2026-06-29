import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum ProcessTreeTerminator {
    static func terminate(_ process: Process) {
        let rootPID = process.processIdentifier
        let descendants = descendantPIDs(of: rootPID)
        signal([rootPID] + descendants, SIGTERM)
        usleep(100_000)
        let remaining = ([rootPID] + descendants).filter(isAlive)
        signal(remaining, SIGKILL)
    }

    private static func signal(_ pids: [Int32], _ signal: Int32) {
        for pid in pids where pid > 0 {
            kill(pid, signal)
        }
    }

    private static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno != ESRCH
    }

    private static func descendantPIDs(of rootPID: Int32) -> [Int32] {
        let parentByPID = processParentMap()
        var descendants: [Int32] = []
        var queue = [rootPID]

        while let parent = queue.first {
            queue.removeFirst()
            let children = parentByPID.compactMap { pid, ppid in
                ppid == parent ? pid : nil
            }
            descendants.append(contentsOf: children)
            queue.append(contentsOf: children)
        }

        return descendants
    }

    private static func processParentMap() -> [Int32: Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid="]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return [:]
        }
        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return [:]
        }

        var parents: [Int32: Int32] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ")
            guard fields.count >= 2,
                  let pid = Int32(fields[0]),
                  let ppid = Int32(fields[1]) else {
                continue
            }
            parents[pid] = ppid
        }
        return parents
    }
}
