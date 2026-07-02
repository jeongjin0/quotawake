import Foundation

public enum RunStatus: String, Codable, Equatable, Sendable {
    case sent
    case failed
    case timedOut = "timed_out"
    case skippedOverlap = "skipped_overlap"
    case skippedMissedWindow = "skipped_missed_window"
}

public struct RunLogEntry: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var eventId: String
    public var scheduledAt: Date
    public var startedAt: Date
    public var endedAt: Date
    public var tool: ToolKind
    public var commandPath: String
    public var status: RunStatus
    public var exitCode: Int?
    public var durationMs: Int
    public var timedOut: Bool
    public var stdoutSummary: String
    public var stderrSummary: String
    public var prompt: String
    public var errorSummary: String?
    public var decisionSource: QuotaReadinessDecisionSource?
    public var quotaConfidence: QuotaWindowConfidence?
    public var skipReason: String?

    public init(
        schemaVersion: Int = 1,
        eventId: String,
        scheduledAt: Date,
        startedAt: Date,
        endedAt: Date,
        tool: ToolKind,
        commandPath: String,
        status: RunStatus,
        exitCode: Int?,
        durationMs: Int,
        timedOut: Bool,
        stdoutSummary: String,
        stderrSummary: String,
        prompt: String,
        errorSummary: String? = nil,
        decisionSource: QuotaReadinessDecisionSource? = nil,
        quotaConfidence: QuotaWindowConfidence? = nil,
        skipReason: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.eventId = eventId
        self.scheduledAt = scheduledAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.tool = tool
        self.commandPath = commandPath
        self.status = status
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.timedOut = timedOut
        self.stdoutSummary = stdoutSummary
        self.stderrSummary = stderrSummary
        self.prompt = prompt
        self.errorSummary = errorSummary
        self.decisionSource = decisionSource
        self.quotaConfidence = quotaConfidence
        self.skipReason = skipReason
    }

    func sanitized() -> RunLogEntry {
        var copy = self
        copy.stdoutSummary = RunLogSanitizer.sanitize(stdoutSummary)
        copy.stderrSummary = RunLogSanitizer.sanitize(stderrSummary)
        if let errorSummary {
            copy.errorSummary = RunLogSanitizer.sanitize(errorSummary)
        }
        if let skipReason {
            copy.skipReason = RunLogSanitizer.sanitize(skipReason)
        }
        return copy
    }
}

public enum RunLogSanitizer {
    public static let summaryLimit = 4_096
    private static let token = "[REDACTED]"

    public static func sanitize(_ text: String) -> String {
        let redacted = SecretRedaction.stripANSI(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let sanitizedLine = SecretRedaction.applyPatterns(String(line), token: token)
                let lowered = sanitizedLine.lowercased()
                if !sanitizedLine.contains(token),
                   SecretRedaction.sensitiveLineKeywords.contains(where: { lowered.contains($0) }) {
                    return token
                }
                return sanitizedLine
            }
            .joined(separator: "\n")

        if redacted.count <= summaryLimit {
            return redacted
        }
        return String(redacted.prefix(summaryLimit))
    }
}

public final class RunLogStore {
    // Serializes appends across the poller and tool-runner paths; a torn
    // concurrent append would corrupt the shared JSONL files.
    private static let ioLock = NSLock()
    private var lastPrunedDay: String?

    private let paths: QuotaWakePaths
    private let fileManager: FileManager
    private let calendar: Calendar
    private let retentionDays: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        paths: QuotaWakePaths = QuotaWakePaths(),
        fileManager: FileManager = .default,
        calendar: Calendar = Calendar(identifier: .gregorian),
        retentionDays: Int = 30
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.calendar = calendar
        self.retentionDays = retentionDays
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
    }

    public func append(_ entry: RunLogEntry, pruneReferenceDate: Date? = nil) throws {
        Self.ioLock.lock()
        defer { Self.ioLock.unlock() }

        try paths.createDirectories(fileManager: fileManager)

        let sanitizedEntry = entry.sanitized()
        let fileURL = paths.logsDirectory.appendingPathComponent(
            "\(Self.fileDateString(for: sanitizedEntry.startedAt, calendar: calendar)).jsonl",
            isDirectory: false
        )
        var data = try encoder.encode(sanitizedEntry)
        data.append(0x0A)

        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forUpdating: fileURL)
            defer { try? handle.close() }
            // If the previous append was torn (crash/power loss mid-write),
            // start on a fresh line so only the torn line is lost, not this one.
            let end = try handle.seekToEnd()
            if end > 0 {
                try handle.seek(toOffset: end - 1)
                if try handle.read(upToCount: 1)?.first != 0x0A {
                    data.insert(0x0A, at: 0)
                }
                try handle.seekToEnd()
            }
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: fileURL, options: [.atomic])
        }

        let pruneDate = pruneReferenceDate ?? entry.startedAt
        let pruneDay = Self.fileDateString(for: pruneDate, calendar: calendar)
        if pruneDay != lastPrunedDay {
            try pruneLocked(now: pruneDate)
            lastPrunedDay = pruneDay
        }
    }

    public func readAll() throws -> [RunLogEntry] {
        Self.ioLock.lock()
        defer { Self.ioLock.unlock() }

        guard fileManager.fileExists(atPath: paths.logsDirectory.path) else {
            return []
        }

        let files = try fileManager.contentsOfDirectory(
            at: paths.logsDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "jsonl" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        // A single torn or corrupted line (crash mid-append, disk hiccup) must
        // not take down every readAll-dependent path for the whole retention
        // window, so undecodable lines are skipped instead of thrown.
        return files.flatMap { fileURL -> [RunLogEntry] in
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return []
            }
            return contents
                .split(separator: "\n")
                .compactMap { line in
                    try? decoder.decode(RunLogEntry.self, from: Data(line.utf8))
                }
        }
    }

    public func prune(now: Date) throws {
        Self.ioLock.lock()
        defer { Self.ioLock.unlock() }
        try pruneLocked(now: now)
    }

    private func pruneLocked(now: Date) throws {
        guard fileManager.fileExists(atPath: paths.logsDirectory.path) else {
            return
        }

        let keepStart = calendar.date(
            byAdding: .day,
            value: -(retentionDays - 1),
            to: calendar.startOfDay(for: now)
        ) ?? now

        let files = try fileManager.contentsOfDirectory(
            at: paths.logsDirectory,
            includingPropertiesForKeys: nil
        )

        for fileURL in files where fileURL.pathExtension == "jsonl" {
            guard let fileDate = Self.date(fromFileName: fileURL.deletingPathExtension().lastPathComponent, calendar: calendar) else {
                continue
            }
            if fileDate < keepStart {
                try fileManager.removeItem(at: fileURL)
            }
        }
    }

    private static func fileDateString(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func date(fromFileName fileName: String, calendar: Calendar) -> Date? {
        let parts = fileName.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
