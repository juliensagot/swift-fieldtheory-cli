import ArgumentParser
import FieldTheory
import Foundation

extension FT {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List bookmarks with filters."
        )

        @Option(name: .long, help: "Filter by author handle.")
        var author: String?

        @Option(name: .long, help: "Only bookmarks posted after this date.")
        var after: String?

        @Option(name: .long, help: "Only bookmarks posted before this date.")
        var before: String?

        @Option(name: .long, help: "Filter by primary category.")
        var category: String?

        @Option(name: .long, help: "Filter by primary domain.")
        var domain: String?

        @Option(name: .long, help: "Max results.")
        var limit: Int = 100

        @Option(name: .long, help: "Offset for pagination.")
        var offset: Int = 0

        @Flag(name: .long, help: "Output as JSON.")
        var json = false

        func run() throws {
            let paths = Paths()
            try DatabaseHelper.requireData(paths: paths)
            let store = try DatabaseHelper.openStore(paths: paths)
            defer { store.db.close() }

            let results = try store.list(
                author: author, after: after, before: before,
                category: category, domain: domain,
                limit: limit, offset: offset
            )

            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(results)
                print(String(data: data, encoding: .utf8)!)
            } else {
                if results.isEmpty {
                    print("No bookmarks found.")
                    return
                }
                for record in results {
                    let handle = record.authorHandle.map { "@\($0)" } ?? "unknown"
                    let date = record.postedAt?.prefix(10) ?? "no date"
                    print("\(handle)  \(date)  \(record.url)")
                    print("  \(record.text.prefix(120))")
                    print()
                }
                print("\(results.count) bookmark(s)")
            }
        }
    }
}
