import Foundation

public struct WakeCoordinator {
    private let store: WakeRequestStore
    private let calendar: Calendar

    public init(store: WakeRequestStore, calendar: Calendar = .autoupdatingCurrent) {
        self.store = store
        self.calendar = calendar
    }

    @discardableResult
    public func updateWakeRequest(nextRun: Date?, settings: WakeSettings) throws -> String? {
        guard settings.enabled, settings.helperInstalled, let nextRun else {
            try store.clearWakeRequest()
            return nil
        }

        let wakeDate = nextRun.addingTimeInterval(TimeInterval(-max(0, settings.leadMinutes) * 60))
        return try store.writeWakeRequest(at: wakeDate)
    }
}
