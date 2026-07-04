<div align="center">

<img alt="QuotaWake" src=".github/assets/quotawake-banner.png" width="760">

<br><br>

**Keep your AI coding session ready when a usage window is available.**

A tiny native macOS menu bar app that sends a small readiness prompt to Claude and Codex
when a local quota-window signal says a reset candidate is due and your Mac appears active.

<br>

[![Platform](https://img.shields.io/badge/macOS-13%2B-1A1A1A?logo=apple&logoColor=white)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-E8602C.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/jeongjin0/quotawake?color=F0962B&label=release)](https://github.com/jeongjin0/quotawake/releases)
[![Downloads](https://img.shields.io/github/downloads/jeongjin0/quotawake/total?color=1A1A1A)](https://github.com/jeongjin0/quotawake/releases)

[**Download**](https://github.com/jeongjin0/quotawake/releases/latest) ·
[How it works](#-how-it-works) ·
[Build from source](#-build-from-source) ·
[Privacy](#-privacy)

</div>

---

## What is QuotaWake?

**Claude Code** and **Codex** meter usage in rolling windows — for example, Claude's
5-hour window opens the moment you send your first prompt. Hit the limit mid-session and
the CLI tells you the window resets in an hour or two… usually while you're away from
the desk, and the reset quietly passes unused.

**QuotaWake** watches those local reset signals. When a reset candidate comes due and your
Mac appears actively in use, it sends a small readiness prompt (`hi` by default) through
your already-installed CLIs — so a fresh usage window is already open and logged by the
time you sit back down, instead of starting on your first real prompt of the afternoon.

> QuotaWake is about **usage-window scheduling and session readiness**, not bypassing limits.
> It uses the official CLIs you already have installed and is transparent about every run.

---

## ✨ Features

- 🌙 **Lives in the menu bar** — a lightweight background utility, no Dock clutter.
- 🤖 **Claude + Codex** — both enabled by default, each toggleable independently.
- 🪟 **Reset-aware readiness** — watches local quota-window signals ("resets 2pm") and
  sends when the reset comes due, not on a blind timer.
- 🖱 **Active-only gate** — skips background sends while the Mac appears idle or in suppressed power states.
- 🚀 **Launch at login** — background scheduling via `SMAppService`.
- ✍️ **Editable prompt** — defaults to `hi`; change it in Settings.
- ▶️ **Send readiness now** — run a manual readiness prompt when you choose.
- 📜 **Local logs (30 days)** — every run's time, tool, duration, exit code, and status.
- 🔒 **Local-first** — no telemetry, no provider-token storage, no source upload.

---

## 📦 Install

1. Download the latest signed & notarized **`QuotaWake.dmg`** from the
   [**Releases**](https://github.com/jeongjin0/quotawake/releases/latest) page.
2. Open the DMG and drag **QuotaWake.app** into **Applications**.
3. Launch it — the first-run setup detects your CLIs and keeps readiness checks local.

> Only signed & notarized `.dmg` builds are published as downloads. macOS Gatekeeper
> validates the app on first launch.

### Requirements

| | |
|---|---|
| **OS** | macOS 13 (Ventura) or later |
| **Tools** | [`claude`](https://docs.anthropic.com/en/docs/claude-code) and/or [`codex`](https://github.com/openai/codex) CLI installed |
| **Account** | An active Claude and/or Codex login the CLI can use |

---

## 🌗 How it works

### A typical afternoon

```
  window #1 open   waiting for reset   window #2
 ●━━━━━━━━━━━━━━━●╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌●━━━━━━━━━━━●━━▶
09:00          11:37               14:00       14:40
 │               │                   │           │
 │               │                   │           └─ you're back —
 │               │                   │              window open + logged
 │               │                   └─ reset lands · Mac still active
 │               │                      QuotaWake sends claude --print "hi"
 │               └─ 5h limit hit · CLI says "resets 2pm"
 │                  QuotaWake records the local reset signal
 └─ first prompt of the day opens the 5-hour window
```

Without QuotaWake, that 14:00 reset passes silently and the next window only opens on
your first real prompt of the afternoon. With it, session readiness is aligned to the
reset — not to whenever you happen to return.

### The pipeline

Every automatic send goes through the same four stages:

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   OBSERVE    │────▶│    DECIDE    │────▶│     SEND     │────▶│     LOG      │
│ local quota  │     │ reset-aware  │     │ official CLI │     │ local record │
│   signals    │     │  readiness   │     │    as you    │     │  + popover   │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
Codex app-server /   due reset candidate  claude --print "hi"  time · tool · exit
Claude usage probe / + Mac appears active / codex exec "hi"    code · duration ·
CLI reset message    + cooldown /         bounded timeout,     source · confidence
("resets 2pm")       idempotency guards   never as root        — popover + JSONL
```

QuotaWake first looks for local quota-window signals. The source hierarchy is:

1. **Observed local quota** from a local provider CLI surface, such as Codex
   `app-server` rate-limit data when available.
2. **Exact observed reset** parsed from bounded, sanitized CLI output such as a reset
   timestamp or relative reset message.
3. **Estimated 5-hour candidate** from the last successful readiness send when explicit
   local quota signals are unavailable and estimation is enabled.
4. **Unknown quota state**, which does not trigger automatic readiness sends in strict mode.

When a reset candidate is due and the active-only gate passes, QuotaWake invokes the
**official CLI you already have installed** (`claude`, `codex`) in a QuotaWake-owned
working directory (Codex additionally runs in its read-only sandbox mode), with a bounded
timeout and an overlap guard so a hung run can't block the next
one. It records the actual time, tool, command path, exit code, duration, decision source,
confidence, and a short sanitized status in the menu bar popover and logs.

QuotaWake does not call Claude, Codex, Anthropic, or OpenAI provider HTTP APIs directly.
Claude `ANTHROPIC_API_KEY`/gateway/cloud billing environment can route Claude Code through
API-billed usage, so QuotaWake blocks or scrubs those keys by default for Claude readiness
prompts.

QuotaWake reports local confidence states such as **observed local quota**, **exact
observed reset**, **estimated 5-hour candidate**, **unknown**, or **blocked**. It does not
claim provider-side reset verification unless an explicit local CLI/provider signal was
observed.

---

## 🛠 Build from source

QuotaWake is a Swift Package (`QuotaWakeCore` library + `QuotaWake` executable).

```bash
git clone https://github.com/jeongjin0/quotawake.git
cd quotawake

# build & test the core
swift build
swift test

# package the signed .app / .dmg
./Scripts/package_app.sh
./Scripts/create_dmg.sh
```

| Doc | Purpose |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Code structure, runtime flow, module map |
| [`DESIGN.md`](DESIGN.md) | App shape, menu bar / Settings UX, first-run flow |
| [`DEVELOPMENT.md`](DEVELOPMENT.md) | Build, QA, troubleshooting, version-bump commands |
| [`RELEASE.md`](RELEASE.md) | Signing, notarization, and release execution |
| [`docs/MVP-SPEC.md`](docs/MVP-SPEC.md) | Full product specification & scope |
| [`version.env`](version.env) | Single SemVer source of truth |

---

## ⚙️ Configuration

Everything lives in the **Settings** window (menu bar → *Settings…*):

| Section | What you control |
|---|---|
| **General** | Version · Launch at Login · Background readiness (pause/resume) · Send readiness now · Check for Updates |
| **Providers** | Claude / Codex checkboxes · CLI path detection · manual path override · test |
| **Window Readiness** | Active-only gate · idle threshold · reset estimation · cooldown · manual send control |
| **Prompt** | The readiness prompt (default `hi`) |
| **Logs** | Recent 30-day run history with decision source, confidence, and per-run status |

GUI apps don't inherit your interactive shell `PATH`, so QuotaWake auto-detects CLIs in
`/opt/homebrew/bin`, `/usr/local/bin`, and other common locations — with a manual override
if detection fails.

---

## 🔒 Privacy

QuotaWake is **local-first** by design:

- ✅ Logs stay on your machine (30-day default retention).
- ✅ No telemetry, no analytics.
- ✅ No provider tokens stored.
- ✅ No source code uploaded.
- ✅ No direct provider HTTP requests — it only invokes installed official local CLIs.
- ✅ No provider dashboard scraping, cookie import, OAuth-token extraction, or WebView auth import.
- ✅ Claude API-billing environment such as `ANTHROPIC_API_KEY` is blocked or scrubbed by
  default for readiness prompts.

The only network activity is an optional **Check for Updates** that reads public GitHub
release metadata.

### Data locations & uninstall

All app data lives under `~/Library/Application Support/QuotaWake/`:
`settings.json`, `Logs/` (daily JSONL run logs), `QuotaWindows/` (observed
quota state), and `Run/` (the working directory readiness prompts run in).

To uninstall completely: quit QuotaWake, delete `/Applications/QuotaWake.app`,
delete `~/Library/Application Support/QuotaWake/`, and remove the login item in
**System Settings → General → Login Items** if it remains listed.

---

## 🗺 Roadmap

Currently **out of scope** (may come later):

- Per-account schedules
- Provider-side reset / window verification
- Usage-monitoring dashboards
- Custom command providers
- Remote / GitHub Actions scheduling
- Automatic update download & install
- Mac App Store distribution

---

## 🤝 Contributing

Issues and PRs are welcome. Please keep the framing consistent with the project's positioning:
**usage-window scheduling and session readiness**, never limit evasion. For larger changes,
open an issue first to discuss direction. See [`DESIGN.md`](DESIGN.md) for app shape and UX
principles, and [`DEVELOPMENT.md`](DEVELOPMENT.md) for the build/QA workflow.

---

## 📄 License

[MIT](LICENSE) © 2026 Jeongjin Shin

<div align="center">
<br>
<img alt="" src=".github/assets/quotawake-badge.png" width="38">
<br><br>
<sub><b>QuotaWake</b> — reset-aware session readiness before you sit down.</sub>
</div>
