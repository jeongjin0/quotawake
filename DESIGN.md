# QuotaWake Mac Design System

## 1. Atmosphere & Identity

QuotaWake feels like a quiet Mac utility: compact, trustworthy, and easy to scan from the menu bar. The signature is "readiness at a glance" - a restrained status surface that makes the current quota-window readiness state, enabled tools, and recent result immediately clear without turning into a dashboard.

## 2. Color

### Palette

| Role | Token | Light | Dark | Usage |
| --- | --- | --- | --- | --- |
| Surface/primary | `surfacePrimary` | system window background | system window background | Settings window base |
| Surface/elevated | `surfaceElevated` | popover background | popover background | Menu bar popover, panels |
| Surface/glass | `popoverGlassMaterial` | native popover/sidebar material | native popover/sidebar material | Translucent menu bar popover shell |
| Surface/glass stroke | `popoverGlassStroke` | separator with reduced opacity | separator with reduced opacity | Glass edge, provider card outline |
| Surface/secondary | `surfaceSecondary` | control background | control background | Group boxes, table rows |
| Text/primary | `textPrimary` | primary label | primary label | Main labels, values |
| Text/secondary | `textSecondary` | secondary label | secondary label | Metadata, helper values |
| Text/tertiary | `textTertiary` | tertiary label | tertiary label | Empty states, disabled copy |
| Border/default | `borderDefault` | separator | separator | Dividers and table separators |
| Accent/primary | `accentPrimary` | system accent | system accent | Focus, selected tab, primary action |
| Status/success | `statusSuccess` | system green | system green | Sent/success state |
| Status/warning | `statusWarning` | system orange | system orange | Skipped/missing setup |
| Status/error | `statusError` | system red | system red | Failed/error state |
| Status/info | `statusInfo` | system blue | system blue | Checking/update info |
| Provider/Claude accent | `providerClaudeAccent` | `#D97757` | `#D97757` | Claude identity mark, non-status emphasis |
| Provider/Claude wash | `providerClaudeWash` | low-opacity `#D97757` tint | low-opacity `#D97757` tint | Claude card accent rail or identity fill |
| Provider/Codex accent | `providerCodexAccent` | `#0D0D0D` | `#0D0D0D` | Codex identity mark, non-status emphasis |
| Provider/Codex wash | `providerCodexWash` | low-opacity `#0D0D0D` tint | low-opacity `#0D0D0D` tint | Codex card accent rail or identity fill |

### Rules

- The shipped app uses surface-specific appearance rules: the menu bar popover
  renders in a fixed light glass theme (`QWTheme`), while the Settings window
  follows the active macOS appearance through system colors in
  `QWSettingsTheme`. Production Settings views must not force `.light` or
  `.dark`; UI QA may render both modes explicitly for evidence. Color values are
  defined once as named constants in the theme types, not scattered per-view.
- Provider identity accents are fixed brand values: Claude `#D97757` (warm
  coral), Codex `#0D0D0D` (near-black). They are identity tokens, not status
  tokens.
- Accent color is reserved for focus, selected state, links, and the strongest
  action in a view.
- Status must pair color with visible text or a status glyph; never depend on color alone or color only status.
- Do not introduce decorative gradients, orbs, one-off bright palettes, marketing color blocks, or ad-hoc per-view hex values outside the named theme constants.

## 3. Typography

### Scale

| Level | Size | Weight | Line Height | Tracking | Usage |
| --- | --- | --- | --- | --- | --- |
| Window title | 20pt | 600 | system | 0 | Settings pane title |
| Section title | 14pt | 600 | system | 0 | Group headings |
| Body | 13pt | 400 | system | 0 | Standard labels and values |
| Body emphasis | 13pt | 600 | system | 0 | Status values, selected labels |
| Caption | 11pt | 400-500 | system | 0 | Timestamps, paths, small metadata |
| Mono caption | 11pt | 400 | system | 0 | CLI paths and fixed values |

### Font Stack

- Primary: SF Pro through `.system` / `.body` / `.callout` / `.caption`.
- Mono: SF Mono through `.system(.caption, design: .monospaced)`.

### Rules

- Use dynamic type-compatible SwiftUI fonts where possible.
- Do not scale type with window or viewport width.
- Keep text compact and no smaller than 11pt in app UI, with one allowed exception: compact inline chips (e.g. the Observe chip) may use 10.5pt.

