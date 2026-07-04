import AppKit
import SwiftUI

// Spacing and type tokens mirroring DESIGN.md §3–4. Custom-built rows consume
// these; native Form/Table surfaces supply their own metrics.
enum QWDesign {
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
    static let space6: CGFloat = 24

    static let windowTitleFont = Font.system(size: 20, weight: .semibold)
    static let sectionFont = Font.system(size: 14, weight: .semibold)
    static let bodyFont = Font.system(size: 13)
    static let bodyEmphasisFont = Font.system(size: 13, weight: .semibold)
    static let captionFont = Font.system(size: 11)
    static let monoCaptionFont = Font.system(size: 11, design: .monospaced)
}

// Popover and first-run palette. The popover renders in fixed light mode;
// these values are a visual contract shared with QuotaWakePopover* views.
enum QWTheme {
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let sidebarBackground = Color(nsColor: .underPageBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let glassSurface = Color(nsColor: .windowBackgroundColor).opacity(0.49)
    static let glassPressed = Color(nsColor: .controlAccentColor).opacity(0.10)
    static let surfaceSubtle = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let glassBorder = Color(nsColor: .separatorColor).opacity(0.42)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let accent = Color.accentColor
    static let accentPressed = Color(nsColor: .selectedContentBackgroundColor)
    static let accentForeground = Color.white
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let error = Color(nsColor: .systemRed)
    static let info = Color(nsColor: .systemBlue)
    // Provider identity accents follow the Redesign v2 marks.
    static let claudeAccent = Color(red: 0.851, green: 0.467, blue: 0.341) // #D97757
    static let claudeWash = Color(red: 0.851, green: 0.467, blue: 0.341).opacity(0.12)
    static let codexAccent = Color(red: 0.051, green: 0.051, blue: 0.051) // #0D0D0D
    static let codexWash = Color(red: 0.051, green: 0.051, blue: 0.051).opacity(0.08)

    // Redesign v2 status/pill palette (popover renders in fixed light mode).
    static let pillGreen = Color(red: 0.114, green: 0.541, blue: 0.263) // #1d8a43
    static let pillOrange = Color(red: 0.784, green: 0.388, blue: 0.102) // #c8631a
    static let pillBlue = Color(red: 0.039, green: 0.435, blue: 0.839) // #0a6fd6
    static let pillRed = Color(red: 0.824, green: 0.231, blue: 0.188) // #d23b30

    // Neutral translucent card surface used by provider cards in the popover.
    static let cardFill = Color.white
    static let cardStroke = Color.black.opacity(0.075)
    static let popoverInk = Color.black.opacity(0.86)
    static let popoverInkSecondary = Color.black.opacity(0.5)
    static let popoverInkTertiary = Color.black.opacity(0.4)
    static let popoverHairline = Color.black.opacity(0.08)
    static let popoverExitGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.46),
            Color.white.opacity(0.20),
            Color.white.opacity(0.04)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}
