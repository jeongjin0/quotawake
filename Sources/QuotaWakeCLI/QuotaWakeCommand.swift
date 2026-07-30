import ArgumentParser
import Foundation
import QuotaWakeCore

@main
public struct QuotaWakeCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "quotawake",
        abstract: "Reset-aware session readiness for Claude Code and Codex.",
        discussion: "QuotaWake observes local usage-window signals and invokes only installed official CLIs. It does not call provider HTTP APIs.",
        version: QuotaWakeCore.currentVersion,
        subcommands: [
            Setup.self,
            Doctor.self,
            Status.self,
            Observe.self,
            Send.self,
            Daemon.self,
            Service.self,
            Config.self,
            Logs.self
        ],
        defaultSubcommand: Status.self
    )

    public init() {}
}

public struct Setup: ParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: "Detect providers and write a local QuotaWake configuration."
    )

    @Option(help: "Comma-separated providers to require: claude,codex. By default, enable every detected provider.")
    var providers: String?

    @Option(help: "Override the Claude CLI path.")
    var claudePath: String?

    @Option(help: "Override the Codex CLI path.")
    var codexPath: String?

    @Flag(help: "Enable automatic readiness; service installation is still a separate step.")
    var enableBackground = false

    @Flag(help: "Print machine-readable JSON.")
    var json = false

    public init() {}

    public func run() throws {
        let context = QuotaWakeCLIContext()
        let selected = try providers.map { try parseProviderSet($0, context: context) }
        let snapshot = try context.setup(
            providers: selected,
            claudePath: claudePath,
            codexPath: codexPath,
            enableBackground: enableBackground
        )
        if json {
            print(try CLIJSON.encode(snapshot))
        } else {
            print("QuotaWake setup complete")
            printStatus(snapshot)
            if !snapshot.backgroundReadinessEnabled {
                print("Next: quotawake service install")
            }
        }
    }
}

public struct Doctor: ParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: "Check provider CLIs, configuration, and automatic-readiness prerequisites."
    )

    @Flag(help: "Print machine-readable JSON.")
    var json = false

    public init() {}

    public func run() throws {
        let snapshot = try QuotaWakeCLIContext().doctor()
        if json {
            print(try CLIJSON.encode(snapshot))
        } else {
            print(snapshot.ready ? "QuotaWake is ready" : "QuotaWake needs attention")
            for provider in snapshot.providers {
                printProvider(provider)
            }
            for problem in snapshot.problems {
                print("- \(problem)")
            }
            print("Data: \(snapshot.configDirectory)")
        }
        if !snapshot.ready {
            throw ExitCode.failure
        }
    }
}

public struct Status: ParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: "Show configuration, local provider, and quota-window state."
    )

    @Flag(help: "Print machine-readable JSON.")
    var json = false

    public init() {}

    public func run() throws {
        let snapshot = try QuotaWakeCLIContext().status()
        if json {
            print(try CLIJSON.encode(snapshot))
        } else {
            printStatus(snapshot)
        }
    }
}

public struct Observe: ParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: "Read local quota-window signals without sending a readiness prompt."
    )

    @Argument(help: "Optional provider: claude or codex")
    var provider: String?

    @Flag(help: "Print machine-readable JSON.")
    var json = false

    public init() {}

    public func run() throws {
        let context = QuotaWakeCLIContext()
        let snapshots = try context.observe(provider: try context.parseProvider(provider))
        if json {
            print(try CLIJSON.encode(snapshots))
        } else {
            for snapshot in snapshots {
                printProvider(snapshot)
            }
        }
    }
}

public struct Send: ParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: "Send a readiness prompt now. This may use the current provider window."
    )

    @Argument(help: "Optional provider: claude or codex")
    var provider: String?

    @Flag(help: "Print machine-readable JSON.")
    var json = false

    public init() {}

    public func run() throws {
        let context = QuotaWakeCLIContext()
        let snapshots = try context.send(provider: try context.parseProvider(provider))
        if json {
            print(try CLIJSON.encode(snapshots))
        } else {
            for snapshot in snapshots {
                print("\(snapshot.provider): \(snapshot.status) (\(snapshot.durationMs) ms)")
                if !snapshot.summary.isEmpty {
                    print("  \(snapshot.summary)")
                }
            }
        }
        if snapshots.contains(where: { $0.status != RunStatus.sent.rawValue }) {
            throw ExitCode.failure
        }
    }
}

