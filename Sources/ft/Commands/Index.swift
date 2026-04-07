import ArgumentParser
import FieldTheory

extension FT {
    struct Index: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Rebuild the SQLite search index."
        )

        func run() throws {
            let paths = Paths()
            try DatabaseHelper.requireData(paths: paths)
            let store = try DatabaseHelper.openStore(paths: paths)
            defer { store.db.close() }

            print("Rebuilding FTS index...")
            try store.rebuildFTS()

            let count = try store.count()
            print("Index rebuilt. \(count) bookmarks indexed.")
        }
    }
}
