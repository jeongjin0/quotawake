import AppKit
import QuotaWakeCore
import SwiftUI

struct FirstRunSetupView: View {
    @ObservedObject var model: QuotaWakeAppModel
    let close: () -> Void
    private let setupSteps = FirstRunStep.allCases.filter { $0 != .complete }

    var body: some View {
        VStack(spacing: 0) {
            FirstRunProgressHeader(
                step: model.firstRunFlow.step,
                stepIndex: currentStepIndex,
                stepCount: setupSteps.count,
                progressValue: progressValue
            )

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.firstRunFlow.step.title)
                                .font(.system(size: 24, weight: .semibold))
                            Text(model.firstRunFlow.step.setupSummary)
                                .font(.system(size: 13))
                                .foregroundStyle(QWTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        FirstRunStepContentView(model: model)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                Divider()

                HStack(spacing: 12) {
                    if let message = model.setupStatusMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(QWTheme.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        model.setupBack()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(QWCommandButtonStyle())
                    .disabled(!model.firstRunFlow.canMoveBack)

                    Button {
                        let transition = model.setupContinue()
                        if case .completed = transition {
                            close()
                        }
                    } label: {
                        Label(continueTitle, systemImage: continueIcon)
                    }
                    .buttonStyle(QWCommandButtonStyle(prominent: true))
                }
                .padding(16)
                .background(QWTheme.windowBackground)
            }
            .background(QWTheme.windowBackground)
        }
        .frame(minWidth: 720, minHeight: 520)
        .background(QWTheme.windowBackground)
        .foregroundStyle(QWTheme.primaryText)
        .tint(QWTheme.accent)
        .groupBoxStyle(QWGroupBoxStyle())
        .environment(\.colorScheme, .light)
    }

    private var currentStepIndex: Int {
        setupSteps.firstIndex(of: model.firstRunFlow.step).map { $0 + 1 } ?? setupSteps.count
    }

    private var progressValue: Double {
        guard !setupSteps.isEmpty else {
            return 1
        }
        return Double(currentStepIndex) / Double(setupSteps.count)
    }

    private var continueTitle: String {
        model.firstRunFlow.step == .testRun ? "Finish" : "Continue"
    }

    private var continueIcon: String {
        model.firstRunFlow.step == .testRun ? "checkmark" : "chevron.right"
    }
}

struct FirstRunProgressHeader: View {
    let step: FirstRunStep
    let stepIndex: Int
    let stepCount: Int
    let progressValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("QuotaWake")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Session readiness setup")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(QWTheme.secondaryText)
                }

                Spacer()

                Text("Step \(stepIndex) of \(stepCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(QWTheme.secondaryText)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(QWTheme.surfaceSubtle)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(QWTheme.border, lineWidth: 1)
                    )
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(QWTheme.surfaceSubtle)
                    Capsule()
                        .fill(QWTheme.accent)
                        .frame(width: max(0, min(geometry.size.width, geometry.size.width * progressValue)))
                }
            }
            .frame(height: 6)
                .accessibilityLabel("Setup progress")
                .accessibilityValue("Step \(stepIndex) of \(stepCount)")

            HStack(spacing: 8) {
                Image(systemName: step.systemImage)
                    .frame(width: 16)
                Text("Current: \(step.compactTitle)")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(QWTheme.primaryText)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(QWTheme.surface)
    }
}

struct FirstRunStepContentView: View {
    @ObservedObject var model: QuotaWakeAppModel

    var body: some View {
        switch model.firstRunFlow.step {
        case .welcome:
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Text("QuotaWake watches local quota-window signals and sends a small readiness prompt only when the window appears due.")
                        .font(.system(size: 15, weight: .semibold))

                    VStack(alignment: .leading, spacing: 10) {
                        FirstRunFeatureLine(
                            icon: "terminal",
                            title: "Use your installed CLIs",
                            detail: "Claude and Codex run from explicit CLI paths."
                        )
                        FirstRunFeatureLine(
                            icon: "person.crop.circle.badge.checkmark",
                            title: "Respect active time",
                            detail: "Background sends wait until this Mac appears in use."
                        )
                        FirstRunFeatureLine(
                            icon: "paperplane",
                            title: "Verify before finishing",
                            detail: "The final step lets you run or explicitly skip one live test."
                        )
                    }

                    Text("The test run may consume a small amount of provider usage.")
                        .foregroundStyle(QWTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
            }
        case .detectTools:
            VStack(alignment: .leading, spacing: 12) {
                Text("Auto-detected paths are used by default. Add a manual path only when the detected command is missing or points to the wrong install.")
                    .font(.system(size: 13))
                    .foregroundStyle(QWTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(model.settingsState.toolStates, id: \.tool) { state in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                StatusDot(tone: state.status == .found ? .success : .warning)
                                Text(state.displayName)
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Text(state.statusText)
                                    .foregroundStyle(QWTheme.secondaryText)
                            }
                            SettingsRow(label: "Path", value: state.pathText, monospaced: true)
                            TextField(
                                "Manual path",
                                text: Binding(
                                    get: { model.settings.tools[state.tool].manualPath ?? "" },
                                    set: { model.setupSetManualPath(state.tool, path: $0) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                        .padding(12)
                    }
                }
            }
        case .windowReadiness:
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        "Launch at Login",
                        isOn: Binding(
                            get: { model.firstRunFlow.settings.background.launchAtLoginEnabled },
                            set: { model.setupSetLaunchAtLogin($0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    Text("Session readiness starts after login when this is enabled.")
                        .foregroundStyle(QWTheme.secondaryText)
                    Divider()
                    Toggle(
                        "Require active use",
                        isOn: Binding(
                            get: { model.firstRunFlow.settings.readiness.activeOnly },
                            set: {
                                model.firstRunFlow.settings.readiness.activeOnly = $0
                                model.settings = model.firstRunFlow.settings
                            }
                        )
                    )
                    .toggleStyle(.checkbox)
                    SettingsRow(
                        label: "Idle threshold",
                        value: "\(model.firstRunFlow.settings.readiness.idleThresholdSeconds) seconds"
                    )
                    SettingsRow(
                        label: "Cooldown",
                        value: "\(model.firstRunFlow.settings.readiness.minimumSendCooldownMinutes) minutes"
                    )
                    Text("Readiness sends only when a reset candidate is due and this Mac appears active.")
                        .foregroundStyle(QWTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
            }
        case .testRun:
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Send the readiness prompt now or acknowledge skipping the test.")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Live providers are used only when you press Run Test. Finish stays blocked until you either run it or acknowledge the skip.")
                        .foregroundStyle(QWTheme.secondaryText)
                    Button {
                        model.setupRunTest()
                    } label: {
                        Label("Run Test", systemImage: "paperplane")
                    }
                    .buttonStyle(QWCommandButtonStyle(prominent: true))
                    .disabled(model.popoverState.toolStates.filter(\.enabled).allSatisfy { $0.status != .found })

                    Toggle(
                        "Skip test with acknowledgment",
                        isOn: Binding(
                            get: { model.firstRunFlow.testRunSkippedAcknowledged },
                            set: { model.setupSetSkipTestAcknowledged($0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                }
                .padding(12)
            }
        case .complete:
            GroupBox {
                Text("Setup complete.")
                    .padding(12)
            }
        }
    }
}

struct FirstRunFeatureLine: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(QWTheme.accent)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(QWTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
