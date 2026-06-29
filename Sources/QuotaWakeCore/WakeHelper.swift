import Foundation

public struct WakeHelperConfiguration: Equatable, Sendable {
    public let uid: Int
    public let label: String
    public let requestFile: URL
    public let stagedDirectory: URL
    public let stagedHelper: URL
    public let stagedPlist: URL
    public let rootHelper: URL
    public let rootPlist: URL
    public let rootLastWakeFile: URL
    public let logDirectory: URL
    public let logFile: URL

    public init(uid: Int, paths: QuotaWakePaths = QuotaWakePaths()) {
        self.uid = uid
        self.label = "com.jeongjin.quotawake.wake-helper.\(uid)"

        let wakeDirectory = paths.applicationSupportDirectory.appendingPathComponent("Wake", isDirectory: true)
        self.requestFile = wakeDirectory.appendingPathComponent("request.txt", isDirectory: false)
        self.stagedDirectory = wakeDirectory.appendingPathComponent("Staged", isDirectory: true)
        self.stagedHelper = stagedDirectory.appendingPathComponent("quotawake-wake-helper-\(uid).sh", isDirectory: false)
        self.stagedPlist = stagedDirectory.appendingPathComponent("\(label).plist", isDirectory: false)

        self.rootHelper = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/quotawake-wake-helper-\(uid).sh", isDirectory: false)
        self.rootPlist = URL(fileURLWithPath: "/Library/LaunchDaemons/\(label).plist", isDirectory: false)
        self.rootLastWakeFile = URL(fileURLWithPath: "/Library/Application Support/QuotaWake/wake-helper-\(uid).last", isDirectory: false)
        self.logDirectory = URL(fileURLWithPath: "/var/log/quotawake", isDirectory: true)
        self.logFile = logDirectory.appendingPathComponent("\(label).log", isDirectory: false)
    }
}

public final class WakeRequestStore {
    private let requestFile: URL
    private let fileManager: FileManager
    private let calendar: Calendar

    public init(requestFile: URL, calendar: Calendar = .autoupdatingCurrent, fileManager: FileManager = .default) {
        self.requestFile = requestFile
        self.calendar = calendar
        self.fileManager = fileManager
    }

    @discardableResult
    public func writeWakeRequest(at date: Date) throws -> String {
        let timestamp = Self.timestampString(for: date, calendar: calendar)
        try write(timestamp)
        return timestamp
    }

    public func clearWakeRequest() throws {
        try write("")
    }

    public static func timestampString(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MM/dd/yy HH:mm:ss"
        return formatter.string(from: date)
    }

    public static func isValidTimestamp(_ timestamp: String) -> Bool {
        let pattern = #"^\d{2}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}$"#
        return timestamp.range(of: pattern, options: .regularExpression) != nil
    }

    private func write(_ text: String) throws {
        try fileManager.createDirectory(
            at: requestFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: requestFile, atomically: true, encoding: .utf8)
    }
}

public struct WakeHelperRenderer: Equatable, Sendable {
    public init() {}

    public func renderLaunchDaemonPlist(configuration: WakeHelperConfiguration) throws -> Data {
        let plist: [String: Any] = [
            "Label": configuration.label,
            "ProgramArguments": [configuration.rootHelper.path],
            "RunAtLoad": false,
            "WatchPaths": [configuration.requestFile.path],
            "StandardOutPath": configuration.logFile.path,
            "StandardErrorPath": configuration.logFile.path
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
    }

    public func renderHelperScript(configuration: WakeHelperConfiguration) -> String {
        """
        #!/bin/sh
        set -eu

        REQUEST_FILE=\(Self.shellQuote(configuration.requestFile.path))
        LAST_FILE=\(Self.shellQuote(configuration.rootLastWakeFile.path))
        LOG_FILE=\(Self.shellQuote(configuration.logFile.path))

        log() {
          printf '%s %s\\n' "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" >> "$LOG_FILE"
        }

        valid_timestamp() {
          case "$1" in
            [0-9][0-9]/[0-9][0-9]/[0-9][0-9]\\ [0-9][0-9]:[0-9][0-9]:[0-9][0-9]) return 0 ;;
            *) return 1 ;;
          esac
        }

        if [ ! -f "$REQUEST_FILE" ]; then
          exit 0
        fi

        WHEN="$(/usr/bin/tr -d '\\r\\n' < "$REQUEST_FILE")"
        OLD=""
        if [ -f "$LAST_FILE" ]; then
          OLD="$(/usr/bin/tr -d '\\r\\n' < "$LAST_FILE")"
        fi

        if [ -n "$OLD" ]; then
          if valid_timestamp "$OLD"; then
            /usr/bin/pmset schedule cancel wake "$OLD" || true
          else
            log "ignored invalid previous wake"
          fi
        fi

        if [ -z "$WHEN" ]; then
          : > "$LAST_FILE"
          exit 0
        fi

        if valid_timestamp "$WHEN"; then
          /usr/bin/pmset schedule wake "$WHEN"
          printf '%s\\n' "$WHEN" > "$LAST_FILE"
        else
          log "ignored invalid wake request"
        fi
        """
    }

    public static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
