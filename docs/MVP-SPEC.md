# QuotaWake

QuotaWake is a local-first CLI and per-user daemon for Claude Code and Codex
usage-window scheduling. It observes local quota-window signals and sends a
small readiness prompt only when a reset candidate is due and the configured
activity, retry, cooldown, and idempotency gates allow an attempt.

Use "usage window scheduling", "session readiness", and "quota window wake".
Do not frame QuotaWake as limit evasion.

## Product surfaces

### Primary: `quotawake` CLI

The lowercase command is the canonical interface on every platform:

- `setup`, `doctor`, and `status` establish and inspect local state.
- `observe` reads local provider quota signals without sending a prompt.
- `send` explicitly sends a manual readiness prompt.
- `daemon` runs reset-aware scheduling in the foreground.
- `service` manages a per-user background daemon.
- `config` and `logs` expose durable local configuration and history.
- Machine-oriented status, logs, observation, and service commands provide
  JSON output and stable string values.

### Optional: macOS menu bar app

The SwiftUI/AppKit menu bar app remains an optional status and settings client.
It is packaged as `QuotaWake.app` and requires macOS 13 or newer. It must not be
required for CLI setup, manual observation/send, local state, or the daemon.

During the CLI-first transition the app retains its original in-process poller.
Before both surfaces are generally available together, the per-user daemon must
become the single scheduling owner and the app must become a client of its
state/control surface.

## Supported scope

“Supported” below describes intended implementation scope, not current public
binary availability. The current ship decision and evidence are maintained in
`docs/RELEASE-READINESS.md`.

### Must have

- Claude Code and Codex provider support, independently toggleable.
- Installed official `claude` and `codex` CLIs as the provider boundary.
- No provider HTTP API calls and no provider-token storage.
- Reset-aware observation and readiness decisions.
- Active-only automatic sends with a fail-closed unavailable policy.
- Cooldown, overlap prevention, idempotency, and bounded failed-send retry.
- A default `hi` prompt with local configuration.
- Per-user background execution without root privileges.
- Atomic local settings/quota state and sanitized 30-day JSONL logs.
- `QUOTAWAKE_HOME` plus native default state roots per platform.
- macOS and Linux build/test gates; visible Windows portability build.
- SemVer shared by `version.env`, CLI output, archives, app metadata, tags, and
  release notes.

### Platform status

- macOS 13+ arm64: locally verified source/developer preview. CLI, launchd user
  agent, CoreGraphics idle detection, power-state suppression, and optional
  native app are implemented; public download trust and service lifecycle
  gates remain pending.
- macOS 13+ x86_64: implementation target, not yet built in this review.
- Linux: CLI preview, `systemd --user` service, and current-session
  `systemd-logind` idle detection. Native build, session discovery, runtime
  dependency, and service-lifecycle gates remain pending.
- Windows 10+: manual CLI/build and Task Scheduler preview. Automatic
  active-only sends fail closed until native Win32 idle detection is verified;
  descendant cleanup remains preview until Job Object support lands.

### Must not have

- Do not run Claude, Codex, or QuotaWake provider work as root.
- Do not store provider tokens, cookies, OAuth sessions, browser sessions, raw
  provider transcripts, or full debug logs.
- Do not call provider HTTP APIs or scrape provider dashboards/TUIs.
- Do not silently treat a headless or unknown session as active.
- Do not claim provider-side reset verification without an explicit local
  provider signal.
- Do not create per-account schedules or custom provider commands in this MVP.
- Do not install privileged wake helpers or modify unrelated power schedules,
  launch jobs, systemd units, or scheduled tasks.
- Do not promise operation while a machine is powered off or unable to run the
  logged-in user's daemon.

## Execution model

QuotaWake owns a working directory under the platform state root and invokes:

- Claude: `claude --print --output-format text --no-session-persistence <prompt>`
- Codex: `codex exec --sandbox read-only --skip-git-repo-check --ephemeral ...`

Every provider invocation has a bounded timeout, an overlap guard, sanitized
output, and an environment scrub that removes API-billing/gateway variables.
The runtime records timestamps, provider, command path, status, exit code,
duration, decision source, confidence, and a short sanitized summary.

The local quota source hierarchy is:

1. Provider CLI state such as Codex `app-server` rate limits.
2. An exact reset parsed from bounded local CLI output.
3. An optional five-hour estimate from the last successful readiness send.
4. Unknown state, which never sends automatically in strict mode.

## Activity and background scheduling

The default active-only gate uses the native session adapter. If activity
cannot be established, automatic sends fail closed. Manual `observe` and `send`
remain explicit user actions and do not depend on the automatic gate.

Per-user service integration is:

- macOS: LaunchAgent registered in the logged-in GUI domain.
- Linux: `systemd --user` service.
- Windows preview: Task Scheduler task at user logon.

No service integration may require or silently escalate to administrator/root.

## Paths

- macOS: `~/Library/Application Support/QuotaWake/`
- Linux: `$XDG_STATE_HOME/quotawake/` or `~/.local/state/quotawake/`
- Windows: `%LOCALAPPDATA%\QuotaWake\`
- Override: `QUOTAWAKE_HOME`

The root contains `settings.json`, `Logs/`, `QuotaWindows/`, `Run/`, and the
daemon PID file. macOS keeps its existing root to preserve app data.

## Distribution

CLI preview packaging produces:

- `quotawake-<version>-macos-<arch>.tar.gz`
- `quotawake-<version>-linux-<arch>.tar.gz`
- `quotawake-<version>-windows-<arch>.zip`
- adjacent SHA-256 files

Public CLI assets require native build and smoke evidence for their platform.
Windows artifacts remain CI previews until Windows is promoted to a required
gate. Package-manager manifests are deferred until the archive layout is
stable.

The optional macOS app continues to require Developer ID signing,
notarization, stapling, Gatekeeper validation, checksum publication, and DMG
presentation verification.

## Deferred

- Windows Win32 idle reader and Job Object process-tree termination.
- CLI-daemon control IPC and conversion of the Mac app into a thin client.
- Homebrew, WinGet/Scoop, and a checksummed official install script.
- Headless always-active mode.
- Automatic binary updater.
- Per-account schedules, provider dashboards, custom providers, and remote
  GitHub Actions scheduling.
