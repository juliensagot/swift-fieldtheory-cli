import ArgumentParser
import FieldTheory
import Foundation

extension FT {
    struct FetchMedia: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "fetch-media",
            abstract: "Download media assets for bookmarks."
        )

        @Option(name: .long, help: "Max bookmarks to process.")
        var limit: Int = 100

        @Option(name: .long, help: "Per-asset byte limit (default: 50MB).")
        var maxBytes: Int = 50_000_000

        @Option(name: .long, help: "Max concurrent downloads.")
        var concurrency: Int = 6

        func run() async throws {
            let paths = Paths()
            try DatabaseHelper.requireData(paths: paths)
            let store = try DatabaseHelper.openStore(paths: paths)
            defer { store.db.close() }

            let mediaDir = (paths.dataDir as NSString).appendingPathComponent("media")
            let mediaStore = MediaStore(db: store.db, mediaDir: mediaDir)

            let records = try store.list(limit: limit)
            let withMedia = records.filter { ($0.mediaObjects?.count ?? 0) > 0 }

            if withMedia.isEmpty {
                print("No bookmarks with media found.")
                return
            }

            print("Downloading media for \(withMedia.count) bookmarks...")
            let downloaded = try await mediaStore.downloadMedia(
                for: withMedia,
                httpClient: URLSessionHTTPClient(),
                maxBytesPerMedia: maxBytes,
                maxConcurrency: concurrency,
                onProgress: { current, total in
                    print("\r  \(current)/\(total) media items processed", terminator: "")
                    fflush(stdout)
                }
            )
            print()
            print("Downloaded \(downloaded) media files to \(mediaDir)")
        }
    }
}
