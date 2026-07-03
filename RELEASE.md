# QuotaWake Mac Release Guide

This is the release path for QuotaWake Mac public and prerelease builds.
QuotaWake is a native SwiftUI/AppKit app, so this guide keeps the reusable
macOS signing and DMG gates from the local reference release process while
excluding Tauri automatic-updater-specific assets and commands.

## Release Channel

- Manual download asset: signed and notarized `.dmg` only.
- The `.dmg` must install `QuotaWake.app` by drag-to-Applications.
- Never publish `.app` bundles, `.zip` archives, private build logs, env dumps,
  secrets, debug builds, or root-helper staging files as user downloads.
- Prerelease `.dmg` assets are release candidates, not lower-grade builds. If a
  tester can download the binary, it must pass the same signing, notarization,
  Gatekeeper, checksum, and DMG presentation gates as a stable release.
- The MVP has no automatic updater channel. Do not create or attach Tauri-style
  `latest.json`, `.app.tar.gz`, `.sig`, updater private keys, or auto-update
  policy metadata for QuotaWake MVP releases.
- The app may use public GitHub Release metadata for a manual "Check for
  Updates" button. That check may open a browser to the release page or DMG
  asset; it must not auto-download, auto-install, or relaunch the app.

## Assumed Location And Variables

Run commands from `quotawake_mac/` unless a command explicitly says otherwise.
This document is the contract the release scripts in `Scripts/` must satisfy.

Set release variables once per release:

```bash
export VERSION="<version-from-version.env>"
export PREVIOUS_TAG="v<previous-version>"
export CURRENT_TAG="v${VERSION}"
export RELEASE_DATE="$(date +%Y%m%d)"
export CAPTURE_DIR=".qa-captures/${RELEASE_DATE}-release-${VERSION}"
export DMG_PATH="dist/QuotaWake-${VERSION}.dmg"
export RELEASES_LATEST_API_URL="https://api.github.com/repos/jeongjin0/quotawake/releases/latest"
```

`VERSION` comes from `version.env`. It must be
numeric SemVer in `MAJOR.MINOR.PATCH` form, for example `0.0.0`; the release
tag is `v${VERSION}`. Release notes use `PREVIOUS_TAG` and `CURRENT_TAG`; DMG
packaging and evidence capture use `VERSION`, `CAPTURE_DIR`, and `DMG_PATH`.
The app bundle's `CFBundleShortVersionString` and `CFBundleVersion` should be
derived from the same `VERSION`.

## Local Secrets

Do not hard-code personal Developer ID identities or notarization credentials in
scripts or docs. Release scripts should read them from the environment or a local
keychain profile.

Canonical environment contract:

```bash
export QUOTAWAKE_SIGNING=developer-id
export QUOTAWAKE_DEVELOPER_ID_APPLICATION="Developer ID Application: ..."
export QUOTAWAKE_NOTARY_PROFILE="quotawake-notarize" # optional keychain profile

# If the script uses App Store Connect API credentials instead of a profile:
export APP_STORE_CONNECT_API_KEY_P8="/absolute/path/AuthKey_XXXX.p8"
export APP_STORE_CONNECT_KEY_ID="..."
export APP_STORE_CONNECT_ISSUER_ID="..."
```

For a local release workstation, optional defaults may live in ignored
`.release.local.env`, for example a keychain profile alias or signing identity.
Do not commit that file.

Keep private keys and profiles out of git, logs, issue bodies, release notes,
and uploaded artifacts.

## Timestamp Preflight

Before any Developer ID signing step, verify that Apple's timestamp service is
reachable from the current network. Captive portals can break
`codesign --timestamp` even when normal HTTPS browsing works.

