# QuotaWake Mac

QuotaWake is a native macOS menu bar app for Claude and Codex usage window
scheduling. It sends a tiny background readiness prompt only when local
quota-window signals indicate a reset candidate is due, the active-only gate
passes, and cooldown/idempotency checks allow the attempt.

This app should use the language "usage window scheduling", "session readiness",
and "quota window wake". Do not frame it as limit evasion.

## MVP Scope

### Must Have

- Native macOS app distributed as a signed and notarized `.dmg`.
- SwiftUI/AppKit native macOS implementation.
- Minimum supported OS: macOS 13+.
- Menu bar primary surface with a separate Settings window.
- Claude and Codex support in the first release.
- Claude and Codex enabled together by default.
- Per-tool toggles so the user can disable Claude or Codex independently.
- Reset-aware readiness polling for enabled tools.
- Local quota-window signal observation from installed official CLIs where
  available.
- Active-only gate so automatic sends are skipped while the Mac appears idle or
  in suppressed power states.
- Cooldown and overlap guards so duplicate or hung runs do not stack.
- Default readiness prompt: `hi`.
- Prompt editable from Settings.
- Launch at Login / Background readiness toggle implemented with
  `SMAppService`.
- Local execution logs retained for 30 days.
- Manual "Run now" action for testing both enabled tools.
- SemVer app/release versioning in `MAJOR.MINOR.PATCH` form, for example
  `0.0.0`, with one `version.env` source of truth.
- Manual "Check for Updates" action in Settings. If a newer signed/notarized
  DMG release is available, show a button that opens the release/download URL.
- Clear first-run explanation that QuotaWake sends a small prompt through the
  user's installed tools and that this may consume a small amount of usage.

### Must Not Have

- Do not promise operation when the Mac is fully powered off.
- Do not frame the product as limit evasion.
- Do not store Claude or Codex provider tokens in the MVP.
- Do not send direct provider HTTP requests in the MVP.
- Do not silently overwrite or clear unrelated system wake schedules.
- Do not include per-account scheduling in the MVP.
- Do not claim provider-side reset/window verification in the MVP; confidence
  must be limited to observed local quota signals, exact observed local reset
  messages, estimated candidates, unknown state, or blocked state.
- Do not include fixed calendar schedule editing in the MVP.
- Do not include wake-helper installation or sleep-wake scheduling in the MVP.
- Do not build a website or marketing page as part of the Mac MVP.
- Do not automatically download, install, or relaunch into updates in the MVP.

## App Shape

QuotaWake is a real `/Applications/QuotaWake.app`, but it should feel like a
lightweight background utility:

- The app normally lives in the macOS menu bar.
- The Dock icon should be hidden during normal use.
- Clicking the menu bar item opens a compact popover.
- "Settings..." opens a separate Settings window.
- First launch opens the setup flow automatically.

App identifier:

- Main app bundle ID: `com.jeongjin.quotawake.agentitem`.
- The app ships no worker or helper processes.

### Menu Bar Popover

The popover is for fast status and control:

- A provider tab bar at the very top (no app-name header): `Overview` plus one
  tab per enabled, runnable provider (Claude, Codex), so the surface scales as
  providers are added.
- Overview tab: a "Next reset" hero — the earliest observed 5h reset candidate
  across runnable providers as a large countdown with provider, window label,
  and wall-clock time (a waiting state points at the footer `Reload` action
  when no local signal exists) — followed by compact per-provider summary rows
  (5h remaining + reset countdown) that open the provider tab, and recent
  activity.
- Provider tab: that provider's full readout only — status, a provider-scoped
  "Next reset" hero countdown (hidden when no reset candidate is observed), 5h
  window and weekly limit with usage bars, source/confidence/last-run meta
  rows, and recent activity filtered to the provider.
- Quota state is observed automatically (periodically and when the popover
  opens); the footer `Reload` action is the manual refresh.
- Recent activity: up to three compact log rows plus an "All logs" link.
- One bottom status line above the footer: the global active-use gate note
  ("Sends while Mac is active" / "Sends in the background") at the leading
  edge and the readiness status pill (Watching / Paused / Setup needed / Last
  run failed) at the trailing edge; neither is repeated per provider.
- Footer actions: Reload, Pause/Resume, Settings, Quit.

Manual "Send readiness now" lives in Settings (General and Window Readiness),
not in the popover.

### Settings Window

Recommended sections:

1. General
   - App version.
   - Launch at Login.
   - Background readiness.
   - Pause readiness.
   - Check for Updates.
   - Update available button when a newer release is found.
2. Tools
   - Claude enabled.
   - Codex enabled.
   - CLI path detection status.
   - Manual path override.
   - Test tool.
3. Window Readiness
   - Background readiness on/off.
   - Active-only gate.
   - Idle threshold.
   - Reset estimation on/off.
   - Cooldown and manual readiness-send control.
4. Prompt
   - Readiness prompt, default `hi`.
5. Logs
   - Recent 30-day execution history.
   - Per-run decision source, confidence, status, duration, tool, exit code,
     and short sanitized summary.

## First-Run Flow

The first-run flow should optimize for trust, not speed.

1. Welcome
   - Explain that QuotaWake schedules Claude/Codex session readiness.
   - State that it sends a small prompt only when local readiness checks decide
     a quota-window candidate is due.
