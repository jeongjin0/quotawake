import Foundation

public final class QuotaWindowStateStore {
    private let paths: QuotaWakePaths
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(paths: QuotaWakePaths = QuotaWakePaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load(tool: ToolKind) throws -> QuotaWindowState? {
        let url = fileURL(for: tool)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try decoder.decode(QuotaWindowState.self, from: Data(contentsOf: url))
    }

    public func save(_ state: QuotaWindowState) throws {
        try paths.createDirectories(fileManager: fileManager)
        let data = try encoder.encode(state)
        try data.write(to: fileURL(for: state.tool), options: [.atomic])
    }

    private func fileURL(for tool: ToolKind) -> URL {
        paths.quotaStateDirectory.appendingPathComponent("\(tool.rawValue).json", isDirectory: false)
    }
}
