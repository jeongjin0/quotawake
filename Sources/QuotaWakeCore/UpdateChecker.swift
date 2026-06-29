import Foundation

public struct SemVer: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public init(_ value: String) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]),
              major >= 0,
              minor >= 0,
              patch >= 0,
              "\(major)" == parts[0],
              "\(minor)" == parts[1],
              "\(patch)" == parts[2] else {
            throw UpdateCheckerError.invalidVersion(value)
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func tag(_ value: String) throws -> SemVer {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "v" || trimmed.first == "V" {
            return try SemVer(String(trimmed.dropFirst()))
        }
        return try SemVer(trimmed)
    }

    public static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public struct GitHubRelease: Decodable, Equatable, Sendable {
    public struct Asset: Decodable, Equatable, Sendable {
        public let name: String
        public let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    public let tagName: String
    public let htmlURL: URL
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

public struct UpdateInfo: Equatable, Sendable {
    public let version: SemVer
    public let releaseURL: URL
    public let downloadURL: URL?

    public var preferredOpenURL: URL {
        downloadURL ?? releaseURL
    }
}

public enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(current: SemVer, latest: SemVer)
    case available(UpdateInfo)
}

public enum UpdateCheckState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(String)
    case available(version: String, url: URL)
    case failed(String)
}

public enum UpdateCheckerError: Error, Equatable, LocalizedError, Sendable {
    case emptyEndpoint
    case invalidVersion(String)
    case malformedRelease
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .emptyEndpoint:
            return "Update endpoint is not configured."
        case let .invalidVersion(value):
            return "Invalid SemVer version: \(value)"
        case .malformedRelease:
            return "Release metadata could not be parsed."
        case let .transport(message):
            return "Update check failed: \(message)"
        }
    }
}

public struct UpdateChecker: Sendable {
    public typealias FetchReleaseData = @Sendable (URL) throws -> Data

    private let currentVersion: SemVer
    private let endpoint: URL
    private let fetchReleaseData: FetchReleaseData

    public init(
        currentVersion: String,
        endpoint: String?,
        fetchReleaseData: @escaping FetchReleaseData
    ) throws {
        let trimmedEndpoint = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedEndpoint.isEmpty, let endpointURL = URL(string: trimmedEndpoint) else {
            throw UpdateCheckerError.emptyEndpoint
        }
        self.currentVersion = try SemVer(currentVersion)
        self.endpoint = endpointURL
        self.fetchReleaseData = fetchReleaseData
    }

    public func check() throws -> UpdateCheckResult {
        let data: Data
        do {
            data = try fetchReleaseData(endpoint)
        } catch let error as UpdateCheckerError {
            throw error
        } catch {
            throw UpdateCheckerError.transport(error.localizedDescription)
        }

        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdateCheckerError.malformedRelease
        }

        let latest = try SemVer.tag(release.tagName)
        if latest <= currentVersion {
            return .upToDate(current: currentVersion, latest: latest)
        }

        let dmgAsset = release.assets.first { asset in
            asset.name.lowercased().hasSuffix(".dmg")
        }
        return .available(
            UpdateInfo(
                version: latest,
                releaseURL: release.htmlURL,
                downloadURL: dmgAsset?.browserDownloadURL
            )
        )
    }
}
