<div align="center">

<img alt="QuotaWake" src=".github/assets/quotawake-banner.png" width="760">

<br><br>

**Keep your AI coding session ready when a usage window is available.**

QuotaWake is a local-first CLI and background daemon for reset-aware Claude Code and
Codex session readiness. The native macOS menu bar app is an optional interface.

<br>

[![Platform](https://img.shields.io/badge/macOS%20%7C%20Linux-Windows%20preview-1A1A1A)](#platform-status)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-E8602C.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/jeongjin0/quotawake?color=F0962B&label=release)](https://github.com/jeongjin0/quotawake/releases)

[Quick start](#quick-start) · [Commands](#commands) · [How it works](#how-it-works) · [macOS app](#optional-macos-menu-bar-app)

</div>

---

> **Release status (2026-07-31): developer preview.** The macOS arm64 CLI is
> locally verified from source, but the downloadable archive is not yet a
> signed/notarized stable release. Native CI now passes on macOS and Linux, and
> the Windows build preview passes, but packaging, clean-machine runtime, and
> background-service lifecycle gates remain. See
> [Release readiness](docs/RELEASE-READINESS.md) before publishing binaries.

## What is QuotaWake?

QuotaWake observes local quota-window signals from the official Claude Code and Codex
CLIs. When a reset candidate is due, activity and cooldown checks allow it, and the
per-user daemon is running, QuotaWake sends a small readiness prompt (`hi` by default)
and records the result locally.

QuotaWake is about **usage-window scheduling and session readiness**, not bypassing
limits. It does not call provider HTTP APIs, import browser sessions, or store provider
tokens.

## Quick start

QuotaWake currently builds from source while cross-platform release archives are being
validated:

```bash
git clone https://github.com/jeongjin0/quotawake.git
cd quotawake
swift build -c release --product quotawake

# Install into a durable user-owned path before registering the service.
install -d "$HOME/.local/bin"
install -m 0755 .build/release/quotawake "$HOME/.local/bin/quotawake"
export PATH="$HOME/.local/bin:$PATH"

quotawake setup
quotawake doctor
quotawake service install
```

The `setup` command detects installed `claude` and `codex` commands. At least one must
already be installed and logged in. `service install` stores the CLI's absolute path;
do not register a binary inside `.build`, Downloads, or a temporary extraction folder.

## Commands

| Command | Purpose |
| --- | --- |
| `quotawake setup` | Detect providers and create local configuration |
| `quotawake doctor` | Check setup and provider CLI paths; service/activity diagnostics are still pending |
| `quotawake status [--json]` | Show provider and quota-window state |
| `quotawake observe [claude\|codex]` | Read local quota signals without sending a prompt |
| `quotawake send [claude\|codex]` | Send a manual readiness prompt now |
| `quotawake daemon` | Run the scheduler in the foreground |
| `quotawake service install` | Install and start the per-user background daemon |
| `quotawake service status` | Show background daemon status |
| `quotawake service stop` | Stop the background daemon |
| `quotawake service uninstall` | Remove the background daemon |
| `quotawake config get [--json]` | Print local configuration |
| `quotawake config set <key> <value>` | Change one configuration value |
| `quotawake logs [--limit N] [--json]` | Show recent local activity |

Run `quotawake --help` or `quotawake help <command>` for the complete command help.
Machine-oriented commands support JSON output, stable provider/status values, and normal
process exit codes so coding agents can install and operate QuotaWake without scraping a
GUI.

## How it works

```text
observe local quota signal
          │
          ▼
reset-aware decision ── candidate due + activity + idempotency + cooldown
          │
          ▼
claude --print "hi" / codex exec "hi"
          │
          ▼
sanitized local state + 30-day JSONL logs
```

The source hierarchy is:

1. Observed local quota from an installed provider CLI surface.
2. An exact reset parsed from bounded, sanitized CLI output.
3. An optional estimated five-hour candidate from the last successful send.
4. Unknown state, which does not send automatically in strict mode.

Provider processes run as the logged-in user with a bounded timeout and an overlap guard.
Claude/Codex API-billing environment variables are scrubbed before child processes run.
The default activity policy fails closed when the OS cannot report whether the session is
active.

## Platform status

| Platform | CLI evidence | Background service | Activity adapter | Release status |
| --- | --- | --- | --- | --- |
| macOS 13+ arm64 | Built and tested locally | `launchd` implemented; native lifecycle gate pending | CoreGraphics + power-state checks | Source/developer preview |
| macOS 13+ x86_64 | Not built in this review | `launchd` implementation shared | Not verified on Intel | Unverified |
| Linux | Swift 6.3.3 CI build, 166 tests, and CLI smoke pass | `systemd --user` preview | `systemd-logind` session handling needs VM QA | Source/CI preview |
| Windows 10+ | Swift 6.3.3 native build and CLI smoke pass | Task Scheduler preview | Automatic sends fail closed pending Win32 adapter | Build preview |

The [cross-platform CI run](https://github.com/jeongjin0/quotawake/actions/runs/30566908704)
passed on macOS 15, Ubuntu 24.04, and Windows. Windows remains a non-required build
preview. Automatic sends stay fail-closed until the native idle adapter and process-tree
termination pass native Windows QA; `status`, `doctor`, `observe`, and `send` are the
initial portability surface. Linux currently requires Bash for safe provider-process
launching in addition to the Swift runtime requirements of the packaged binary.

Current ship decision: a clearly labeled macOS arm64 developer preview is
reasonable for technical testers. A stable public CLI archive, Linux binary,
Windows binary, or combined Mac app + CLI-daemon release is not yet approved.

## Configuration and data

Default data roots:

| Platform | Location |
| --- | --- |
| macOS | `~/Library/Application Support/QuotaWake/` |
| Linux | `$XDG_STATE_HOME/quotawake/` or `~/.local/state/quotawake/` |
| Windows | `%LOCALAPPDATA%\QuotaWake\` |

Set `QUOTAWAKE_HOME` to use an explicit root. The directory contains `settings.json`,
`Logs/`, `QuotaWindows/`, `Run/`, and the daemon PID file.

Useful settings include:

```bash
quotawake config set prompt hi
quotawake config set readiness.paused true
quotawake config set readiness.active-only true
quotawake config set readiness.idle-seconds 300
quotawake config set background.enabled true
```

## Optional macOS menu bar app

The SwiftUI/AppKit menu bar app remains available for people who prefer a glanceable
status surface and native Settings window. It is not required for the CLI, local state,
manual observation, or daemon architecture.

Build and package it on macOS:

```bash
swift build --product QuotaWakeMac
./Scripts/package_app.sh debug
```

The application bundle is still named `QuotaWake.app`; `QuotaWakeMac` is only the internal
SwiftPM product name used to avoid a case-insensitive filesystem collision with the
lowercase `quotawake` CLI.

## Build and test

```bash
swift build --product quotawake
swift test

# macOS/Linux CLI preview archive
./Scripts/package_cli.sh release

# macOS app package
./Scripts/package_app.sh debug
```

Windows packaging uses `Scripts/package_cli.ps1`. CI builds and tests macOS and Linux as
required jobs, and keeps the Windows build visible as a portability preview until it is
promoted to a required gate.

| Document | Purpose |
| --- | --- |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Targets, runtime flow, and platform seams |
| [`docs/MVP-SPEC.md`](docs/MVP-SPEC.md) | Product contract and supported scope |
| [`docs/RELEASE-READINESS.md`](docs/RELEASE-READINESS.md) | Current confidence, ship decision, evidence, and risk register |
| [`DEVELOPMENT.md`](DEVELOPMENT.md) | Build, QA, and troubleshooting |
| [`RELEASE.md`](RELEASE.md) | CLI archives and optional macOS app release gates |
| [`DESIGN.md`](DESIGN.md) | Optional macOS interface design system |

## Privacy and safety

- Logs and quota state stay on the local machine.
- No telemetry or analytics.
- No direct provider HTTP requests.
- No provider-token, cookie, OAuth-session, or browser-session storage.
- No source upload.
- Provider CLIs never run as root.
- API-billing and gateway environment variables are scrubbed before readiness calls.
- Automatic sends remain disabled when the active-only gate cannot be evaluated.

## Roadmap

- Promote Linux service and activity support after native QA.
- Add the Windows Win32 idle adapter and native process-tree termination.
- Publish signed/checksummed CLI release archives.
- Add Homebrew and Windows package-manager installation.
- Make the macOS app a thin client of the CLI-owned daemon and JSON state surface.

Per-account schedules, provider dashboard scraping, direct provider APIs, and quota
bypass behavior remain out of scope.

## License

[MIT](LICENSE) © 2026 Jeongjin Shin
