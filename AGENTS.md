# QuotaWake Mac Notes

This directory owns the native macOS QuotaWake app.

## Read First

- Product spec and scope: `docs/MVP-SPEC.md`
- Code structure overview: `docs/ARCHITECTURE.md`
- Build, QA, and troubleshooting: `DEVELOPMENT.md`
- App shape and design system: `DESIGN.md`
- Release packaging: `RELEASE.md`
- Public readme: `README.md`
- Implementation plans live outside this repository under a machine-local
  `../.omo/` convention; they are not available in a fresh clone.

## Product Boundaries

- QuotaWake is a native SwiftUI/AppKit menu bar app, not Tauri, Electron, or a
  website surface.
- Use "usage window scheduling", "session readiness", and "quota window wake"
  language. Do not frame the app as quota bypassing or getting extra usage.
- The MVP invokes installed official `claude` and `codex` CLIs. It must not
  store provider tokens or call provider HTTP APIs directly.
- The readiness prompt runs as the logged-in user. Do not run Claude or Codex as
  root.

## Release Rules

- Public and prerelease manual downloads must be signed and notarized `.dmg`
  assets only.
- Version strings use SemVer `MAJOR.MINOR.PATCH` form, for example `0.0.0`.
  Keep `version.env`, app bundle metadata, release tags, and DMG filenames in
  sync.
- Do not publish `.app` bundles, `.zip` archives, debug builds, private logs,
  env dumps, secrets, updater-only assets, or helper staging files as user
  downloads.
- The MVP may include a manual "Check for Updates" UI that opens a release page
  or DMG URL. Do not implement automatic download, install, relaunch, Sparkle,
  or Tauri updater flows in the MVP.
- Public release candidates must pass Developer ID signing, Apple notarization,
  stapling, Gatekeeper validation, SHA-256 checksum, and mounted DMG Finder
  presentation checks before upload.
- Keep detailed signing, notarization, and DMG execution steps in `RELEASE.md`;
  do not duplicate the full process here.

## Removed Wake Helper Scope

- Do not call `pmset schedule cancelall`.
- Do not call `pmset repeat` or `pmset repeat cancel`.
- Phase 4 removed wake-helper installation and sleep-wake scheduling from the
  active MVP/release path, and the historical helper code
  (`WakeHelper`, `WakeHelperInstaller`, `WakeCoordinator`) has since been
  deleted from the tree (it remains in git history). Do not add active helper
  install, root helper, or `pmset schedule wake` behavior unless a future plan
  explicitly reintroduces it with fresh evidence.
- Any reintroduced helper must not overwrite unrelated launchd jobs, unrelated
  pmset schedules, or unrelated root-owned files.

## Useful Commands

Run these from `quotawake_mac/` unless a command says otherwise:

```bash
swift test
swift build -c debug
./Scripts/package_app.sh debug
./Scripts/create_dmg.sh --dry-run
```

Use fake Claude/Codex CLIs for automated tests and QA. Live provider calls
require explicit user approval.