```bash
tmp_payload="$(mktemp)"
tmp_query="$(mktemp)"
tmp_reply="$(mktemp)"
printf 'quotawake timestamp preflight' > "$tmp_payload"
openssl ts -query -data "$tmp_payload" -sha256 -cert -out "$tmp_query"
curl --fail --http1.1 \
  -H 'Content-Type: application/timestamp-query' \
  --data-binary @"$tmp_query" \
  http://timestamp.apple.com/ts01 \
  -o "$tmp_reply"
openssl ts -reply -in "$tmp_reply" -text | grep 'Status: Granted'
rm -f "$tmp_payload" "$tmp_query" "$tmp_reply"
```

If this fails or returns a login page, fix the network first. Do not continue
with release signing until the timestamp reply is granted.

## Build And Package

The implementation scripts are expected to live under `Scripts/`:

```bash
./Scripts/build_release_dmg.sh \
  --capture-dir "$CAPTURE_DIR" \
  --output "$DMG_PATH"
```

`Scripts/build_release_dmg.sh` is the default public/prerelease DMG builder. It
runs tests, builds and packages the release app, signs the app, creates the DMG,
signs/notarizes/staples the final DMG, then runs signing, Gatekeeper, stapler,
Finder-presentation, and checksum verification. Use the manual commands below
only for debugging a failed step or re-signing an existing app with
`--skip-build`.

Manual build steps, when debugging:

```bash
swift test
swift build -c release
./Scripts/package_app.sh release
```

`Scripts/package_app.sh release` should assemble
`QuotaWake.app`, write and lint `Info.plist`, include resources, and
prepare the app bundle for release signing. It should not submit to Apple
notarization. The app ships no helper binaries (the wake helper was removed
from the active release path; see Removed Wake Helper below).

`Scripts/sign-and-notarize.sh` owns release signing and final DMG notarization.
App-only mode is sign-only because `notarytool` does not accept a
raw `.app` bundle.

Release app signing must use hardened runtime:

```bash
./Scripts/sign-and-notarize.sh --app QuotaWake.app --dry-run
./Scripts/sign-and-notarize.sh --app QuotaWake.app
codesign --verify --deep --strict --verbose=2 QuotaWake.app
```

The app-only dry run does not require Apple credentials and should report that
no raw `.app` notarization will be attempted. Gatekeeper validation is required
on the final signed and notarized DMG in the verification step below.

The app must not use the Mac App Store sandbox entitlement in the MVP because it
launches user-installed Claude/Codex CLIs. Phase 4 releases do not install a
wake helper.

## DMG Creation

Create the final public installer from the signed app:

```bash
./Scripts/create_dmg.sh \
  --app QuotaWake.app \
  --output "$DMG_PATH" \
  --capture-dir "$CAPTURE_DIR"
```

The DMG script should:

- create a staging directory containing `QuotaWake.app` and an `Applications`
  symlink;
- set the volume name to `QuotaWake`;
- apply Finder presentation metadata before compression;
- convert to a compressed read-only DMG;
- write build and Finder presentation evidence when `--capture-dir` is supplied;
- print the SHA-256 digest.

After DMG creation, run release signing/notarization on the final DMG:

```bash
./Scripts/sign-and-notarize.sh --app QuotaWake.app --dmg "$DMG_PATH"
```

That script signs the DMG with the Developer ID Application identity, submits
the DMG to Apple notarization with `xcrun notarytool submit --wait`, staples the
ticket with `xcrun stapler staple`, and validates the result.

Target QuotaWake DMG presentation contract for the manual release gate:

- volume name: `QuotaWake`;
- window bounds: `{160, 120, 760, 500}`;
- `QuotaWake.app` icon position: `{180, 170}`;
- `Applications` symlink position: `{480, 170}`;
- icon size: `128`;
- text size: `16`;
- generated background asset inside the mounted DMG:
  `.background/background.png`;
- mounted installer screenshot showing the visible install surface.

If the final design assets choose different values, update this contract before
release. A mounted DMG that falls back to default Finder icon size, text size,
or layout fails the release gate.

Do not treat an unsigned intermediate DMG as release-ready. Finder presentation
can drift silently, so the final mounted artifact must be checked after
compression, signing, notarization, and stapling.

## Required Verification Before Upload

