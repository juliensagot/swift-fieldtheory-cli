import FieldTheory
import Foundation

enum DatabaseHelper {
    static func openStore(paths: Paths = Paths()) throws -> BookmarkStore {
        let db = try SQLiteDatabase(path: paths.indexPath)
        let store = BookmarkStore(db: db)
        try store.initSchema()
        return store
    }

    static func requireData(paths: Paths = Paths()) throws {
        guard FileManager.default.fileExists(atPath: paths.indexPath) else {
            throw CLIError.noData(
                "No bookmarks found at \(paths.indexPath).\n" +
                "Run 'ft sync' first to download your bookmarks from X."
            )
        }
    }
}

enum CLIError: Error, CustomStringConvertible {
    case noData(String)

    var description: String {
        switch self {
        case .noData(let msg): return msg
        }
    }
}
