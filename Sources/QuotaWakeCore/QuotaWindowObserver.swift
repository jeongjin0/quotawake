import Foundation

public protocol QuotaWindowObserving {
    func observe(observedAt: Date) -> QuotaWindowState
}

extension CodexQuotaAdapter: QuotaWindowObserving {}
extension ClaudeQuotaAdapter: QuotaWindowObserving {}

public enum LocalQuotaWindowObserverProvider {
    public static func makeObserver(
        command: ResolvedToolCommand,
        paths: QuotaWakePaths
    ) -> QuotaWindowObserving? {
        guard command.status == .found, let executableURL = command.executableURL else {
            return nil
        }

        switch command.tool {
        case .codex:
            return CodexQuotaAdapter(executableURL: executableURL, runDirectory: paths.runDirectory)
        case .claude:
            return ClaudeQuotaAdapter(executableURL: executableURL, runDirectory: paths.runDirectory)
        }
    }
}