Run these checks on the final packaged app and upload DMG, then copy the results
into the GitHub Release body. Upload only the `.dmg` named by `$DMG_PATH`.

```bash
codesign --verify --deep --strict --verbose=2 QuotaWake.app
codesign --verify --verbose=2 "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"
shasum -a 256 "$DMG_PATH"
```

Live provider checks are opt-in release gates, not default automated QA. Before
uploading a public or prerelease DMG, the release owner must also pass the live
CLI smoke and packaged-app Run Now gates in the sections below, or record the
blocking auth, usage, path, or API-billing failure and stop the release.

Final DMG presentation verification:

```bash
./Scripts/verify_dmg_presentation.sh --dmg "$DMG_PATH" --capture-dir "$CAPTURE_DIR"
```

The mounted Finder window must show the intended QuotaWake install surface, not
Finder defaults. `Scripts/verify_dmg_presentation.sh` gates on mounted window
bounds, icon size, text size, icon positions, visible items, and the presence of
`.background/background.png`. It deliberately does not gate on Finder's
`background picture` AppleScript getter because current macOS Finder can return
AppleEvent `-10000` even when the mounted window and background asset are
present; the screenshot is the review evidence for the visible background.

The capture directory should include:

- `dmg-build-evidence.txt` from `Scripts/create_dmg.sh --capture-dir`
- `finder-presentation.txt` from `Scripts/verify_dmg_presentation.sh`
- `dmg-finder-window.png`
- command output for signing, notarization, Gatekeeper, and checksum checks

Do not upload a public or prerelease `.dmg` unless all checks pass.

## Live CLI Smoke

Automated QA uses fake Claude/Codex binaries to avoid provider side effects.
Every release candidate must also pass one credentialed, subscription-only
smoke against the installed official local CLIs:

```bash
./Scripts/live_cli_smoke.sh \
  --billing-mode subscription-only \
  --evidence-dir "../.omo/evidence/quotawake-phase2-live-cli-tests/release-${VERSION}/live-cli" \
  --prompt hi
```

If multiple Codex installs are present, choose the intended one explicitly:

```bash
which -a codex
./Scripts/live_cli_smoke.sh \
  --billing-mode subscription-only \
  --codex-path /absolute/path/to/codex \
  --evidence-dir "../.omo/evidence/quotawake-phase2-live-cli-tests/release-${VERSION}/live-cli" \
  --prompt hi
```

Expected result: the script exits `0` and writes sanitized JSON/text evidence.
Missing CLI, broken symlink, auth-required, usage-limit, timeout, nonzero exit,
empty output, and `ANTHROPIC_API_KEY`/OpenAI key/gateway/cloud API-billing
environment classifications block release. QuotaWake invokes installed official
local CLIs only; it does not call provider HTTP APIs directly, scrape provider
dashboards, import cookies/OAuth/WebView auth state, or store provider tokens.
The evidence may include reset-signal confidence so release reviewers can
distinguish exact observed reset messages from unknown quota state.

Then run the packaged app scenario against the same selected paths:

```bash
./Scripts/ui_qa.sh \
  --evidence-dir "../.omo/evidence/quotawake-phase2-live-cli-tests/release-${VERSION}/live-app-run" \
  --scenario live-run-now \
  --claude-path "$(command -v claude)" \
  --codex-path /absolute/path/to/codex
```

The app scenario must show local logs for Claude and Codex with `sent` status
and clean up the launched app process. If the script reports an unknown scenario
or path argument, the live app QA gate is not implemented in that checkout and
the release is blocked. Never run live smoke as root or from removed wake-helper
code.

## Reset-Aware Readiness Release Gate

Before upload, release evidence must show that the shipped app uses reset-aware
readiness rather than fixed calendar scheduling:

- no active setup or release flow asks users to choose fixed run times or days;
- automatic sends require a due reset candidate, enabled tool, active Mac,
  cooldown clearance, and idempotency clearance;
