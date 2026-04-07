import ArgumentParser
import FieldTheory

extension FT {
    struct Categories: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show category distribution."
        )

        func run() throws {
            let paths = Paths()
            try DatabaseHelper.requireData(paths: paths)
            let store = try DatabaseHelper.openStore(paths: paths)
            defer { store.db.close() }

            let total = try store.count()
            let counts = try store.getCategoryCounts()

            if counts.isEmpty {
                print("No categories assigned. Run 'ft classify' first.")
                return
            }

            print("Categories (\(total) bookmarks):")
            for (cat, count) in counts.sorted(by: { $0.value > $1.value }) {
                let pct = total > 0 ? Double(count) / Double(total) * 100 : 0
                print("  \(cat.padding(toLength: 14, withPad: " ", startingAt: 0)) \(count)\t(\(String(format: "%.1f", pct))%)")
            }
        }
    }
}
