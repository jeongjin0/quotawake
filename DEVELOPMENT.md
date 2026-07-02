# QuotaWake Mac Development

This is the day-to-day implementation guide for the native macOS app. Run
commands from `quotawake_mac/` unless a command says otherwise.

## Local Build

Required baseline:

- macOS 13 or newer.
- Xcode command line tools with Swift 5.9-compatible SwiftPM.
- `plutil`, `codesign`, `hdiutil`, and `xcrun` from macOS/Xcode tools.
- `rg` for guardrail scans.
- No provider credentials are needed for automated tests or fake-CLI QA.

Core commands:

```bash
swift test
swift build -c debug
./Scripts/package_app.sh debug
./Scripts/create_dmg.sh --dry-run
```

`./Scripts/package_app.sh debug` creates `QuotaWake.app`, writes
`Contents/Info.plist`, sets `LSUIElement=true`, injects version/update metadata
from `version.env`, and ad-hoc signs the debug app for local launch checks.

Local launch smoke test:

```bash
open -n QuotaWake.app
pgrep -fl QuotaWake
plutil -extract LSUIElement raw -o - QuotaWake.app/Contents/Info.plist
osascript -e 'tell application "QuotaWake" to quit' || pkill -x QuotaWake
```

Expected result: QuotaWake runs as a menu bar app with `LSUIElement=true`; it
does not show a normal Dock app icon.

Useful focused test commands (reset-aware core first):

```bash
swift test --filter QuotaWakeCoreTests.QuotaReadinessEngineTests
swift test --filter QuotaWakeCoreTests.QuotaWindowParserTests
swift test --filter QuotaWakeCoreTests.ClaudeQuotaAdapterTests
swift test --filter QuotaWakeCoreTests.CodexQuotaAdapterTests
swift test --filter QuotaWakeCoreTests.ResetAwareAppIntegrationTests
swift test --filter QuotaWakeCoreTests.ActivityGateTests
swift test --filter QuotaWakeCoreTests.SettingsAndLogsTests
swift test --filter QuotaWakeCoreTests.CLIPathDetectorTests
swift test --filter QuotaWakeCoreTests.CLIExecutorTests
swift test --filter QuotaWakeCoreTests.LaunchAtLoginManagerTests
swift test --filter QuotaWakeCoreTests.AppUIModelsTests
swift test --filter QuotaWakeCoreTests.FirstRunFlowTests
swift test --filter QuotaWakeCoreTests.UpdateCheckerTests
swift test --filter QuotaWakeCoreTests.BundleMetadataTests
swift test --filter QuotaWakeCoreTests.QuotaSourceLicenseTests

# Guard tests for removed wake-helper scope (kept quarantined):
swift test --filter QuotaWakeCoreTests.WakeHelperTests
```

## UI QA

Use fake Claude/Codex state for automated QA. These scenarios render the native
menu bar app surfaces and write screenshots/transcripts to the evidence
directory without calling live provider tools. `--fake-cli-root` is a stable
fixture path used in rendered UI state; for these screenshot scenarios, the
harness does not require executable fake binaries.

The evidence directory can be any writable directory. The `.omo/evidence/...`
path below is the project convention for recorded implementation evidence.

```bash
./Scripts/package_app.sh debug

./Scripts/ui_qa.sh \
  --fake-cli-root .build/fake-cli \
  --evidence-dir ../.omo/evidence/quotawake-mvp-implementation/task-local \
  --scenario popover-settings

./Scripts/ui_qa.sh \
  --fake-cli-root .build/fake-cli \
  --evidence-dir ../.omo/evidence/quotawake-mvp-implementation/task-local \
  --scenario missing-cli

./Scripts/ui_qa.sh \
  --fake-cli-root .build/fake-cli \
  --evidence-dir ../.omo/evidence/quotawake-mvp-implementation/task-local \
  --scenario first-run
```

Manual update check fixtures:

```bash
./Scripts/ui_qa.sh \
  --fake-cli-root .build/fake-cli \
  --evidence-dir ../.omo/evidence/quotawake-mvp-implementation/task-local \
  --scenario update-available \
  --update-fixture Tests/Fixtures/releases/latest-newer.json

./Scripts/ui_qa.sh \
  --fake-cli-root .build/fake-cli \
  --evidence-dir ../.omo/evidence/quotawake-mvp-implementation/task-local \
  --scenario update-error \
  --update-fixture Tests/Fixtures/releases/latest-malformed.json
```

