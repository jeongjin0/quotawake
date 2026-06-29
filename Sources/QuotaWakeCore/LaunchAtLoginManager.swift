import Foundation

#if canImport(ServiceManagement)
import ServiceManagement
#endif

public enum LaunchAtLoginStatus: String, Codable, Equatable, Sendable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound
    case unknown
}

public struct LaunchAtLoginManager {
    public typealias StatusProvider = () throws -> LaunchAtLoginStatus
    public typealias Action = () throws -> Void

    private let statusProvider: StatusProvider
    private let registerAction: Action
    private let unregisterAction: Action

    public init(
        statusProvider: @escaping StatusProvider,
        registerAction: @escaping Action,
        unregisterAction: @escaping Action
    ) {
        self.statusProvider = statusProvider
        self.registerAction = registerAction
        self.unregisterAction = unregisterAction
    }

    public func currentStatus() throws -> LaunchAtLoginStatus {
        try statusProvider()
    }

    @discardableResult
    public func enable() throws -> LaunchAtLoginStatus {
        try setEnabled(true)
    }

    @discardableResult
    public func disable() throws -> LaunchAtLoginStatus {
        try setEnabled(false)
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        let status = try currentStatus()

        if enabled {
            guard status == .notRegistered else {
                return status
            }
            try registerAction()
            return try currentStatus()
        }

        switch status {
        case .enabled, .requiresApproval:
            try unregisterAction()
            return try currentStatus()
        case .notRegistered, .notFound, .unknown:
            return status
        }
    }
}

#if canImport(ServiceManagement)
@available(macOS 13.0, *)
public extension LaunchAtLoginManager {
    static var mainApp: LaunchAtLoginManager {
        LaunchAtLoginManager(
            statusProvider: {
                mapStatus(SMAppService.mainApp.status)
            },
            registerAction: {
                try SMAppService.mainApp.register()
            },
            unregisterAction: {
                try SMAppService.mainApp.unregister()
            }
        )
    }

    private static func mapStatus(_ status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .notRegistered
        case .notFound:
            return .notFound
        @unknown default:
            return .unknown
        }
    }
}
#endif
