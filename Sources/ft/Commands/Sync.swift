import ArgumentParser
import FieldTheory
import Foundation

extension FT {
    struct Sync: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Sync bookmarks from X into local database."
        )

        @Option(name: .long, help: "Max pages to fetch (20 bookmarks per page).")
        var maxPages: Int = 500

        @Option(name: .long, help: "Stop after this many new bookmarks.")
        var targetAdds: Int?

        @Option(name: .long, help: "Delay between page requests in ms.")
        var delayMs: Int = 600

        @Option(name: .long, help: "Max runtime in minutes.")
        var maxMinutes: Int = 30

        @Flag(name: .long, help: "Full re-sync (not incremental).")
        var rebuild = false

        @Flag(name: .long, help: "Classify bookmarks after sync.")
        var classify = false

        func run() async throws {
            let paths = Paths()
            try paths.ensureDataDir()

            // Extract Safari cookies
            print("Reading Safari cookies...")
            let cookieResult: CookieResult
            do {
                cookieResult = try SafariCookieParser.extractXCookies(fromPath: SafariCookieParser.defaultCookiesPath)
            } catch let error as SafariCookieError {
                print("Error: \(error)")
                throw ExitCode.failure
            }

            let store = try DatabaseHelper.openStore(paths: paths)
            defer { store.db.close() }

            let existingRecords = try store.list(limit: 100_000)

            let engine = SyncEngine(
                httpClient: URLSessionHTTPClient(),
                csrfToken: cookieResult.csrfToken,
                cookieHeader: cookieResult.cookieHeader
            )

            let options = SyncOptions(
                incremental: !rebuild,
                maxPages: maxPages,
                delayMs: delayMs,
                maxMinutes: maxMinutes
            )

            print("Syncing bookmarks...")
            let (result, records) = try await engine.sync(
                options: options,
                existingRecords: existingRecords,
                onProgress: { progress in
                    print("\r  page \(progress.page) — \(progress.newAdded) new, \(progress.totalFetched) fetched", terminator: "")
                    fflush(stdout)
                }
            )
            print()

            // Store new records
            try store.bulkInsert(records)
            try store.rebuildFTS()

            // Optionally classify
            if classify {
                print("Classifying bookmarks...")
                var updated = 0
                for record in records {
                    let cr = Classifier.classify(record)
                    if !cr.categories.isEmpty {
                        var classified = record
                        classified.categories = cr.categories.joined(separator: ",")
                        classified.primaryCategory = cr.primary
                        classified.githubUrls = cr.githubUrls.isEmpty ? nil : cr.githubUrls.joined(separator: ",")
                        try store.insert(classified)
                        updated += 1
                    }
                }
                print("  classified \(updated) bookmarks")
            }

            print("Sync complete.")
            print("  bookmarks added: \(result.added)")
            print("  total bookmarks: \(result.totalBookmarks)")
            print("  pages fetched: \(result.pages)")
            print("  stop reason: \(result.stopReason)")
        }
    }
}
