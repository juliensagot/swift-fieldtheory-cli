import ArgumentParser
import FieldTheory
import Foundation

extension FT {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show one bookmark in detail."
        )

        @Argument(help: "Bookmark/tweet ID.")
        var id: String

        @Flag(name: .long, help: "Output as JSON.")
        var json = false

        func run() throws {
            let paths = Paths()
            try DatabaseHelper.requireData(paths: paths)
            let store = try DatabaseHelper.openStore(paths: paths)
            defer { store.db.close() }

            guard let record = try store.getById(id) else {
                print("Bookmark \(id) not found.")
                throw ExitCode.failure
            }

            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(record)
                print(String(data: data, encoding: .utf8)!)
            } else {
                let handle = record.authorHandle.map { "@\($0)" } ?? "unknown"
                print("\(handle) — \(record.url)")
                print()
                print(record.text)
                print()
                if let posted = record.postedAt { print("  posted:     \(posted)") }
                if let bookmarked = record.bookmarkedAt { print("  bookmarked: \(bookmarked)") }
                if let lang = record.language { print("  language:   \(lang)") }
                if let eng = record.engagement {
                    var parts: [String] = []
                    if let l = eng.likeCount { parts.append("\(l) likes") }
                    if let r = eng.repostCount { parts.append("\(r) reposts") }
                    if let v = eng.viewCount { parts.append("\(v) views") }
                    if !parts.isEmpty { print("  engagement: \(parts.joined(separator: ", "))") }
                }
                if let links = record.links, !links.isEmpty {
                    print("  links:      \(links.joined(separator: ", "))")
                }
                if let cat = record.primaryCategory { print("  category:   \(cat)") }
                if let dom = record.primaryDomain { print("  domain:     \(dom)") }
            }
        }
    }
}
