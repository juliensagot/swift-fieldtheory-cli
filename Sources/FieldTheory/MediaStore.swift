import Foundation
import CommonCrypto

private actor Counter {
    private var value = 0
    func increment() -> Int { value += 1; return value }
}

public struct MediaFile: Sendable {
    public let id: String
    public let bookmarkId: String
    public let sourceUrl: String
    public let localPath: String?
    public let contentType: String?
    public let width: Int?
    public let height: Int?
    public let altText: String?
    public let byteCount: Int?
    public let status: String   // "downloaded", "skipped_too_large", "failed"
    public let reason: String?
    public let fetchedAt: String
}

public final class MediaStore {
    public let db: SQLiteDatabase
    public let mediaDir: String

    public init(db: SQLiteDatabase, mediaDir: String) {
        self.db = db
        self.mediaDir = mediaDir
    }

    // MARK: - Insert

    public func insertRecord(
        bookmarkId: String,
        tweetId: String,
        sourceUrl: String,
        localPath: String?,
        contentType: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        altText: String? = nil,
        byteCount: Int? = nil,
        status: String,
        reason: String? = nil
    ) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let id = "\(tweetId)-\(sha256Prefix(sourceUrl))"
        try db.execute("""
            INSERT OR IGNORE INTO media_files (
                id, bookmark_id, source_url, local_path, content_type,
                width, height, alt_text, byte_count, status, reason, fetched_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            .text(id),
            .text(bookmarkId),
            .text(sourceUrl),
            localPath.map { .text($0) } ?? .null,
            contentType.map { .text($0) } ?? .null,
            width.map { .integer(Int64($0)) } ?? .null,
            height.map { .integer(Int64($0)) } ?? .null,
            altText.map { .text($0) } ?? .null,
            byteCount.map { .integer(Int64($0)) } ?? .null,
            .text(status),
            reason.map { .text($0) } ?? .null,
            .text(now),
        ])
    }

    // MARK: - Query

    public func filesForBookmark(_ bookmarkId: String) throws -> [MediaFile] {
        let rows = try db.query(
            "SELECT id, bookmark_id, source_url, local_path, content_type, width, height, alt_text, byte_count, status, reason, fetched_at FROM media_files WHERE bookmark_id = ?",
            [.text(bookmarkId)]
        )
        return rows.map { rowToMediaFile($0) }
    }

    public func totalCount() throws -> Int {
        let rows = try db.query("SELECT count(*) FROM media_files WHERE status = 'downloaded'")
        return rows[0][0].intValue ?? 0
    }

    public func hasFile(bookmarkId: String, sourceUrl: String) throws -> Bool {
        let rows = try db.query(
            "SELECT 1 FROM media_files WHERE bookmark_id = ? AND source_url = ? LIMIT 1",
            [.text(bookmarkId), .text(sourceUrl)]
        )
        return !rows.isEmpty
    }

    // MARK: - Download media for bookmarks

    public func downloadMedia(
        for records: [BookmarkRecord],
        httpClient: HTTPClientProtocol,
        maxBytesPerMedia: Int = 50_000_000,
        maxConcurrency: Int = 6,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> Int {
        try FileManager.default.createDirectory(
            atPath: mediaDir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        // Collect work items, filtering out already-downloaded
        var work: [(record: BookmarkRecord, media: BookmarkMediaObject, urlString: String)] = []
        for record in records {
            for media in record.mediaObjects ?? [] {
                guard let urlString = Self.downloadUrl(for: media),
                      URL(string: urlString) != nil else { continue }
                if try hasFile(bookmarkId: record.id, sourceUrl: urlString) { continue }
                work.append((record, media, urlString))
            }
        }

        let total = work.count
        if total == 0 { return 0 }

        let mediaDir = self.mediaDir
        let maxBytes = maxBytesPerMedia

        // Download concurrently, collect results to insert into DB on the main thread
        let completed = Counter()
        let results: [(record: BookmarkRecord, media: BookmarkMediaObject, urlString: String, outcome: DownloadOutcome)] =
            try await withThrowingTaskGroup(of: (Int, BookmarkRecord, BookmarkMediaObject, String, DownloadOutcome).self) { group in
                var results: [(BookmarkRecord, BookmarkMediaObject, String, DownloadOutcome)] = []
                var nextIndex = 0

                // Seed initial batch
                for _ in 0..<min(maxConcurrency, work.count) {
                    let i = nextIndex
                    let item = work[i]
                    nextIndex += 1
                    group.addTask {
                        let outcome = await Self.downloadOne(
                            url: item.urlString, httpClient: httpClient,
                            tweetId: item.record.tweetId, mediaDir: mediaDir, maxBytes: maxBytes,
                            data: item.media
                        )
                        return (i, item.record, item.media, item.urlString, outcome)
                    }
                }

                for try await (_, record, media, urlString, outcome) in group {
                    results.append((record, media, urlString, outcome))
                    let done = await completed.increment()
                    onProgress?(done, total)

                    // Enqueue next item
                    if nextIndex < work.count {
                        let i = nextIndex
                        let item = work[i]
                        nextIndex += 1
                        group.addTask {
                            let outcome = await Self.downloadOne(
                                url: item.urlString, httpClient: httpClient,
                                tweetId: item.record.tweetId, mediaDir: mediaDir, maxBytes: maxBytes,
                                data: item.media
                            )
                            return (i, item.record, item.media, item.urlString, outcome)
                        }
                    }
                }

                return results
            }

        // Insert results into DB (SQLite is single-threaded)
        var downloaded = 0
        for (record, media, urlString, outcome) in results {
            switch outcome {
            case .downloaded(let localPath, let contentType, let byteCount):
                try insertRecord(
                    bookmarkId: record.id, tweetId: record.tweetId, sourceUrl: urlString,
                    localPath: localPath, contentType: contentType,
                    width: media.width, height: media.height, altText: media.extAltText,
                    byteCount: byteCount, status: "downloaded"
                )
                downloaded += 1
            case .skippedTooLarge(let byteCount, let reason):
                try insertRecord(
                    bookmarkId: record.id, tweetId: record.tweetId, sourceUrl: urlString,
                    localPath: nil, byteCount: byteCount,
                    status: "skipped_too_large", reason: reason
                )
            case .failed(let reason):
                try insertRecord(
                    bookmarkId: record.id, tweetId: record.tweetId, sourceUrl: urlString,
                    localPath: nil, status: "failed", reason: reason
                )
            }
        }

        return downloaded
    }

    // MARK: - Single Download (runs concurrently)

    private enum DownloadOutcome: Sendable {
        case downloaded(localPath: String, contentType: String?, byteCount: Int)
        case skippedTooLarge(byteCount: Int, reason: String)
        case failed(reason: String)
    }

    private static func downloadOne(
        url urlString: String,
        httpClient: HTTPClientProtocol,
        tweetId: String,
        mediaDir: String,
        maxBytes: Int,
        data mediaObj: BookmarkMediaObject
    ) async -> DownloadOutcome {
        guard let url = URL(string: urlString) else {
            return .failed(reason: "Invalid URL")
        }

        let request = URLRequest(url: url)
        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await httpClient.data(for: request)
        } catch {
            return .failed(reason: error.localizedDescription)
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            return .failed(reason: "HTTP \(statusCode)")
        }

        if responseData.count > maxBytes {
            return .skippedTooLarge(
                byteCount: responseData.count,
                reason: "\(responseData.count) bytes exceeds max \(maxBytes)"
            )
        }

        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
        let ext = fileExtension(contentType: contentType, sourceUrl: urlString)

        // SHA256 prefix for filename uniqueness
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        responseData.withUnsafeBytes { CC_SHA256($0.baseAddress, CC_LONG(responseData.count), &hash) }
        let digest = hash.prefix(8).map { String(format: "%02x", $0) }.joined()

        let filename = "\(tweetId)-\(digest)\(ext)"
        let localPath = (mediaDir as NSString).appendingPathComponent(filename)

        do {
            try responseData.write(to: URL(fileURLWithPath: localPath))
        } catch {
            return .failed(reason: "Write failed: \(error.localizedDescription)")
        }

        return .downloaded(localPath: localPath, contentType: contentType, byteCount: responseData.count)
    }

    // MARK: - Helpers

    public func shouldSkip(dataSize: Int, maxBytes: Int) -> Bool {
        dataSize > maxBytes
    }

    public static func bestVideoVariant(_ variants: [BookmarkMediaVariant]) -> BookmarkMediaVariant? {
        variants
            .filter { $0.contentType == "video/mp4" || $0.url?.hasSuffix(".mp4") == true }
            .max { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }
    }

    public static func downloadUrl(for media: BookmarkMediaObject) -> String? {
        if media.type == "video" || media.type == "animated_gif" {
            if let variants = media.variants, let best = bestVideoVariant(variants) {
                return best.url
            }
        }
        return media.mediaUrl
    }

    static func fileExtension(contentType: String?, sourceUrl: String) -> String {
        if let ct = contentType {
            if ct.contains("jpeg") || ct.contains("jpg") { return ".jpg" }
            if ct.contains("png") { return ".png" }
            if ct.contains("gif") { return ".gif" }
            if ct.contains("webp") { return ".webp" }
            if ct.contains("mp4") { return ".mp4" }
        }
        let ext = (URL(string: sourceUrl)?.pathExtension).flatMap { $0.isEmpty ? nil : ".\($0)" }
        return ext ?? ".bin"
    }

    private func sha256Prefix(_ string: String) -> String {
        sha256Prefix(Data(string.utf8))
    }

    private func sha256Prefix(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private func rowToMediaFile(_ row: [SQLiteValue]) -> MediaFile {
        MediaFile(
            id: row[0].textValue ?? "",
            bookmarkId: row[1].textValue ?? "",
            sourceUrl: row[2].textValue ?? "",
            localPath: row[3].textValue,
            contentType: row[4].textValue,
            width: row[5].intValue,
            height: row[6].intValue,
            altText: row[7].textValue,
            byteCount: row[8].intValue,
            status: row[9].textValue ?? "",
            reason: row[10].textValue,
            fetchedAt: row[11].textValue ?? ""
        )
    }
}

// MARK: - SQLiteValue blob convenience (kept for SQLiteDatabase tests)

extension SQLiteValue {
    var blobValue: Data? {
        if case .blob(let v) = self { return v }
        return nil
    }
}
