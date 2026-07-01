import Foundation

public enum QuotaWakeCore {
    public static let appName = "QuotaWake"
}

public struct BundleMetadata: Equatable, Sendable {
    public static let expectedBundleIdentifier = "com.jeongjin.quotawake.agentitem"
    public static let expectedBundleName = "QuotaWake"
    public static let minimumSupportedMajorVersion = 13

    public let bundleIdentifier: String
    public let minimumSystemVersion: String
    public let bundleName: String
    public let executableName: String
    public let isAgentApplication: Bool

    public init(
        bundleIdentifier: String,
        minimumSystemVersion: String,
        bundleName: String,
        executableName: String,
        isAgentApplication: Bool
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.minimumSystemVersion = minimumSystemVersion
        self.bundleName = bundleName
        self.executableName = executableName
        self.isAgentApplication = isAgentApplication
    }

    public static let production = BundleMetadata(
        bundleIdentifier: expectedBundleIdentifier,
        minimumSystemVersion: "13.0",
        bundleName: expectedBundleName,
        executableName: expectedBundleName,
        isAgentApplication: true
    )

    public func validate() throws {
        guard bundleIdentifier == Self.expectedBundleIdentifier else {
            throw ValidationError.invalidBundleIdentifier
        }

        guard let majorVersion = Self.majorVersion(from: minimumSystemVersion),
              majorVersion >= Self.minimumSupportedMajorVersion else {
            throw ValidationError.unsupportedMinimumSystemVersion
        }

        guard !bundleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyBundleName
        }

        guard !executableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyExecutableName
        }

        guard isAgentApplication else {
            throw ValidationError.agentApplicationRequired
        }
    }

    private static func majorVersion(from version: String) -> Int? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard let firstPart = parts.first else {
            return nil
        }
        return Int(firstPart)
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case invalidBundleIdentifier
        case unsupportedMinimumSystemVersion
        case emptyBundleName
        case emptyExecutableName
        case agentApplicationRequired
    }
}
