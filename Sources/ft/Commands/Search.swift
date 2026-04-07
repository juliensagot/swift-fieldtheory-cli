import ArgumentParser
import FieldTheory

extension FT {
    struct Search: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Full-text search across bookmarks."
        )

        @Argument(help: "Search query (supports AND, OR, NOT, \"exact phrase\").")
        var query: String

        @Option(name: .long, help: "Filter by author handle.")
        var author: String?

        @Option(name: .long, help: "Only bookmarks posted after this date (ISO).")
        var after: String?

        @Option(name: .long, help: "Only bookmarks posted before this date (ISO).")
        var before: String?

        @Option(name: .long, help: "Max results to return.")
        var limit: Int = 50

        func run() throws {
            let paths = Paths()
            try DatabaseHelper.requireData(paths: paths)
            let store = try DatabaseHelper.openStore(paths: paths)
            defer { store.db.close() }

            let results = try store.search(query, limit: limit)

            if results.isEmpty {
                print("No results for \"\(query)\".")
                return
            }

            for record in results {
                let handle = record.authorHandle.map { "@\($0)" } ?? "unknown"
                let date = record.postedAt?.prefix(10) ?? "no date"
                print("\(handle)  \(date)  \(record.url)")
                print("  \(record.text.prefix(120))")
                print()
            }
            print("\(results.count) result(s)")
        }
    }
}