`update-available` writes `settings-update-available.png` and `opened-url.txt`
through a fake URL opener. `update-error` writes `settings-update-error.png` and
must not write `opened-url.txt`.

## Reset-Aware Readiness Model

QuotaWake's active product model is reset-aware session readiness, not fixed
calendar scheduling. The app observes local quota-window signals, evaluates the
active-only gate, and sends a readiness prompt only when a candidate reset
window is due, the tool is enabled, cooldown/idempotency permits it, and the Mac
appears active.

Quota confidence labels are intentionally narrow:

- `observedLocalQuota`: local provider CLI state was observed, such as Codex
  `app-server` rate-limit data.
- `exactReset`: a bounded local CLI probe or sanitized CLI message included an
  explicit reset timestamp or relative reset interval.
- `estimatedFiveHour`: no exact local signal was available, so the candidate is
  estimated from the last successful readiness send plus five hours.
- `unknown`: QuotaWake does not know enough to send automatically in strict
  mode.
- `blocked`: auth, API-billing environment, usage-limit-without-reset, or other
  provider-blocking state prevents an automatic send.

Feedback-loop guardrails around the engine:

- Blocked/unavailable states are not permanent: once the stored state is older
  than about 15 minutes, the engine requests a re-observation so a one-time
  condition (logged out once, app-server briefly missing) self-heals.
- Automatic quota observations are throttled to one probe per tool per
  10 minutes; manual Observe is immediate.
- Skip logging is transition-based: the same gated candidate with the same
  reason logs once, not once per 60-second poll tick.

Provider boundary guardrails:

- Do not call Anthropic, OpenAI, Claude, or Codex provider HTTP APIs directly.
- Do not scrape provider dashboards or interactive TUI screens.
- Do not import cookies, OAuth tokens, browser sessions, WebView auth state, or
  provider tokens.
- Do not store raw provider transcripts, auth headers, API keys, cookies, or
  full debug logs.
- Do not run Claude or Codex as root, from a LaunchDaemon, or from any removed
  wake-helper path.

Codex quota observation may use the installed local `codex app-server`
JSON-RPC surface where present. That is a local CLI boundary, not a provider
HTTP integration.

## Live CLI Smoke

Automated tests and default UI QA use fake CLIs. Live Claude/Codex calls are
opt-in release/local QA only, never default automated QA. Before a release
candidate, run the billing-boundary smoke against the same installed official
local CLIs selected in Settings > Tools:

```bash
./Scripts/live_cli_smoke.sh \
  --billing-mode subscription-only \
  --evidence-dir ../.omo/evidence/quotawake-phase2-live-cli-tests/final/live-cli \
  --prompt hi
```

If more than one Codex binary exists, inspect the candidates and rerun with the
same path selected in Settings > Tools:

```bash
which -a codex
./Scripts/live_cli_smoke.sh \
  --billing-mode subscription-only \
  --codex-path /absolute/path/to/codex \
  --evidence-dir ../.omo/evidence/quotawake-phase2-live-cli-tests/final/live-cli \
  --prompt hi
```

`subscription-only` fails closed when Claude/API-billing environment such as
`ANTHROPIC_API_KEY`, OpenAI keys, gateway/base URL, or cloud billing keys is
present. Auth errors, usage limits, broken symlinks, missing CLI paths,
API-billing env, timeouts, nonzero exits, and empty responses are blocking smoke
failures. The script records failure classifications and reset-signal confidence
without env dumps, provider tokens, cookies, account IDs, or raw debug logs.

The packaged-app live Run Now release scenario is:

```bash
./Scripts/ui_qa.sh \
  --evidence-dir ../.omo/evidence/quotawake-phase2-live-cli-tests/final/live-app-run \
  --scenario live-run-now \
  --claude-path "$(command -v claude)" \
  --codex-path /absolute/path/to/codex
```

If this command reports an unknown scenario or path argument, the live app QA
gate is not implemented in that checkout and the release is blocked.

Self-test fixture coverage:

```bash
./Scripts/live_cli_smoke.sh \
  --self-test \
  --evidence-dir ../.omo/evidence/quotawake-phase4-reset-aware-readiness/task-7/live-smoke-selftest
```

Do not run live smoke as root or from removed wake-helper code.

## Version Bump

`version.env` is the source of truth:

```bash
VERSION=0.0.0
RELEASES_LATEST_API_URL=https://api.github.com/repos/jeongjin0/quotawake/releases/latest
```

When preparing a release:

1. Set `VERSION` to numeric SemVer `MAJOR.MINOR.PATCH`.
2. Use release tag `v${VERSION}`.
3. Run `./Scripts/package_app.sh release`.
4. Confirm `CFBundleShortVersionString`, `CFBundleVersion`, release notes, and
   `dist/QuotaWake-${VERSION}.dmg` use the same value.

Invalid values such as `1.2` must fail before packaging.

## Manual Update Check

The MVP update check is user-initiated from Settings > General. It reads public
GitHub Release metadata from `RELEASES_LATEST_API_URL`, strips an optional
leading `v` from `tag_name`, compares strict SemVer, and opens the `.dmg` asset
URL when a newer release exists. If no `.dmg` asset is present, it opens the
release page.

The app must not automatically download, install, relaunch, poll in the
background, use Sparkle, or use Tauri updater assets. Tests and UI QA must use
fixtures or injected fetchers/openers; automated checks must not call live
GitHub.

## Signing, Notarization, And DMG

`RELEASE.md` is the canonical release guide. Keep detailed Apple signing,
notarization, stapling, Gatekeeper, checksum, and Finder-presentation steps
there.

Release scripts expect these variables:

```bash
export QUOTAWAKE_SIGNING=developer-id
export QUOTAWAKE_DEVELOPER_ID_APPLICATION="Developer ID Application: ..."
export QUOTAWAKE_NOTARY_PROFILE="quotawake-notarize" # optional

# Or App Store Connect API credentials instead of a keychain profile:
export APP_STORE_CONNECT_API_KEY_P8="/absolute/path/AuthKey_XXXX.p8"
export APP_STORE_CONNECT_KEY_ID="..."
export APP_STORE_CONNECT_ISSUER_ID="..."
```

Release flow:

```bash
set -a
. ./version.env
set +a

swift test
swift build -c release
./Scripts/package_app.sh release
./Scripts/sign-and-notarize.sh --app QuotaWake.app
./Scripts/create_dmg.sh --app QuotaWake.app --output "dist/QuotaWake-${VERSION}.dmg" --capture-dir ".qa-captures/release-${VERSION}"
./Scripts/sign-and-notarize.sh --app QuotaWake.app --dmg "dist/QuotaWake-${VERSION}.dmg"
```

The first `sign-and-notarize.sh` command is app signing only. Raw `.app`
bundles are not submitted to `notarytool`; notarization runs only when the final
DMG archive is passed with `--dmg`. `create_dmg.sh --capture-dir` records DMG
build evidence only, not applied or measured Finder presentation metadata.
Follow the mounted-DMG Finder measurement gate in `RELEASE.md` before upload.

Do not hard-code personal Developer ID identities, notary credentials, private
keys, or keychain profile names in tracked files.

## Removed Wake Helper

Earlier prototypes included optional wake-helper support. Phase 4 removed it
from the active product and release flow: readiness prompts run only as the
logged-in user while QuotaWake is running, and the active-only gate suppresses
background sends during idle or unsuitable power states. Keep historical helper
code quarantined unless a future plan explicitly reintroduces it with new tests
and release gates.

## Troubleshooting

- Missing CLI: open Settings > Tools, choose a manual path, then run the tool
  test. GUI apps do not inherit an interactive shell PATH.
- Node runtime missing: npm-installed CLIs with `#!/usr/bin/env node` need
  `node` in the child PATH. Fix the Node install or choose a CLI path whose
  runtime is available.
- Unauthenticated Claude/Codex CLI: QuotaWake records the local command failure
  and exit details. Authentication remains owned by the official CLI.
- Timeout: the tool run is killed after the fixed 120-second execution timeout
  and logged as a timed-out readiness prompt. Timeouts are not user-configurable.
- Disabled Login Item: macOS can disable the login item in System Settings.
  Re-enable Launch at Login from Settings after resolving that state.
- Idle or suppressed power state: the active-only gate records a skip and does
  not run provider CLIs.
- Powered off, asleep, or unavailable: QuotaWake cannot send readiness prompts
  until the user session is running and active again.
- Update check failure: treat it as release metadata, invalid SemVer, missing
  asset fallback, or network failure. It is not an app authentication flow.

## Deferred Work

These are intentionally outside the MVP:

- Per-account schedules.
- Provider-side reset verification beyond explicit local signals.
- Custom command providers.
- Battery or weekend pause policies.
- Usage dashboards.
- Automatic update download/install/relaunch.
- Website work.
