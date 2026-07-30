# QuotaWake Release Readiness

Assessment date: 2026-07-31

This document separates implementation confidence from distribution
confidence. A passing local build does not by itself make a cross-platform
binary safe to publish as a stable release.

## Decision

- **Stable cross-platform release: NO-GO.** Linux and Windows have not passed
  native build, package, service-lifecycle, and clean-machine runtime gates.
- **Stable downloadable macOS CLI archive: NO-GO.** The current arm64 archive
  is only linker/ad-hoc signed and is rejected by Gatekeeper (`spctl`).
- **macOS arm64 source/developer preview: GO, with constraints.** The CLI,
  reset-aware core, archive, and optional debug app build successfully on the
  current Mac. Install the binary into a durable path before registering the
  service, and do not run the app poller and CLI daemon together.
- **Private technical prerelease: CONDITIONAL GO.** Label it as a developer
  preview, publish only a checksum, list the tested architecture, and avoid
  claiming Linux or Windows support until their native gates pass.

## Confidence

| Surface | Confidence | Basis |
| --- | ---: | --- |
| Reset-aware core and provider safety boundaries | 85% | 166 automated tests plus the fake-provider live-smoke self-test pass on macOS |
| macOS arm64 manual CLI | 80% | Release build, help/status JSON, archive extraction, version, and checksum verified locally |
| macOS arm64 background service | 55% | launchd implementation exists, but install/start/stop/reboot behavior has no isolated lifecycle test |
| macOS downloadable CLI distribution | 35% | Archive works locally but Gatekeeper rejects its ad-hoc/linker signature |
| Linux CLI and daemon | 35% | Portability seams and CI workflow exist; no native build or `systemd-logind` service run has completed |
| Windows manual CLI | 20% | Build/package workflow exists but has not run; Swift runtime packaging is not verified |
| Windows automatic daemon | 10% | Activity is intentionally fail-closed, descendant cleanup is incomplete, and duplicate-daemon detection is not implemented |

These values are engineering confidence estimates, not probabilities derived
from production telemetry. QuotaWake currently has no release telemetry or
installed-user adoption evidence.

## Review convergence

The release was examined through four independent failure modes:

- **Correctness: conditional pass.** The decision engine is well tested, but
  daemon/service behavior is not covered at the operating-system boundary.
- **Safety: conditional pass.** Provider environment scrubbing, timeout
  handling, sanitization, and fail-closed activity behavior are strong; the
  unsigned downloadable CLI still fails the platform trust gate.
- **Installability: fail.** The service records the absolute path of whichever
  binary invoked `service install`, so running it from `.build` or a temporary
  extraction directory creates a fragile installation.
- **Portability: fail for general availability.** No native Linux or Windows
  artifact has passed the complete build-to-service path.

The lenses agree that a broad stable release is not ready. The one decision
that changes the immediate ship path is: **Is the next tag explicitly a
macOS-arm64 developer preview, or is it intended to be a stable
cross-platform release?** Only the first is supportable with current evidence.

## Risk register

### Release blockers

| ID | Severity | Risk | Required mitigation |
| --- | --- | --- | --- |
| R1 | P0 | macOS CLI archive is rejected by Gatekeeper | Developer ID sign and notarize the shipped CLI/package, or distribute through a trusted package-manager path; verify the exact downloaded artifact with `spctl` |
| R2 | P0 | Linux and Windows workflows have not run on the new code | Push a branch/PR and require green native jobs before publishing those platform assets |
| R3 | P0 | Linux/Windows clean-machine runtime dependencies are unknown | Run each archive on a clean supported OS without a Swift toolchain; package Swift runtime libraries or use an appropriate static-runtime build where required |

### High risks

| ID | Severity | Risk | Required mitigation |
| --- | --- | --- | --- |
| R4 | P1 | `service install` pins the current executable path | Add a supported installer/package-manager flow and refuse or clearly warn about transient `.build` and temporary paths |
| R5 | P1 | Linux activity currently requires `XDG_SESSION_ID`; a `systemd --user` service may not inherit it, and `loginctl` has no timeout | Discover the active graphical session robustly, bound the probe, expose the result in `doctor`, and test after login/reboot in a real Linux VM |
| R6 | P1 | Windows automatic safety/runtime is incomplete | Add a Win32 idle reader, Job Object descendant cleanup, and real duplicate-daemon detection before enabling automatic sends |
| R7 | P1 | The macOS app and CLI daemon can both own scheduling | Make the daemon the single scheduling owner, or add a cross-process ownership guard before shipping both as generally available |
| R8 | P1 | Service manager and daemon lease have no direct tests | Add definition-generation tests and native install/start/status/stop/uninstall scenarios for every supported OS |

### Medium risks

| ID | Severity | Risk | Required mitigation |
| --- | --- | --- | --- |
| R9 | P2 | `doctor` checks setup/provider paths but not actual service state or activity-adapter availability | Extend its JSON contract and exit status to cover those prerequisites |
| R10 | P2 | Only macOS arm64 is locally packaged | Build and test macOS x86_64 or publish an accurately labeled arm64-only preview |
| R11 | P2 | No supported binary installer or upgrade/uninstall flow exists | Add Homebrew first; add Windows package management only after Windows becomes a required gate |

The CLI archives now include QuotaWake's third-party notices and the complete
Apache 2.0 license for `swift-argument-parser`. That packaging issue was fixed
during this review and is no longer an open risk.

## Evidence recorded in this worktree

- Apple Swift 6.3.3, arm64 macOS host.
- `swift test`: 166 tests passed, 0 failures.
- `live_cli_smoke.sh --self-test`: all fake failure/safety scenarios passed,
  including timeout child cleanup and API-billing environment detection.
- macOS arm64 release CLI: built, archived, checksum-verified, extracted, and
  executed as version `0.0.1`.
- Optional debug `QuotaWake.app`: built and passed local ad-hoc signature
  verification.
- Standalone CLI trust check: `spctl` rejected the current archive binary.
- GitHub Action commit pins resolve upstream, but the new workflows have not
  run because the branch has not been pushed.
- No live Claude or Codex readiness prompt was sent during this assessment.
- No native Linux VM/container or Windows runner was available locally.

## Gates for a stable release

1. Install from the exact intended public artifact on a clean machine.
2. Run `setup`, `doctor`, `status --json`, fake `observe`, and fake `send`.
3. Test service install, status, reboot/login start, stop, restart, and
   uninstall without leaving state behind.
4. Prove duplicate daemons and app/daemon overlap cannot produce duplicate
   readiness sends.
5. Exercise timeout cleanup and activity fail-closed behavior natively.
6. Verify checksums, third-party notices, architecture labels, and runtime
   dependencies.
7. On macOS, pass Developer ID signature, notarization, and Gatekeeper checks.
8. Run the explicit subscription-only live provider gate only with release
   owner approval.

## Testing other platforms from this Mac

- Use GitHub Actions for reproducible Linux and Windows compiler/package
  checks.
- Use a Linux VM, not only a container, for `systemd --user`, logind session,
  login/reboot, idle detection, and service-lifecycle QA. A container remains
  useful for clean-runtime binary checks.
- Use a Windows hosted runner or Windows 11 ARM VM for Task Scheduler, process
  cleanup, path quoting, and login-start behavior. Cross-compilation alone is
  not evidence for those OS integrations.