- local quota-source hierarchy is documented as observed local quota, exact
  observed reset, estimated 5-hour candidate, then unknown quota state;
- unknown quota state does not produce automatic sends in strict mode;
- the active-only gate records idle or suppressed power states as skips;
- provider boundary scans find no direct provider HTTP integration, dashboard
  scraping, cookie import, OAuth-token extraction, WebView auth import, or
  provider-token storage claims.

If CodexBar source or algorithms are copied or substantially adapted in a
release, preserve its MIT license notice and record the attribution in the
release evidence. Reference-only research does not require vendored source
notice in the binary, but the release notes should avoid implying QuotaWake is a
CodexBar distribution.

## Manual Update Check Metadata

QuotaWake MVP's update UI is a manual release check, not an automatic updater.
The public app should check:

```text
https://api.github.com/repos/jeongjin0/quotawake/releases/latest
```

Expected release metadata contract:

- release tag is `v<VERSION>`, for example `v0.0.0`;
- the latest release has one public `.dmg` asset named
  `QuotaWake-${VERSION}.dmg`;
- the release body includes the `.dmg` SHA-256 digest and verification summary;
- the release `html_url` is safe to open if the app cannot find a `.dmg` asset.

The app compares the local bundle version against the latest release tag after
stripping an optional leading `v`. If a newer version exists, Settings may show
a button such as `Download QuotaWake <VERSION>` that opens the `.dmg` asset or
release page with `NSWorkspace`. The MVP must not download the file in-process,
install over the current app, relaunch, or use Sparkle/Tauri updater assets.

## Removed Wake Helper

Earlier QuotaWake prototypes had optional wake-helper release checks. Phase 4
removed wake-helper installation from the active release path. Do not package,
stage, notarize, document, or test a wake helper for a release unless a future
plan explicitly reintroduces it with fresh scope, tests, and release gates.

## Release Notes

Before creating or editing a GitHub Release, write notes from the actual
tag-range diff, not memory:

```bash
git log --oneline "$PREVIOUS_TAG..$CURRENT_TAG"
git diff --stat "$PREVIOUS_TAG..$CURRENT_TAG"
```

Use the release body sections:

- `Summary`
- `Diff basis`
- `Changes`
- `Downloads`
- `Verification`
- `Notes`

In `Downloads`, list the `.dmg` filename and SHA-256 digest. In `Verification`,
list only checks actually run for that release.

## Troubleshooting

- Timestamp preflight fails: authenticate captive portal or switch networks,
  then rerun the preflight before signing.
- `notarytool` rejects the artifact: inspect the notarization log, fix the
  signed app or nested helper issue, rebuild, and resubmit.
- `stapler validate` fails: do not upload; staple again only after the notary
  submission is accepted for the exact artifact.
- `spctl` rejects the DMG: treat Gatekeeper as failed even if notarization
  succeeded.
- Mounted DMG shows default Finder icon size/text size/layout: rebuild from the
  chosen Finder presentation process before signing and notarizing again.

## End-To-End Checklist

1. Set `VERSION`, `PREVIOUS_TAG`, `CURRENT_TAG`, `RELEASE_DATE`, `CAPTURE_DIR`,
   and `DMG_PATH`.
2. Confirm `QUOTAWAKE_DEVELOPER_ID_APPLICATION` and either
   `QUOTAWAKE_NOTARY_PROFILE` or App Store Connect API credentials are present,
   directly or through ignored `.release.local.env`.
3. Run `./Scripts/build_release_dmg.sh --capture-dir "$CAPTURE_DIR" --output "$DMG_PATH"`.
4. Run required Finder presentation
   checks.
5. Run the live CLI smoke for Claude and Codex.
6. Verify reset-aware readiness evidence and provider-boundary scans.
7. Confirm the GitHub Release tag and `.dmg` asset satisfy the manual update
   check metadata contract.
8. Write release notes from `git log` and `git diff --stat`.
9. Upload only `$DMG_PATH`; include SHA-256 and verification evidence in the
   release body.