public struct Daemon: ParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: "Run the reset-aware scheduler in the foreground."
    )

    @Option(help: "Polling interval in seconds.")
    var interval = 60

    @Flag(help: "Run one poll pass and exit.")
    var once = false

    public init() {}

    public func validate() throws {
        if interval < 1 {
            throw ValidationError("--interval must be at least 1 second")
        }
    }

    public func run() throws {
        let context = QuotaWakeCLIContext()
        let status = try context.status()
        guard status.setupComplete else {
            throw ValidationError("setup is incomplete; run 'quotawake setup'")
        }
        guard status.backgroundReadinessEnabled else {
            throw QuotaWakeCLIError.backgroundReadinessDisabled
        }

        let lease = DaemonLease(pidFile: context.paths.daemonPIDFile)
        try lease.acquire()
        defer { lease.release() }

        let poller = context.makePoller()
        repeat {
            try poller.tick()
            try poller.observeIfStale(maxAgeSeconds: 55)
            if !once {
                Thread.sleep(forTimeInterval: TimeInterval(interval))
            }
        } while !once
    }
}

public struct Service: ParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: "Manage the per-user background daemon.",
        subcommands: [
            ServiceInstall.self,
            ServiceUninstall.self,
            ServiceStart.self,
            ServiceStop.self,
            ServiceStatus.self
        ],
        defaultSubcommand: ServiceStatus.self
    )

    public init() {}
}

public struct ServiceInstall: ParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "install", abstract: "Install and start the per-user daemon.")

    @Flag(help: "Print machine-readable JSON.")
    var json = false

    public init() {}

    public func run() throws {
        let context = QuotaWakeCLIContext()
        let previousSettings = try context.settingsStore.load()
        guard previousSettings.firstRunCompleted else {
            throw ValidationError("setup is incomplete; run 'quotawake setup' first")
        }
        _ = try context.updateConfiguration(key: "background.enabled", value: "true")
        do {
            let snapshot = try PlatformServiceManager(paths: context.paths).install()
            printService(snapshot, json: json)
        } catch {
            try? context.settingsStore.save(previousSettings)
            throw error
        }
    }
}

public struct ServiceUninstall: ParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "uninstall", abstract: "Stop and remove the per-user daemon.")

    @Flag(help: "Print machine-readable JSON.")
    var json = false

    public init() {}

    public func run() throws {
        let context = QuotaWakeCLIContext()
        let snapshot = try PlatformServiceManager(paths: context.paths).uninstall()
        _ = try context.updateConfiguration(key: "background.enabled", value: "false")
        printService(snapshot, json: json)
    }
}

public struct ServiceStart: ParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "start", abstract: "Start the installed per-user daemon.")

    @Flag(help: "Print machine-readable JSON.")
    var json = false

    public init() {}

    public func run() throws {
        printService(try PlatformServiceManager().start(), json: json)
    }
}

public struct ServiceStop: ParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "stop", abstract: "Stop the installed per-user daemon.")

    @Flag(help: "Print machine-readable JSON.")
    var json = false

    public init() {}

    public func run() throws {
        printService(try PlatformServiceManager().stop(), json: json)
    }
}

public struct ServiceStatus: ParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "status", abstract: "Show per-user daemon status.")

    @Flag(help: "Print machine-readable JSON.")
    var json = false

    public init() {}

    public func run() throws {
        printService(try PlatformServiceManager().status(), json: json)
    }
}

public struct Config: ParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: "Read or update local configuration.",
        subcommands: [ConfigGet.self, ConfigSet.self],
        defaultSubcommand: ConfigGet.self
    )

    public init() {}
}

