import Foundation

public struct ScheduledEvent: Equatable, Sendable {
    public let eventId: String
    public let scheduledAt: Date
    public let localDateKey: String
    public let time: ScheduleTime

    public init(eventId: String, scheduledAt: Date, localDateKey: String, time: ScheduleTime) {
        self.eventId = eventId
        self.scheduledAt = scheduledAt
        self.localDateKey = localDateKey
        self.time = time
    }

    public func idempotencyKey(for tool: ToolKind) -> String {
        "\(eventId)-\(tool.rawValue)"
    }
}

public enum ScheduleRunDecision: Equatable, Sendable {
    case run(ScheduledEvent)
    case skippedMissedWindow(ScheduledEvent)
    case none(nextRun: ScheduledEvent?)
}

public struct ScheduleEngine: Equatable, Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    public func nextRun(after now: Date, schedule: Schedule) -> ScheduledEvent? {
        guard !schedule.paused, hasRunnableSlots(schedule) else {
            return nil
        }

        let startOfToday = calendar.startOfDay(for: now)
        for dayOffset in 0...370 {
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday),
                  isWeekdayAllowed(dayStart, schedule: schedule) else {
                continue
            }

            let events = events(on: dayStart, schedule: schedule)
                .filter { $0.scheduledAt > now }
                .sorted { $0.scheduledAt < $1.scheduledAt }
            if let event = events.first {
                return event
            }
        }

        return nil
    }

    public func decision(now: Date, schedule: Schedule) -> ScheduleRunDecision {
        guard !schedule.paused, hasRunnableSlots(schedule) else {
            return .none(nextRun: nil)
        }

        guard let latest = latestScheduledEvent(beforeOrAt: now, schedule: schedule) else {
            return .none(nextRun: nextRun(after: now, schedule: schedule))
        }

        let graceSeconds = TimeInterval(max(0, schedule.missedRunGraceMinutes) * 60)
        let age = now.timeIntervalSince(latest.scheduledAt)
        if age <= graceSeconds {
            return .run(latest)
        }
        return .skippedMissedWindow(latest)
    }

    private func latestScheduledEvent(beforeOrAt now: Date, schedule: Schedule) -> ScheduledEvent? {
        let startOfToday = calendar.startOfDay(for: now)
        var latest: ScheduledEvent?

        for dayOffset in 0...7 {
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: startOfToday),
                  isWeekdayAllowed(dayStart, schedule: schedule) else {
                continue
            }

            for event in events(on: dayStart, schedule: schedule) where event.scheduledAt <= now {
                if latest == nil || event.scheduledAt > latest!.scheduledAt {
                    latest = event
                }
            }
        }

        return latest
    }

    private func events(on dayStart: Date, schedule: Schedule) -> [ScheduledEvent] {
        schedule.times.compactMap { time in
            event(on: dayStart, time: time)
        }
    }

    private func event(on dayStart: Date, time: ScheduleTime) -> ScheduledEvent? {
        var matching = DateComponents()
        matching.calendar = calendar
        matching.timeZone = calendar.timeZone
        matching.hour = time.hour
        matching.minute = time.minute
        matching.second = 0

        guard let scheduledAt = calendar.nextDate(
            after: dayStart.addingTimeInterval(-1),
            matching: matching,
            matchingPolicy: .strict,
            repeatedTimePolicy: .first,
            direction: .forward
        ), calendar.isDate(scheduledAt, inSameDayAs: dayStart) else {
            return nil
        }

        let dateKey = localDateKey(for: dayStart)
        let timeKey = String(format: "%02d%02d", time.hour, time.minute)
        return ScheduledEvent(
            eventId: "scheduled-\(dateKey)-\(timeKey)",
            scheduledAt: scheduledAt,
            localDateKey: dateKey,
            time: time
        )
    }

    private func hasRunnableSlots(_ schedule: Schedule) -> Bool {
        !schedule.weekdays.isEmpty && !schedule.times.isEmpty
    }

    private func isWeekdayAllowed(_ date: Date, schedule: Schedule) -> Bool {
        Set(schedule.weekdays).contains(calendar.component(.weekday, from: date))
    }

    private func localDateKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

public struct DueRunCoordinatorResult: Equatable, Sendable {
    public let decision: ScheduleRunDecision
    public let entries: [RunLogEntry]
    public let nextRun: ScheduledEvent?
}

public final class DueRunCoordinator {
    public typealias RunTool = (ToolKind, ScheduledEvent, String) throws -> RunLogEntry

    private let engine: ScheduleEngine
    private let logStore: RunLogStore
    private let runTool: RunTool

    public init(
        engine: ScheduleEngine = ScheduleEngine(),
        logStore: RunLogStore = RunLogStore(),
        runTool: @escaping RunTool
    ) {
        self.engine = engine
        self.logStore = logStore
        self.runTool = runTool
    }

    public func runDue(
        now: Date,
        schedule: Schedule,
        enabledTools: [ToolKind],
        prompt: String
    ) throws -> DueRunCoordinatorResult {
        let decision = engine.decision(now: now, schedule: schedule)
        let tools = uniqueTools(enabledTools)

        switch decision {
        case .run(let event):
            let entries = try tools.compactMap { tool -> RunLogEntry? in
                guard try !hasExistingLog(event: event, tool: tool) else {
                    return nil
                }
                return try runTool(tool, event, prompt)
            }
            return DueRunCoordinatorResult(
                decision: decision,
                entries: entries,
                nextRun: engine.nextRun(after: now, schedule: schedule)
            )
        case .skippedMissedWindow(let event):
            let entries = try tools.compactMap { tool -> RunLogEntry? in
                guard try !hasExistingLog(event: event, tool: tool) else {
                    return nil
                }
                let entry = RunLogEntry(
                    eventId: event.eventId,
                    scheduledAt: event.scheduledAt,
                    startedAt: now,
                    endedAt: now,
                    tool: tool,
                    commandPath: "",
                    status: .skippedMissedWindow,
                    exitCode: nil,
                    durationMs: 0,
                    timedOut: false,
                    stdoutSummary: "",
                    stderrSummary: "",
                    prompt: prompt,
                    errorSummary: "Missed schedule grace window"
                )
                try logStore.append(entry)
                return entry
            }
            return DueRunCoordinatorResult(
                decision: decision,
                entries: entries,
                nextRun: engine.nextRun(after: now, schedule: schedule)
            )
        case .none(let nextRun):
            return DueRunCoordinatorResult(decision: decision, entries: [], nextRun: nextRun)
        }
    }

    private func hasExistingLog(event: ScheduledEvent, tool: ToolKind) throws -> Bool {
        try logStore.readAll().contains { entry in
            entry.eventId == event.eventId && entry.tool == tool
        }
    }

    private func uniqueTools(_ tools: [ToolKind]) -> [ToolKind] {
        var seen = Set<ToolKind>()
        var result: [ToolKind] = []

        for tool in tools where seen.insert(tool).inserted {
            result.append(tool)
        }

        return result
    }
}
