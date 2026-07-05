# QuotaWake Mac Architecture

A map of the code for contributors. Product scope lives in `docs/MVP-SPEC.md`;
build/QA commands live in `DEVELOPMENT.md`.

## Targets

- `QuotaWakeCore` (library): all decision logic, parsing, persistence, and
  process execution. Fully covered by `Tests/QuotaWakeCoreTests`.
- `QuotaWake` (executable): AppKit/SwiftUI shell — `AppModel.swift` (view
  model), `AppDelegate.swift` (status item, popover/window wiring),
  `SettingsViews.swift`, `FirstRunViews.swift`, the popover view files,
  `DebugUIQA.swift` (`#if DEBUG` UI-QA harness), and a 9-line `main.swift`
  entry point.

## Runtime flow

```
60s tick (QuotaWakeAppModel.startResetAwarePoller)
   ├─ QuotaReadinessPoller.tick()
   │    ├─ SettingsStore.load()            gate: first-run done, background on, not paused
   │    ├─ RunLogStore.readAll()           idempotency + cooldown inputs (read once per tick)
   │    ├─ ActivityGate.evaluate()         idle threshold (CGEventSource) + power state (ioreg)
   │    └─ per enabled tool (failures isolated per tool):
   │         ├─ QuotaWindowStateStore.load(tool)
   │         ├─ QuotaReadinessEngine.evaluate(input) ──▶ send / wait / observeNeeded
   │         ├─ send:    ToolRunner.run() ──▶ CLIExecutor (timeout, env scrub,
   │         │           overlap guard, ProcessTreeTerminator) ──▶ RunLogStore
   │         │           ├─ QuotaWindowParser.parse(output) ──▶ QuotaWindowStateStore
   │         │           └─ successful sends: one immediate post-send
   │         │             verification observe (unthrottled; read-only) so
   │         │             the freshly started window is stored right away
   │         ├─ wait:    transition-deduped skip entry ──▶ RunLogStore
   │         └─ observe: (readiness path; throttled to one probe / tool / 10 min)
   │                     CodexQuotaAdapter (codex app-server JSON-RPC) or
   │                     ClaudeQuotaAdapter (bounded /usage probe via QuotaProbeRunner)
   │                     ──▶ QuotaWindowStateStore + deduped log entry
   └─ QuotaReadinessPoller.observeIfStale(maxAgeSeconds: 55)
        display-refresh path: re-observes each enabled tool whose stored quota
        state is older than maxAgeSeconds (5-minute retry backoff after failed
        observations). Local quota read only — never sends a provider message —
        so it runs even when background readiness is off or paused; gated only
        on first-run completion. Opening the popover triggers the same path
        with a 30-second threshold and a matching failure-retry override, so a
        failed probe heals on the next open instead of waiting out the backoff.
        Its log entries dedupe on outcome only, so a moving usage percent does
        not append a row per pass. State merge: fresh quota fields win
        field-wise and the previous observation fills the gaps, so the popover
        never blanks to Unknown while data is merely stale. An uninformative
        result (a send's reply text, a failed probe, or the idle post-reset
        panel — including its "0% used, no resets clause" shape) additionally
        retains a previous unconsumed limitReached reset candidate so the due
        wake cannot be erased before the engine consumes it; once a successful
        send lands at/after that reset the candidate is consumed and the fresh
        classification wins (which is what lets the estimated-5h chain resume).
        Blocked classifications (auth, billing env) always win.
```

The 60-second loop's `Task.sleep` pauses while the Mac sleeps, so
`QuotaWakeAppModel` also listens for `NSWorkspace.didWakeNotification` and runs
one immediate catch-up pass (tick + stale observe) on system wake instead of
waiting for the next post-wake tick.

## Decision engine

`QuotaReadinessEngine` is pure (no I/O). Source hierarchy: observed local
quota → exact observed reset → estimated 5-hour candidate (only when
estimation is enabled) → unknown (strict mode observes instead of sending).
Gates, in order: candidate due → activity gate → idempotency (successful sends
only, persisted via run logs, so relaunches cannot double-send) → bounded
failure retry (a failed/timed-out send retries after a 10-minute backoff, at
most 3 attempts per reset window) → cooldown (keyed to the last provider
attempt of any outcome, so attempts on different reset candidates stay
spaced). Blocked/unavailable states older than ~15 minutes yield
`observeNeeded(.staleProviderState)` so a one-time failure self-heals.

## Core files (active)

| Area | Files |
| --- | --- |
| Decision engine | `QuotaReadinessEngine`, `QuotaReadinessTypes` |
| Poll loop | `QuotaReadinessPoller` |
| Quota observation | `CodexQuotaAdapter`, `ClaudeQuotaAdapter`, `QuotaProbeRunner`, `QuotaWindowObserver` |
| CLI output parsing | `QuotaWindowParser` |
| Quota state | `QuotaWindowState` (+ sanitizer), `QuotaWindowStateStore` (per-tool JSON in `QuotaWindows/`) |
| Prompt execution | `CLIExecutor`, `ProcessTreeTerminator` (SIGTERM→SIGKILL over the descendant tree) |
| CLI discovery | `CLIPathDetector` (common bins + nvm/volta/npm dirs; codex `--version` health probe, cached) |
| Activity gate | `ActivityGate` (fail-closed idle + dark-wake suppression) |
| Persistence | `AppSettings`/`SettingsStore`, `RunLogs` (daily JSONL, 30-day retention, corruption-tolerant reads), `AppPaths` |
| UI state mapping | `AppUIModels` (pure presentation mapper consumed by the executable) |
| Misc | `FirstRunFlow`, `LaunchAtLoginManager` (SMAppService), `UpdateChecker` (strict SemVer vs GitHub releases), `QuotaWakeCore` (bundle metadata) |

## Removed scope

The Phase-4 wake-helper subsystem (`WakeHelper`, `WakeHelperInstaller`,
`WakeCoordinator`) has been deleted from the tree; it remains in git history.
See "Removed Wake Helper Scope" in `AGENTS.md` before reintroducing anything
like it.

## Data on disk

`~/Library/Application Support/QuotaWake/`
- `settings.json` — app settings (schema v2; v1 `schedule.paused` migrates to `readiness.paused`)
- `Logs/YYYY-MM-DD.jsonl` — sanitized run/skip/observation entries
- `QuotaWindows/<tool>.json` — last observed quota state per tool
- `Run/` — working directory for readiness prompts

## Invariants worth knowing

- No provider HTTP calls; only installed local CLIs are invoked, never as root.
- Child environments are always scrubbed of API-billing keys
  (`CLIChildEnvironmentPolicy`); `live_cli_smoke.sh` mirrors the same key list.
- Everything written to disk passes a sanitizer (`RunLogSanitizer`,
  `QuotaWindowSanitizer`) first.
- Failed/timed-out sends retry with a bounded backoff instead of burning the
  reset window: no immediate retry (10-minute backoff, pinned by
  `testFailedAndTimedOutResetWindowAttemptsPreventImmediateRetry`), retry
  allowed after the backoff (`testFailedSendRetriesAfterBackoffElapses`), and
  a hard cap of 3 attempts per reset window
  (`testExhaustedSendAttemptsStopRetrying`). A send that exits 0 while its
  output reports a usage limit or login prompt is graded `.failed`, not
  `.sent`, so it cannot complete the window or anchor the 5h estimate.
