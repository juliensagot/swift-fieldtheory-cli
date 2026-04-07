import ArgumentParser
import FieldTheory

extension FT {
    struct Classify: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Classify bookmarks by category using regex patterns."
        )

        func run() throws {
            let paths = Paths()
            try DatabaseHelper.requireData(paths: paths)
            let store = try DatabaseHelper.openStore(paths: paths)
            defer { store.db.close() }

            let records = try store.list(limit: 100_000)
            print("Classifying \(records.count) bookmarks...")

            var updated = 0
            for record in records {
                let result = Classifier.classify(record)
                var classified = record
                classified.categories = result.categories.isEmpty ? nil : result.categories.joined(separator: ",")
                classified.primaryCategory = result.categories.isEmpty ? nil : result.primary
                classified.githubUrls = result.githubUrls.isEmpty ? nil : result.githubUrls.joined(separator: ",")
                try store.insert(classified)
                if !result.categories.isEmpty { updated += 1 }
            }

            let summary = Classifier.classifyCorpus(records)
            print("Classified \(updated) of \(records.count) bookmarks.")
            print("Unclassified: \(summary.unclassifiedCount)")
            for (cat, count) in summary.categoryCounts.sorted(by: { $0.value > $1.value }) {
                print("  \(cat): \(count)")
            }
        }
    }
}
