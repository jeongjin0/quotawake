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
| Hero countdown | 30pt | 600 rounded, monospaced digits | system | 0 | Popover "Next reset" countdown only |
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
- Keep text compact and no smaller than 11pt in app UI, with two allowed exceptions: compact inline card metadata and quiet captions (e.g. the gate note) may use 10.5pt, and tracked uppercase eyebrows (`NEXT RESET`, `RECENT ACTIVITY`) may use 10pt bold.

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

- Popover: fixed 306x500pt (`PopoverMetrics.size`) so status and tab changes never cause resize jitter.
- Settings window: 980x680pt default, 720x520pt minimum. The first-run setup window uses 720x520pt minimum.
- Use a native sidebar-list structure for Settings, not a rounded sidebar island, nested cards, or tab-like marketing panels.
- Rows use stable min heights so status changes do not shift the whole view.
- Settings rows use a stable label/control column rhythm; long controls can move
  below their labels, but they must not overlap adjacent values or resize the
  window.
- The popover reads top-down as: quiet header (13pt app name + status pill), provider tab bar (Overview plus one tab per runnable provider), the selected tab's content, one global gate note, footer. The Overview tab holds the "Next reset" hero, compact provider summary rows, and recent activity; a provider tab holds that provider's full quota detail.
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

### Popover Tab Bar

- **Structure**: a segmented row under the header — `Overview` plus one tab per runnable provider, each icon + label (grid glyph for Overview, mini identity mark for providers). Providers appear as tabs only when enabled and runnable, so the bar scales as providers are added.
- **Variants**: selected (near-opaque white chip, ink text, hairline stroke) and unselected (secondary ink, transparent). Selection is view state; it falls back to Overview if the selected provider stops being runnable.
- **Rules**: the tab bar decides whose data the popover shows — Overview aggregates, a provider tab shows only that provider. Never mix providers inside a provider tab.
- **Accessibility**: tabs are buttons with visible labels and a selected trait.

### Next Reset Hero

- **Structure**: the Overview tab's signature element, directly under the tab bar. A small `NEXT RESET` eyebrow, then the earliest observed 5h reset candidate across runnable providers as a 30pt rounded semibold countdown ("45m", "Due now") with a one-line two-tone subline: provider + window label (semibold secondary ink) and "· at HH:MM" (tertiary ink).
- **Variants**: known candidate; waiting state. With no local reset signal the hero renders "Waiting for a quota signal" (15pt semibold secondary) over a "Reload to check now" caption — no oversized glyphs or placeholder dashes.
- **Rules**: the hero states an observed local reset candidate, never provider-verified language. It is the only element allowed the hero countdown type level; keep everything around it quiet.
- **Accessibility**: the hero combines into one label, e.g. "Next reset in 45m, Claude · 5h window, at 18:04".

### Provider Summary Row (Overview)

- **Structure**: one compact tappable row per runnable provider inside a single grouped card, separated by hairlines. Each row: identity mark, provider name, a trailing "58% left · 45m" two-tone value (5h remaining + reset countdown), a small chevron, and a thin 5h quota bar underneath. Tapping the row opens that provider's tab.
- **Identity accents**: Claude `#D97757` (warm coral), Codex `#0D0D0D` (near-black). The accent appears only on the identity mark and bar fill — never as a row background wash.
- **Variants**: known ("58% left · 45m") / unknown ("No signal" with a striped track). Quota state refreshes automatically, so rows carry no inline action beyond navigation.
- **Notes**: global facts stay out of rows — the active-use gate note renders once above the footer, not per row.
- **Accessibility**: each row combines into one label that names the provider, the 5h state, and that it opens the provider detail.
- **Visibility**: summary rows and provider tabs render only for enabled tools whose CLI is detected and runnable. Missing, invalid, disabled, or broken tools are surfaced through the status pill and Settings tools pane.

### Provider Detail Tab

- **Structure**: the selected provider's full readout. Provider header (identity mark, name, status dot + status text), then one card holding the 5h window and Weekly Limit sections in the same label/value/bar/reset-footnote rhythm (prominent variant: 14pt monospaced-digit values, 6pt bars), then quiet Source / Confidence / Last run meta rows, then `RECENT ACTIVITY` filtered to this provider.
- **Variants**: per-window known / unknown. When a window has no local signal the bar renders a diagonal striped track and the 5h section shows "No local quota signal yet".
- **Weekly limit**: a peer quota-window readout — same accent, bar treatment, and its own "Resets in Xd" line when known. Sources: Codex's secondary rate-limit window and Claude's `/usage` "current week" line; both best-effort, degrading to a striped "Unknown" track.
- **Reset labels**: 5h and weekly reset countdowns live inside their own quota-window sections; no unlabeled countdown badges in the header.
- **Accessibility**: provider name, status, 5h quota, weekly quota, and reset countdowns are visible text or accessible labels; the striped track is decorative and hidden from accessibility.

### Recent Activity

- **Structure**: a small `RECENT ACTIVITY` section header with an "All logs" link, followed by up to three compact log rows (status dot, `HH:MM` time, provider, status text).
- **States**: empty ("No readiness runs yet"); populated. The "All logs" link opens the Logs settings pane.
- **Accessibility**: rows combine into a single readable label; status is carried by text, not the dot color alone.

### Popover Secondary Actions

- **Structure**: no standalone button row and no inline card actions. Quota state refreshes automatically (periodically and when the popover opens); manual refresh lives as `Reload` in the footer.
- **Variants**: footer chip (Reload).
- **States**: shown only when meaningful.
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
