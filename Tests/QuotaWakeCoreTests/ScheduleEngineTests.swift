import XCTest
@testable import QuotaWakeCore

final class ScheduleEngineTests: XCTestCase {
    private var tempDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in tempDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        tempDirectories.removeAll()
    }

    func testNextRunUsesMultipleTimesAndWeekdaySelection() throws {
        let calendar = Self.utcCalendar
        let engine = ScheduleEngine(calendar: calendar)
        let schedule = try makeSchedule(weekdays: [2], times: [(7, 30), (18, 0)])

        let morning = try XCTUnwrap(engine.nextRun(
            after: date(2026, 6, 29, 6, 0, calendar: calendar),
            schedule: schedule
        ))
        assertLocal(morning.scheduledAt, 2026, 6, 29, 7, 30, calendar: calendar)

        let evening = try XCTUnwrap(engine.nextRun(
            after: date(2026, 6, 29, 8, 0, calendar: calendar),
            schedule: schedule
        ))
        assertLocal(evening.scheduledAt, 2026, 6, 29, 18, 0, calendar: calendar)

        let nextWeek = try XCTUnwrap(engine.nextRun(
            after: date(2026, 6, 29, 18, 1, calendar: calendar),
            schedule: schedule
        ))
        assertLocal(nextWeek.scheduledAt, 2026, 7, 6, 7, 30, calendar: calendar)
    }

    func testDueCoordinatorRunsEnabledToolsOnceWithinGrace() throws {
        let calendar = Self.utcCalendar
        let paths = try makePaths()
        let store = RunLogStore(paths: paths, calendar: calendar)
        let engine = ScheduleEngine(calendar: calendar)
        let schedule = try makeSchedule(weekdays: [2], times: [(7, 30)])
        let now = date(2026, 6, 29, 7, 40, calendar: calendar)
        var executedTools: [ToolKind] = []

        let coordinator = DueRunCoordinator(engine: engine, logStore: store) { tool, event, prompt in
            executedTools.append(tool)
            let entry = Self.makeEntry(event: event, now: now, tool: tool, prompt: prompt)
            try store.append(entry)
            return entry
        }

        let result = try coordinator.runDue(
            now: now,
            schedule: schedule,
            enabledTools: [.claude, .codex],
            prompt: "hi"
        )

        XCTAssertEqual(executedTools, [.claude, .codex])
        XCTAssertEqual(result.entries.map(\.status), [.sent, .sent])
        XCTAssertEqual(try store.readAll().count, 2)

        let duplicate = try coordinator.runDue(
            now: now,
            schedule: schedule,
            enabledTools: [.claude, .codex],
            prompt: "hi"
        )
        XCTAssertTrue(duplicate.entries.isEmpty)
        XCTAssertEqual(executedTools, [.claude, .codex])
        XCTAssertEqual(try store.readAll().count, 2)
    }

    func testGraceBoundaryAndStaleMissedWindowLogging() throws {
        let calendar = Self.utcCalendar
        let paths = try makePaths()
        let store = RunLogStore(paths: paths, calendar: calendar)
        let engine = ScheduleEngine(calendar: calendar)
        let schedule = try makeSchedule(weekdays: [2], times: [(7, 30)], graceMinutes: 15)

        let boundaryDecision = engine.decision(
            now: date(2026, 6, 29, 7, 45, calendar: calendar),
            schedule: schedule
        )
        guard case .run = boundaryDecision else {
            return XCTFail("Expected 15-minute boundary to run")
        }

        let staleNow = date(2026, 6, 29, 7, 46, calendar: calendar)
        let staleDecision = engine.decision(now: staleNow, schedule: schedule)
        guard case .skippedMissedWindow = staleDecision else {
            return XCTFail("Expected stale missed window")
        }

        let coordinator = DueRunCoordinator(engine: engine, logStore: store) { _, _, _ in
            XCTFail("Stale missed window must not execute tools")
            throw TestError.unexpectedRun
        }

        let result = try coordinator.runDue(
            now: staleNow,
            schedule: schedule,
            enabledTools: [.claude, .codex],
            prompt: "hi"
        )
        XCTAssertEqual(result.entries.map(\.status), [.skippedMissedWindow, .skippedMissedWindow])
        XCTAssertEqual(try store.readAll().count, 2)

        let duplicate = try coordinator.runDue(
            now: staleNow,
            schedule: schedule,
            enabledTools: [.claude, .codex],
            prompt: "hi"
        )
        XCTAssertTrue(duplicate.entries.isEmpty)
        XCTAssertEqual(try store.readAll().count, 2)
    }

    func testPausedScheduleSuppressesNextRunAndDueRuns() throws {
        let calendar = Self.utcCalendar
        let paths = try makePaths()
        let store = RunLogStore(paths: paths, calendar: calendar)
        let engine = ScheduleEngine(calendar: calendar)
        let schedule = try makeSchedule(paused: true, weekdays: [2], times: [(7, 30)])
        let coordinator = DueRunCoordinator(engine: engine, logStore: store) { _, _, _ in
            XCTFail("Paused schedule must not execute tools")
            throw TestError.unexpectedRun
        }

        XCTAssertNil(engine.nextRun(after: date(2026, 6, 29, 6, 0, calendar: calendar), schedule: schedule))
        let result = try coordinator.runDue(
            now: date(2026, 6, 29, 7, 30, calendar: calendar),
            schedule: schedule,
            enabledTools: [.claude],
            prompt: "hi"
        )

        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(try store.readAll(), [])
    }

    func testSpringForwardNonexistentTimeIsSkipped() throws {
        let calendar = Self.newYorkCalendar
        let engine = ScheduleEngine(calendar: calendar)
        let schedule = try makeSchedule(weekdays: [1], times: [(2, 30)])

        let next = try XCTUnwrap(engine.nextRun(
            after: date(2026, 3, 8, 0, 0, calendar: calendar),
            schedule: schedule
        ))

        assertLocal(next.scheduledAt, 2026, 3, 15, 2, 30, calendar: calendar)
    }

    func testFallBackRepeatedTimeUsesOneLocalEventIdAndHistoryPreventsDuplicate() throws {
        let calendar = Self.newYorkCalendar
        let paths = try makePaths()
        let store = RunLogStore(paths: paths, calendar: calendar)
        let engine = ScheduleEngine(calendar: calendar)
        let schedule = try makeSchedule(weekdays: [1], times: [(1, 30)])
        let firstNow = date(2026, 11, 1, 0, 30, calendar: calendar)
        let event = try XCTUnwrap(engine.nextRun(after: firstNow, schedule: schedule))
        XCTAssertEqual(event.eventId, "scheduled-2026-11-01-0130")

        var runCount = 0
        let coordinator = DueRunCoordinator(engine: engine, logStore: store) { tool, event, prompt in
            runCount += 1
            let entry = Self.makeEntry(event: event, now: event.scheduledAt, tool: tool, prompt: prompt)
            try store.append(entry)
            return entry
        }

        _ = try coordinator.runDue(
            now: event.scheduledAt.addingTimeInterval(60),
            schedule: schedule,
            enabledTools: [.claude],
            prompt: "hi"
        )
        _ = try coordinator.runDue(
            now: event.scheduledAt.addingTimeInterval(3_900),
            schedule: schedule,
            enabledTools: [.claude],
            prompt: "hi"
        )

        XCTAssertEqual(runCount, 1)
        XCTAssertEqual(try store.readAll().count, 1)
    }

    private func makeSchedule(
        paused: Bool = false,
        weekdays: [Int],
        times: [(Int, Int)],
        graceMinutes: Int = 15
    ) throws -> Schedule {
        Schedule(
            paused: paused,
            weekdays: weekdays,
            times: try times.map { try ScheduleTime(hour: $0.0, minute: $0.1) },
            missedRunGraceMinutes: graceMinutes
        )
    }

    private func makePaths() throws -> QuotaWakePaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaWakeScheduleEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        tempDirectories.append(root)
        return QuotaWakePaths(applicationSupportDirectory: root)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: 0
        ))!
    }

    private func assertLocal(
        _ date: Date,
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual(components.year, year, file: file, line: line)
        XCTAssertEqual(components.month, month, file: file, line: line)
        XCTAssertEqual(components.day, day, file: file, line: line)
        XCTAssertEqual(components.hour, hour, file: file, line: line)
        XCTAssertEqual(components.minute, minute, file: file, line: line)
    }

    private static func makeEntry(
        event: ScheduledEvent,
        now: Date,
        tool: ToolKind,
        prompt: String
    ) -> RunLogEntry {
        RunLogEntry(
            eventId: event.eventId,
            scheduledAt: event.scheduledAt,
            startedAt: now,
            endedAt: now.addingTimeInterval(1),
            tool: tool,
            commandPath: "/fake/\(tool.rawValue)",
            status: .sent,
            exitCode: 0,
            durationMs: 1_000,
            timedOut: false,
            stdoutSummary: "ok",
            stderrSummary: "",
            prompt: prompt
        )
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static var newYorkCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private enum TestError: Error {
        case unexpectedRun
    }
}