2. Detect Tools
   - Locate Claude and Codex CLI binaries.
   - Show detected paths.
   - Allow manual path selection if detection fails.
3. Configure Window Readiness
   - Explain reset-aware readiness, active-only behavior, cooldown, and
     estimation.
   - Offer the Launch at Login / background readiness toggle (`SMAppService`)
     as part of this step rather than a separate step.
   - Let the user keep the safe defaults or adjust readiness controls later in
     Settings.
4. Test Run
   - Send the prompt through enabled tools.
   - Show success/failure and where logs are stored.

## Execution Model

QuotaWake is a DMG-installed GUI app. Internally, the MVP sends readiness prompts
by invoking the user's installed official CLI tools in the background.

The MVP adapter should use:

- Claude: installed `claude` command.
- Codex: installed `codex` command.
- Working directory: a QuotaWake-owned directory, for example
  `~/Library/Application Support/QuotaWake/Run`.
- Timeout: bounded, so a hung CLI cannot block later readiness attempts.
- Overlap guard: skip a duplicate run if the same tool is already running.

The app should capture:

- Decision time.
- Actual start and end time.
- Tool.
- Command path.
- Exit code.
- Duration.
- Timed-out flag.
- Decision source.
- Confidence state.
- Short sanitized stdout/stderr summary.

The app should not claim the provider window reset was verified. Use wording
like "readiness prompt sent", "candidate due", "unknown quota state", or
"readiness prompt failed"; do not use provider-window success language unless a
future release adds explicit provider-side verification.

## CLI Path Detection

GUI apps do not inherit a normal interactive shell PATH. QuotaWake must support
automatic detection plus manual override.

Detection should check common locations such as:

- `/opt/homebrew/bin`
- `/usr/local/bin`
- `/usr/bin`
- `/bin`
- `/usr/sbin`
- `/sbin`
- Node/npm-managed locations discovered from the user's environment where
  practical.

For npm-installed CLIs with `#!/usr/bin/env node`, launching the CLI binary may
still fail if `node` is not on the child process PATH. The child environment
should include the detected CLI directory and common Homebrew/npm locations.

## Background Scheduling

Use `SMAppService` for Launch at Login / background readiness.

Settings must expose:

- Background readiness on/off.
- Launch at Login state.
- A clear error state if macOS reports the login item disabled.

Users can disable login/background items in macOS System Settings. QuotaWake
should detect and explain that state instead of assuming it remains enabled.

## Sleep Wake

Sleep wake is not active MVP scope. Automatic readiness sends are evaluated only
while the app is running in the logged-in user session and the active-only gate
passes.

Guardrails:

- Do not install a privileged helper for MVP readiness.
- Do not run Claude or Codex as root.
- Do not create or modify system wake schedules.
- Do not promise operation when the Mac is asleep, fully powered off,
  unavailable, or unable to run the logged-in user app.

## Logs And Privacy

QuotaWake should be local-first.

- Logs are stored locally.
- Default retention is 30 days.
- Logs should avoid storing full long outputs by default.
- Logs may include the prompt text, command path, status, timestamps, duration,
  exit code, and short error summaries.
- The MVP does not collect telemetry.
- The MVP does not upload source code.
- The MVP does not store provider tokens.

## Versioning And Updates

QuotaWake Mac should use one explicit SemVer version contract:

- `version.env` is the version source of truth.
- `VERSION` uses numeric `MAJOR.MINOR.PATCH` form, such as `0.0.0`.
- Release tags use `v<VERSION>`, for example `v0.0.0`.
- `CFBundleShortVersionString`, `CFBundleVersion`, release notes, and DMG
  filenames should all be derived from the same `VERSION`.

The MVP update path is manual:

- Settings > General has "Check for Updates".
- The check reads public GitHub Release metadata for the QuotaWake release
  repository.
- If the latest release version is newer than the local app version, Settings
  shows a button to open the release page or signed/notarized DMG asset.
- The app must not auto-download, auto-install, relaunch, or run a Sparkle/Tauri
  updater flow in the MVP.

## Distribution

Target distribution:

- `.dmg` download.
- Drag `QuotaWake.app` to `/Applications`.
- Developer ID signed.
- Hardened runtime enabled.
- Notarized before public release.

The MVP should not target the Mac App Store first. Direct DMG distribution is a
better fit for CLI invocation and background readiness behavior.

Release execution details live in `RELEASE.md`. Public and prerelease downloads
must be signed and notarized `.dmg` assets only, with Gatekeeper validation,
SHA-256 digest, and mounted Finder-window presentation evidence recorded before
upload. Do not publish `.app` bundles, `.zip` archives, debug builds, private
logs, env dumps, secrets, updater-only assets, or helper staging files as user
downloads.

Developer build, QA, troubleshooting, and version-bump commands live in
`DEVELOPMENT.md`.

## Deferred

- Per-account schedules.
- Direct provider HTTP/token-based readiness requests.
- Provider-side reset/window verification.
- Sleep wake support.
- Fixed calendar schedule editing.
- Usage monitoring dashboards.
- Custom command providers.
- Cloud sync.
- Remote/GitHub Actions scheduling.
- Automatic update download/install/relaunch.
- Mac App Store distribution.