public struct ConfigGet: ParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "get", abstract: "Print the current configuration.")

    @Flag(help: "Print machine-readable JSON.")
    var json = false

    public init() {}

    public func run() throws {
        let context = QuotaWakeCLIContext()
        let settings = try context.settingsStore.load()
        if json {
            print(try CLIJSON.encode(settings))
        } else {
            print("prompt: \(settings.prompt)")
            print("background.enabled: \(settings.background.launchAtLoginEnabled)")
            print("readiness.paused: \(settings.readiness.paused)")
            print("readiness.active-only: \(settings.readiness.activeOnly)")
            print("readiness.idle-seconds: \(settings.readiness.idleThresholdSeconds)")
            print("readiness.cooldown-minutes: \(settings.readiness.minimumSendCooldownMinutes)")
            print("provider.claude.enabled: \(settings.tools.claude.enabled)")
            print("provider.codex.enabled: \(settings.tools.codex.enabled)")
            print("config: \(context.paths.settingsFile.path)")
        }
    }
}

public struct ConfigSet: ParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "set", abstract: "Set one configuration value.")

    @Argument(help: "Configuration key.")
    var key: String

    @Argument(help: "New value.")
    var value: String

    public init() {}

    public func run() throws {
        let context = QuotaWakeCLIContext()
        _ = try context.updateConfiguration(key: key, value: value)
        print("\(key) updated")
    }
}

public struct Logs: ParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: "Show recent local readiness and observation logs."
    )

    @Option(help: "Maximum entries to print.")
    var limit = 20

    @Flag(help: "Print machine-readable JSON.")
    var json = false

    public init() {}

    public func validate() throws {
        if limit < 0 {
            throw ValidationError("--limit must be non-negative")
        }
    }

    public func run() throws {
        let entries = try QuotaWakeCLIContext().logs(limit: limit)
        if json {
            print(try CLIJSON.encode(entries))
        } else if entries.isEmpty {
            print("No QuotaWake activity yet.")
        } else {
            let formatter = ISO8601DateFormatter()
            for entry in entries {
                let reason = entry.skipReason.map { " \($0)" } ?? ""
                print("\(formatter.string(from: entry.startedAt)) \(entry.tool.rawValue) \(entry.status.rawValue)\(reason)")
            }
        }
    }
}

private func parseProviderSet(_ value: String, context: QuotaWakeCLIContext) throws -> Set<ToolKind> {
    let values = value.split(separator: ",").map(String.init)
    guard !values.isEmpty else {
        throw ValidationError("--providers must include claude or codex")
    }
    return try Set(values.map { raw in
        guard let tool = try context.parseProvider(raw) else {
            throw QuotaWakeCLIError.invalidProvider(raw)
        }
        return tool
    })
}

private func printStatus(_ snapshot: QuotaWakeStatusSnapshot) {
    print("QuotaWake \(snapshot.version)")
    print("Setup: \(snapshot.setupComplete ? "complete" : "required")")
    print("Background: \(snapshot.backgroundReadinessEnabled ? "enabled" : "disabled")\(snapshot.paused ? " (paused)" : "")")
    print("Activity: \(snapshot.activityMode)")
    for provider in snapshot.providers {
        printProvider(provider)
    }
    print("Config: \(snapshot.configPath)")
}

private func printProvider(_ provider: ProviderSnapshot) {
    let enabled = provider.enabled ? "enabled" : "disabled"
    var detail = "\(provider.provider): \(enabled), CLI \(provider.cliStatus)"
    if let classification = provider.classification {
        detail += ", quota \(classification)"
    }
    print(detail)
    if let path = provider.executablePath {
        print("  \(path)")
    }
    if let summary = provider.summary, !summary.isEmpty {
        print("  \(summary)")
    }
}

private func printService(_ snapshot: BackgroundServiceSnapshot, json: Bool) {
    if json, let encoded = try? CLIJSON.encode(snapshot) {
        print(encoded)
    } else {
        print("Service: \(snapshot.state.rawValue) (\(snapshot.platform))")
        if let path = snapshot.definitionPath {
            print("  \(path)")
        }
    }
}
