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

AI coding assistants like **Claude Code** and **Codex** only run through their CLIs after you
send a prompt. If that first readiness prompt happens after you sit down, it competes with
the start of your workday.

**QuotaWake** sends a small readiness prompt (`hi` by default) through your already-installed
CLIs when a reset-aware readiness check has a due quota-window candidate and your Mac
appears actively in use. By the time you return to coding, the readiness attempt and its
local confidence state are already logged.

> QuotaWake is about **usage-window scheduling and session readiness**, not bypassing limits.
> It uses the official CLIs you already have installed and is transparent about every run.

---

## ✨ Features

- 🌙 **Lives in the menu bar** — a lightweight background utility, no Dock clutter.
- 🤖 **Claude + Codex** — both enabled by default, each toggleable independently.
- 🪟 **Reset-aware readiness** — uses local quota-window signals before sending.
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

```
        ┌────────────────────────┐
        │ local quota observation│  Codex app-server / Claude usage probe / CLI message
        └───────────┬────────────┘
                    ▼
        ┌────────────────────────┐
        │ reset-aware readiness  │  due candidate + active Mac + cooldown/idempotency
        └───────────┬────────────┘
                    ▼
           claude -p "hi" / codex "hi"  ◀── runs as you, not root
                    │
                    ▼
       readiness attempt + confidence state logged locally
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
**official CLI you already have installed** (`claude`, `codex`) in a sandboxed working
directory, with a bounded timeout and an overlap guard so a hung run can't block the next
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
| **General** | Version · Launch at Login · Background readiness · Pause · Check for Updates |
| **Tools** | Claude / Codex toggles · CLI path detection · manual path override · test |
| **Window Readiness** | Active-only gate · idle threshold · reset estimation · cooldown · observe/send controls |
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
