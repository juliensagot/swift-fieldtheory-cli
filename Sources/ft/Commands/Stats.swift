import ArgumentParser
import FieldTheory

extension FT {
    struct Stats: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show aggregate statistics."
        )

        func run() throws {
            let paths = Paths()
            try DatabaseHelper.requireData(paths: paths)
            let store = try DatabaseHelper.openStore(paths: paths)
            defer { store.db.close() }

            let stats = try store.getStats()

            print("Bookmarks: \(stats.totalBookmarks)")
            print("Authors:   \(stats.uniqueAuthors)")

            if let earliest = stats.earliestDate?.prefix(10),
               let latest = stats.latestDate?.prefix(10) {
                print("Range:     \(earliest) — \(latest)")
            }

            if !stats.topAuthors.isEmpty {
                print()
                print("Top authors:")
                for (i, author) in stats.topAuthors.prefix(10).enumerated() {
                    print("  \(i + 1). @\(author.handle) (\(author.count))")
                }
            }

            if !stats.languages.isEmpty {
                print()
                print("Languages:")
                for lang in stats.languages.prefix(5) {
                    print("  \(lang.language): \(lang.count)")
                }
            }
        }
    }
}
