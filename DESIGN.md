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
| Provider/Claude accent | `providerClaudeAccent` | dynamic warm system accent | dynamic warm system accent | Claude identity mark, non-status emphasis |
| Provider/Claude wash | `providerClaudeWash` | low-opacity warm material tint | low-opacity warm material tint | Claude card accent rail or identity fill |
| Provider/Codex accent | `providerCodexAccent` | dynamic cool system accent | dynamic cool system accent | Codex identity mark, non-status emphasis |
| Provider/Codex wash | `providerCodexWash` | low-opacity cool material tint | low-opacity cool material tint | Codex card accent rail or identity fill |

### Rules

- Use native dynamic system colors through SwiftUI/AppKit so light, dark, vibrancy, and accessibility contrast follow macOS.
- Accent color is reserved for focus, selected state, links, and the strongest action in a view.
- Provider identity accents are semantic identity tokens, not status tokens: Claude uses the warm accent family and Codex uses the cool accent family.
- Status must pair color with visible text or a status glyph; never depend on color alone or color only status.
- Do not introduce decorative gradients, orbs, one-off bright palettes, marketing color blocks, or arbitrary raw hex values in SwiftUI/product code.

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
- Keep text compact but never below 11pt in app UI.

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

- Popover width: 320-360pt, fixed enough to avoid resize jitter; height may expand to about 580pt when quota progress bars and diagnostics are visible.
- Settings window minimum: 720x520pt.
- Use native sidebar or tab-like section navigation for Settings, not nested cards.
- Rows use stable min heights so status changes do not shift the whole view.
- Provider quota cards use a stable compact footprint: provider header, quota progress bar, reset countdown line, and only conditional diagnostic detail.
- The bottom menu footer is separated from provider content by a native divider and uses full-width text rows for Settings, About QuotaWake, and Quit.

### Rules

- No nested UI cards. Use grouped rows, dividers, native `Form`, `Table`, and `GroupBox` patterns.
- Prefer dense, organized information over landing-page spacing.
- Long paths and summaries must truncate in the middle or tail with tooltips/copy affordances later.
- Do not build nested card stacks in the popover; provider quota cards sit directly on the glass shell.

## 5. Components

### Status Row

- **Structure**: label, value, optional status dot/icon.
- **Variants**: neutral, success, warning, error, info.
- **Spacing**: `space2` horizontal gap, `space1` value detail gap.
- **States**: normal, disabled, stale.
- **Accessibility**: value text must carry the semantic status, not color alone.

### Provider Quota Card

- **Structure**: a single column card. Top row = provider identity mark, provider name, a short tinted status chip ("Observed" / "Ready" / "Unknown" / "Unavailable"), an optional `NEXT` badge (provider whose window resets soonest), and a large reset countdown ("in 2h 41m" / "Due" / "—"). Below: a thin 5h quota bar that fills by **remaining** capacity (a fuel gauge), a one-line 5h summary ("58% quota left · sends only while Mac is active") and, separated by a hairline divider, a Weekly Limit row.
- **Identity accents**: Claude `#D97757` (warm coral), Codex `#0D0D0D` (near-black). The accent appears only on the identity mark, the bar fill, and the `NEXT` badge — never as a card background wash.
- **Variants**: per-window known / unknown. When the 5h window has no local signal the bar renders a diagonal striped track and the summary line shows "No local quota signal yet" with an inline `Observe` chip.
- **Spacing**: `space3` padding, `space2`–`space3` row gaps, `space1` gaps inside compact metadata lines.
- **Surface**: a neutral translucent white card (≈0.55 opacity for the next-due provider, ≈0.42 for others) on the glass popover shell with a hairline stroke; one card per provider, never nested colored panels.
- **States**: status chip copy and tone change with state; identity accent stays stable so status never relies on color alone. The `NEXT` badge marks the soonest-due enabled provider.
- **Accessibility**: provider name, 5h quota, weekly quota, reset countdowns, and status are visible text or accessible labels; the striped track is decorative and hidden from accessibility.

### Weekly Limit Row

- **Structure**: a compact secondary readout at the bottom of each provider card — "Weekly limit" label, a percent value ("62% left" / "Unknown"), a thin muted-accent bar, and a "Resets in Xd" line when known.
- **Source**: Codex's secondary rate-limit window and Claude's `/usage` "current week" line; both are best-effort and degrade to a striped "Unknown" track when no signal is present.
- **Rules**: the weekly bar uses a lower-emphasis accent (≈0.65 opacity) and a thinner height than the 5h bar, so the 5h window stays the primary signal and weekly reads as supporting context.

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

- **Structure**: a horizontal footer below a hairline divider. Reload and Settings are grouped at the leading edge; Quit sits at the trailing edge as a destructive (error-tinted) chip. Each item is icon + text (`↻ Reload`, `⚙ Settings`, `⏻ Quit`).
- **Actions**: Reload refreshes the observed quota; Settings opens the settings window; Quit terminates the app.
- **Variants**: normal chip, destructive Quit chip.
- **Spacing**: compact chip padding, `space2` grouping, divider above footer.
- **States**: normal, pressed, disabled only when an action is temporarily unavailable.
- **Accessibility**: footer actions must show visible text; do not hide Reload, Settings, or Quit behind icon-only controls.

### Settings Pane

- **Structure**: sidebar section list plus detail pane, or equivalent native Settings grouping.
- **Variants**: General, Tools, Window Readiness, Prompt, Logs.
- **Spacing**: `space6` outer padding, `space4` group padding.
- **States**: normal, error banner, disabled controls.
- **Accessibility**: each control has a visible label and native focus ring.

### Log Table

- **Structure**: time, tool, status, duration, exit code, summary.
- **Variants**: empty, populated, error rows.
- **Spacing**: native table row metrics.
- **States**: selected row, empty state.
- **Accessibility**: column headers remain visible and summaries are text, not color-only.

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
