# QuotaWake Notes

This repository owns the cross-platform QuotaWake CLI/daemon and the optional
native macOS menu bar interface.

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

- The lowercase `quotawake` CLI and its per-user daemon are the primary product
  surface. The SwiftUI/AppKit menu bar app is optional and macOS-only.
- Keep shared decision logic, parsing, persistence, and provider adapters in
  `QuotaWakeCore`; do not make cross-platform behavior depend on AppKit.
- Use "usage window scheduling", "session readiness", and "quota window wake"
  language. Do not frame the app as quota bypassing or getting extra usage.
- QuotaWake invokes installed official `claude` and `codex` CLIs. It must not
  store provider tokens or call provider HTTP APIs directly.
- The readiness prompt runs as the logged-in user. Do not run Claude or Codex as
  root.
- Automatic activity gating must fail closed when a platform cannot establish
  that the user session is active. Headless always-active behavior requires an
  explicit future product decision.

## Release Rules

- CLI previews may be packaged as checksummed `.tar.gz` files for macOS/Linux
  and `.zip` files for Windows. Do not attach them to a public release until
  their native-platform build and smoke gates pass.
- The optional macOS GUI continues to ship only as a signed and notarized `.dmg`.
- Version strings use SemVer `MAJOR.MINOR.PATCH` form, for example `0.0.0`.
  Keep `version.env`, CLI version output, app bundle metadata, release tags,
  archives, and DMG filenames in sync.
- Do not publish raw `.app` bundles, debug builds, private logs, env dumps,
  secrets, updater-only assets, or helper staging files as user downloads.
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

Run these from the repository root unless a command says otherwise:

```bash
swift test
swift build -c debug --product quotawake
swift run quotawake --help
./Scripts/package_app.sh debug
./Scripts/package_cli.sh release
./Scripts/create_dmg.sh --dry-run
```

Use fake Claude/Codex CLIs for automated tests and QA. Live provider calls
require explicit user approval.
