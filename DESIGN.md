# QuotaWake Mac Design System

## 1. Atmosphere & Identity

QuotaWake feels like a quiet Mac utility: compact, trustworthy, and easy to scan from the menu bar. The signature is "readiness at a glance" - a restrained status surface that makes the current quota-window readiness state, enabled tools, and recent result immediately clear without turning into a dashboard.

## 2. Color

### Palette

| Role | Token | Light | Dark | Usage |
| --- | --- | --- | --- | --- |
| Surface/primary | `surfacePrimary` | system window background | system window background | Settings window base |
| Surface/elevated | `surfaceElevated` | popover background | popover background | Menu bar popover, panels |
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

### Rules

- Use native dynamic system colors through SwiftUI/AppKit so light, dark, vibrancy, and accessibility contrast follow macOS.
- Accent color is reserved for focus, selected state, links, and the strongest action in a view.
- Do not introduce decorative gradients, one-off bright palettes, or marketing color blocks.

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

- Popover width: 320-360pt, fixed enough to avoid resize jitter.
- Settings window minimum: 720x520pt.
- Use native sidebar or tab-like section navigation for Settings, not nested cards.
- Rows use stable min heights so status changes do not shift the whole view.

### Rules

- No nested UI cards. Use grouped rows, dividers, native `Form`, `Table`, and `GroupBox` patterns.
- Prefer dense, organized information over landing-page spacing.
- Long paths and summaries must truncate in the middle or tail with tooltips/copy affordances later.

## 5. Components

### Status Row

- **Structure**: label, value, optional status dot/icon.
- **Variants**: neutral, success, warning, error, info.
- **Spacing**: `space2` horizontal gap, `space1` value detail gap.
- **States**: normal, disabled, stale.
- **Accessibility**: value text must carry the semantic status, not color alone.

### Popover Command Bar

- **Structure**: horizontal row of native buttons for Run Now, Pause/Resume, Settings, Quit.
- **Variants**: primary Run Now, secondary utility buttons.
- **Spacing**: `space2` gaps, stable button widths when labels change.
- **States**: enabled, disabled, running.
- **Accessibility**: labels are explicit and keyboard-focusable.

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

Use native tonal shift and separators.

| Type | Treatment | Usage |
| --- | --- | --- |
| Primary surface | system window/popover background | App shell |
| Secondary surface | native grouped background | Settings groups and log rows |
| Separator | native separator color | Section and row boundaries |
| Elevation | native popover/window shadow only | OS-owned windows/popovers |

### Rules

- Do not add custom heavy shadows.
- Use native popover/window depth instead of decorative containers.
- Controls should feel like macOS controls, not a web dashboard port.
