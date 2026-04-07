import Foundation

public struct Paths: Sendable {
    public let dataDir: String

    public init(baseDir: String? = nil, environment: [String: String] = [:]) {
        if let envDir = environment["FT_DATA_DIR"] {
            self.dataDir = envDir
        } else if let explicitBase = baseDir {
            self.dataDir = explicitBase
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            self.dataDir = "\(home)/.ft-bookmarks"
        }
    }

    public var indexPath: String { "\(dataDir)/bookmarks.db" }
    public var metaPath: String { "\(dataDir)/bookmarks-meta.json" }
    public var backfillStatePath: String { "\(dataDir)/bookmarks-backfill-state.json" }
    public var cachePath: String { "\(dataDir)/bookmarks.jsonl" }

    public func ensureDataDir() throws {
        try FileManager.default.createDirectory(
            atPath: dataDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}

public enum FileUtilities {

    public static func writeJSONLines<T: Encodable>(_ records: [T], to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = try records.map { record in
            let data = try encoder.encode(record)
            return String(data: data, encoding: .utf8)!
        }
        let content = lines.joined(separator: "\n") + "\n"

        let tmpPath = path + ".tmp"
        try content.write(toFile: tmpPath, atomically: true, encoding: .utf8)
        try FileManager.default.moveItem(atPath: tmpPath, toPath: path)
    }

    public static func readJSONLines<T: Decodable>(from path: String) throws -> [T] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let decoder = JSONDecoder()
        return content
            .split(separator: "\n")
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                return try? decoder.decode(T.self, from: Data(trimmed.utf8))
            }
    }

    public static func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        let tmpPath = path + ".tmp"
        try data.write(to: URL(fileURLWithPath: tmpPath))
        try FileManager.default.moveItem(atPath: tmpPath, toPath: path)
    }

    public static func readJSON<T: Decodable>(from path: String) throws -> T {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(T.self, from: data)
    }
}