## 4. Spacing & Layout

### Base Unit

All spacing derives from a 4pt base.

| Token | Value | Usage |
| --- | --- | --- |
| `space1` | 4pt | Icon-label gaps, tight row details |
| `space2` | 8pt | Row gaps, control grouping |
| `space3` | 12pt | Compact group padding |
| `space4` | 16pt | Default panel padding |
| `space5` | 20pt | Settings inner section spacing |
| `space6` | 24pt | Pane padding and major groups |

### Layout

- Popover: fixed 360x580pt so status changes never cause resize jitter.
- Settings window: 980x680pt default, 720x520pt minimum. The first-run setup window uses 720x520pt minimum.
- Use a native sidebar-list structure for Settings, not a rounded sidebar island, nested cards, or tab-like marketing panels.
- Rows use stable min heights so status changes do not shift the whole view.
- Settings rows use a stable label/control column rhythm; long controls can move
  below their labels, but they must not overlap adjacent values or resize the
  window.
- Provider quota cards use a stable compact footprint: provider header, quota progress bar, reset countdown line, and only conditional diagnostic detail.
- The bottom menu footer is separated from provider content by a hairline divider and uses compact icon+text chips: Reload, Pause/Resume, and Settings grouped at the leading edge, Quit at the trailing edge (see Popover Menu Footer below).

### Rules

- No nested UI cards. Use grouped rows, dividers, native `Form`, `Table`, and `GroupBox` patterns.
- Prefer dense, organized information over landing-page spacing.
- Long paths, prompts, and summaries must truncate in the middle or tail with
  tooltips/copy affordances later. They must remain readable at the 720x520pt
  Settings minimum.
- Do not build nested card stacks in the popover; provider quota cards sit directly on the glass shell.

## 5. Components

### Status Row

- **Structure**: label, value, optional status dot/icon.
- **Variants**: neutral, success, warning, error, info.
- **Spacing**: `space2` horizontal gap, `space1` value detail gap.
- **States**: normal, disabled, stale.
- **Accessibility**: value text must carry the semantic status, not color alone.

### Provider Quota Card

- **Structure**: a single column card. Top row = provider identity mark and provider name. Below: a 5h quota-window section followed by a Weekly Limit section. Both quota-window sections use the same label/value/bar/reset-footnote rhythm so weekly is treated as a peer signal rather than a muted footer.
- **Identity accents**: Claude `#D97757` (warm coral), Codex `#0D0D0D` (near-black). The accent appears only on the identity mark and bar fill — never as a card background wash.
- **Variants**: per-window known / unknown. When a window has no local signal the bar renders a diagonal striped track; the 5h section shows "No local quota signal yet" with an inline `Observe` chip.
- **Reset labels**: 5h and weekly reset countdowns are shown inside their own quota-window sections. Do not put an unlabeled countdown or next-due badge in the card header.
- **Spacing**: `space3` padding, `space2`–`space3` row gaps, `space1` gaps inside compact metadata lines.
- **Surface**: a neutral translucent white card (≈0.55 opacity for the next-due provider, ≈0.42 for others) on the glass popover shell with a hairline stroke; one card per provider, never nested colored panels.
- **States**: identity accent stays stable so provider identity never relies on text alone.
- **Accessibility**: provider name, 5h quota, weekly quota, reset countdowns, and status are visible text or accessible labels; the striped track is decorative and hidden from accessibility.
- **Visibility**: the popover renders provider quota cards only for enabled tools whose CLI is detected and runnable. Missing, invalid, disabled, or broken tools are surfaced through the status pill and Settings tools pane, not as normal quota cards.

### Weekly Limit Row

- **Structure**: a peer quota-window readout at the bottom of each provider card — "Weekly limit" label, a percent value ("62% left" / "Unknown"), the same thin accent bar treatment as the 5h row, and its own "Resets in Xd" line when known.
- **Source**: Codex's secondary rate-limit window and Claude's `/usage` "current week" line; both are best-effort and degrade to a striped "Unknown" track when no signal is present.
- **Rules**: the weekly bar uses the provider accent and bar height consistently with the 5h window. Vertical placement and section labels separate the two windows, not a divider, reduced opacity, or smaller geometry.

### Recent Activity

