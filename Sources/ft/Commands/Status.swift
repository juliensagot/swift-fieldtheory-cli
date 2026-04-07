import ArgumentParser
import FieldTheory
import Foundation

extension FT {
    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show sync status and bookmark count."
        )

        func run() throws {
            let paths = Paths()

            print("Data directory: \(paths.dataDir)")
            print("Database:       \(paths.indexPath)")

            guard FileManager.default.fileExists(atPath: paths.indexPath) else {
                print("Status:         No data. Run 'ft sync' to get started.")
                return
            }

            let store = try DatabaseHelper.openStore(paths: paths)
            defer { store.db.close() }

            let count = try store.count()
            let mediaDir = (paths.dataDir as NSString).appendingPathComponent("media")
            let mediaStore = MediaStore(db: store.db, mediaDir: mediaDir)
            let mediaCount = try mediaStore.totalCount()

            print("Bookmarks:      \(count)")
            print("Media files:    \(mediaCount)")
            print("Media dir:      \(mediaDir)")
        }
    }
}
