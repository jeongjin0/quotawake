# Error Log

## 2026-06-30 - QuotaWake menu bar item hidden on macOS

- Symptom: QuotaWake was running, but no recognizable QuotaWake item appeared in the macOS menu bar.
- User-facing trigger: the menu bar item had been changed from `QW` text to a generic gauge icon, and macOS also stopped displaying items for the original bundle ID.
- Diagnosis:
  - `NSStatusItem` existed in-app and the popover could be opened from app reopen.
  - A minimal status item app appeared with a different bundle ID, but did not appear when using `com.jeongjin.quotawake`.
  - System Settings listed QuotaWake under Menu Bar app items, but toggling it did not restore display.
  - LaunchServices had multiple stale `/Applications/QuotaWake.backup.*.app` entries with the same bundle ID.
- Fix:
  - Restored a visible text status item: `QW`, fixed width, centered, text-only.
  - Changed the app bundle ID to `com.jeongjin.quotawake.menubar` to escape the corrupted macOS menu bar state attached to the old bundle ID.
  - Moved stale `/Applications/QuotaWake.backup.*.app` bundles to `/Users/jeongjin/Desktop/Project/quotawake/_local_app_backups/`.
- Verification:
  - `swift test --filter BundleMetadataTests`: 5 tests passed.
  - `swift test`: 127 tests passed.
  - Repackaged and installed `/Applications/QuotaWake.app`.
  - Verified installed bundle ID: `com.jeongjin.quotawake.menubar`.
  - Verified `LSUIElement=true`.
  - Verified `QW` appears in the macOS menu bar.
- Follow-up:
  - Launch-at-login may need to be re-enabled once because the main app bundle ID changed.