- **Structure**: a small `RECENT ACTIVITY` section header with an "All logs" link, followed by up to three compact log rows (status dot, `HH:MM` time, provider, status text).
- **States**: empty ("No readiness runs yet"); populated. The "All logs" link opens the Logs settings pane.
- **Accessibility**: rows combine into a single readable label; status is carried by text, not the dot color alone.

### Popover Secondary Actions

- **Structure**: per-context inline actions rather than a standalone button row. The unknown-quota state surfaces an inline `Observe` chip on the affected provider card; manual refresh lives as `Reload` in the footer.
- **Variants**: inline chip (Observe), footer chip (Reload).
- **States**: shown only when meaningful — `Observe` appears when a provider has no local quota signal.
- **Accessibility**: labels are explicit and keyboard-focusable.

### Popover Menu Footer

- **Structure**: a horizontal footer below a hairline divider. Reload, Pause/Resume, and Settings are grouped at the leading edge; Quit sits at the trailing edge as a destructive (error-tinted) chip. Each item is icon + text (`↻ Reload`, `⏸ Pause`/`▶ Resume`, `⚙ Settings`, `⏻ Quit`).
- **Actions**: Reload refreshes the observed quota; Pause/Resume toggles background readiness; Settings opens the settings window; Quit terminates the app.
- **Variants**: normal chip, destructive Quit chip; the Pause chip swaps its label and icon with the paused state.
- **Spacing**: compact chip padding, `space2` grouping, divider above footer.
- **States**: normal, pressed, disabled only when an action is temporarily unavailable.
- **Accessibility**: footer actions must show visible text; do not hide Reload, Settings, or Quit behind icon-only controls.

### Settings Pane

- **Structure**: sidebar section list plus detail pane, or equivalent native Settings grouping.
- **Variants**: General, Tools, Window Readiness, Prompt, Logs.
- **Spacing**: `space6` outer padding, `space4` group padding, 240pt label column for standard rows, compact 52pt row minimums.
- **States**: normal, error banner, disabled controls, pressed buttons, focused text inputs, light appearance, dark appearance, and 720x520pt resize minimum.
- **Accessibility**: each control has a visible label and native focus ring.
- **Rules**: segmented controls and multiline editors use below-label placement.
  General toggles, steppers, and short actions use trailing placement. Action
  groups may use full-width placement when buttons need to wrap.

### Log Table

- **Structure**: time, tool, status, duration, exit code, summary.
- **Variants**: empty, populated, error rows.
- **Spacing**: native list-style row metrics with stable column widths and a
  horizontal scroll fallback at the Settings minimum.
- **States**: selected row, empty state.
- **Accessibility**: column headers remain visible and summaries are text, not color-only. Empty logs render an explicit empty state.

## 6. Motion & Interaction

### Timing

| Type | Duration | Easing | Usage |
| --- | --- | --- | --- |
| Micro | 100-150ms | ease-out | Button/toggle feedback |
| Standard | 180-240ms | ease-in-out | Popover content state changes |

### Rules

- Keep motion native and minimal. Use SwiftUI/AppKit default control transitions unless there is a clear usability reason.
- Never animate layout-heavy resizing for status rows or logs.
- Respect Reduce Motion automatically by using native controls and avoiding custom continuous animation.

## 7. Depth & Surface

### Strategy

Use native material/vibrancy, tonal shift, and separators.

| Type | Treatment | Usage |
| --- | --- | --- |
| Primary surface | system window/popover background | App shell |
| Glass popover shell | native popover/sidebar material with subtle vibrancy | Menu bar quota cockpit |
| Glass edge | reduced-opacity separator stroke | Popover outline and card outlines |
| Secondary surface | native grouped background | Settings groups and log rows |
| Separator | native separator color | Section and row boundaries |
| Elevation | native popover/window shadow only | OS-owned windows/popovers |

### Rules

- Do not add custom heavy shadows.
- Use native popover/window depth and material instead of decorative containers.
- The glass treatment is a translucent native utility surface, not a decorative gradient, blurred orb, or marketing hero treatment.
- Glass-only tonal treatment is allowed for the popover shell when paired with readable text, native separators, and explicit provider structure.
- Provider quota cards may use a quiet glass stroke and identity accent, but must not become stacked promotional cards or color blocks.
- Controls should feel like macOS controls, not a web dashboard port.
