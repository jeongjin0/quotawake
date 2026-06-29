import AppKit
import QuotaWakeCore
import SwiftUI

struct ProviderQuotaCard: View {
    let provider: ProviderReadinessUIState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(provider.accent)
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(spacing: 7) {
                HStack(alignment: .center, spacing: 8) {
                    ProviderIdentityMark(provider: provider)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Label(provider.statusText, systemImage: provider.statusTone.qwStatusImage)
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(provider.statusTone.qwStatusColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                }

                VStack(alignment: .leading, spacing: 7) {
                    ProviderQuotaProgress(provider: provider)
                    ProviderMetricLine(label: "Reset in", value: provider.resetCountdownText)
                    if provider.showsDiagnosticDetail {
                        ProviderDiagnosticLine(text: provider.diagnosticText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: provider.showsDiagnosticDetail ? 136 : 122, alignment: .topLeading)
        .layoutPriority(provider.showsDiagnosticDetail ? 2 : 1)
        .background(.thinMaterial)
        .background(provider.wash)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(QWTheme.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

struct ProviderIdentityMark: View {
    let provider: ProviderReadinessUIState

    var body: some View {
        ZStack {
            Circle()
                .fill(provider.accent)
            if let image = ProviderBrandIcon.image(for: provider.tool) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
            } else {
                Text(provider.monogram)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityLabel("\(provider.displayName) identity")
    }
}

@MainActor
private enum ProviderBrandIcon {
    private static var cache: [ToolKind: NSImage] = [:]

    static func image(for tool: ToolKind) -> NSImage? {
        if let cached = cache[tool] {
            return cached
        }
        guard let url = Bundle.main.url(forResource: tool.providerIconResourceName, withExtension: "svg"),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        cache[tool] = image
        return image
    }
}

struct ProviderQuotaProgress: View {
    let provider: ProviderReadinessUIState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("5h quota")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(QWTheme.secondaryText)
                Spacer(minLength: 8)
                Text(provider.quotaValueText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(QWTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            ProviderQuotaBar(provider: provider)

            HStack(spacing: 8) {
                Text(provider.quotaUsedText)
                Spacer(minLength: 8)
                if provider.usedPercent == nil {
                    Text(provider.quotaRemainingText)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(QWTheme.secondaryText)
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.displayName) 5h quota")
        .accessibilityValue(provider.quotaText)
    }
}

struct ProviderQuotaBar: View {
    let provider: ProviderReadinessUIState

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(QWTheme.secondaryText.opacity(0.16))
                if let fraction = provider.usedFraction {
                    Capsule()
                        .fill(provider.accent)
                        .frame(width: max(4, width * fraction))
                }
            }
        }
        .frame(height: 6)
        .overlay(
            Capsule()
                .stroke(QWTheme.glassBorder.opacity(0.55), lineWidth: 1)
        )
    }
}

struct ProviderDiagnosticLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(QWTheme.secondaryText)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProviderMetricLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(QWTheme.secondaryText)
                .frame(width: 68, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(QWTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PopoverMenuFooter: View {
    let openSettings: () -> Void
    let showAbout: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            VStack(spacing: 2) {
                Button(action: openSettings) {
                    menuLabel("Settings", systemImage: "gearshape")
                }
                .buttonStyle(QWPopoverMenuRowStyle())

                Button(action: showAbout) {
                    menuLabel("About QuotaWake", systemImage: "info.circle")
                }
                .buttonStyle(QWPopoverMenuRowStyle())

                Button(action: quit) {
                    menuLabel("Quit", systemImage: "power")
                }
                .buttonStyle(QWPopoverMenuRowStyle(destructive: true))
            }
        }
    }

    private func menuLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 16)
            Text(title)
            Spacer(minLength: 0)
        }
    }
}
