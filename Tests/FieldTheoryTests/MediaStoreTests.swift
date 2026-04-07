import Testing
import Foundation
@testable import FieldTheory

@Suite("MediaStore")
struct MediaStoreTests {

    private func makeStoreWithSchema() throws -> (BookmarkStore, MediaStore) {
        let db = try SQLiteDatabase(path: ":memory:")
        let bookmarkStore = BookmarkStore(db: db)
        try bookmarkStore.initSchema()
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ft-media-test-\(UUID().uuidString)").path
        let mediaStore = MediaStore(db: db, mediaDir: tmpDir)
        return (bookmarkStore, mediaStore)
    }

    // MARK: - Schema

    @Test func mediaFilesTableExists() throws {
        let (_, mediaStore) = try makeStoreWithSchema()
        let tables = try mediaStore.db.query(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='media_files'"
        )
        #expect(tables.count == 1)
    }

    @Test func mediaFilesIndexExists() throws {
        let (_, mediaStore) = try makeStoreWithSchema()
        let indexes = try mediaStore.db.query(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_media_files_bookmark'"
        )
        #expect(indexes.count == 1)
    }

    // MARK: - Insert & Retrieve

    @Test func insertAndRetrieveFile() throws {
        let (bookmarkStore, mediaStore) = try makeStoreWithSchema()
        try bookmarkStore.insert(BookmarkRecord(
            id: "1", tweetId: "1", url: "u", text: "t", syncedAt: "2024-01-01T00:00:00Z"
        ))

        try mediaStore.insertRecord(
            bookmarkId: "1",
            tweetId: "1",
            sourceUrl: "https://pbs.twimg.com/photo.jpg",
            localPath: "/tmp/media/1-abc123.jpg",
            contentType: "image/jpeg",
            width: 800,
            height: 600,
            altText: "A photo",
            byteCount: 1024,
            status: "downloaded"
        )

        let files = try mediaStore.filesForBookmark("1")
        #expect(files.count == 1)
        #expect(files[0].sourceUrl == "https://pbs.twimg.com/photo.jpg")
        #expect(files[0].localPath == "/tmp/media/1-abc123.jpg")
        #expect(files[0].contentType == "image/jpeg")
        #expect(files[0].width == 800)
        #expect(files[0].height == 600)
        #expect(files[0].altText == "A photo")
        #expect(files[0].byteCount == 1024)
        #expect(files[0].status == "downloaded")
    }

    // MARK: - Multiple Files Per Bookmark

    @Test func multipleFilesForBookmark() throws {
        let (bookmarkStore, mediaStore) = try makeStoreWithSchema()
        try bookmarkStore.insert(BookmarkRecord(
            id: "1", tweetId: "1", url: "u", text: "t", syncedAt: "2024-01-01T00:00:00Z"
        ))

        for i in 1...3 {
            try mediaStore.insertRecord(
                bookmarkId: "1", tweetId: "1",
                sourceUrl: "https://pbs.twimg.com/photo\(i).jpg",
                localPath: "/tmp/media/1-hash\(i).jpg",
                status: "downloaded"
            )
        }

        let files = try mediaStore.filesForBookmark("1")
        #expect(files.count == 3)
    }

    // MARK: - Duplicate Skip

    @Test func duplicateIsIdempotent() throws {
        let (bookmarkStore, mediaStore) = try makeStoreWithSchema()
        try bookmarkStore.insert(BookmarkRecord(
            id: "1", tweetId: "1", url: "u", text: "t", syncedAt: "2024-01-01T00:00:00Z"
        ))

        try mediaStore.insertRecord(
            bookmarkId: "1", tweetId: "1",
            sourceUrl: "https://pbs.twimg.com/photo.jpg",
            localPath: "/tmp/media/1-abc.jpg",
            status: "downloaded"
        )

        // Same (bookmark_id, source_url) — should not duplicate
        try mediaStore.insertRecord(
            bookmarkId: "1", tweetId: "1",
            sourceUrl: "https://pbs.twimg.com/photo.jpg",
            localPath: "/tmp/media/1-def.jpg",
            status: "downloaded"
        )

        let files = try mediaStore.filesForBookmark("1")
        #expect(files.count == 1)
    }

    // MARK: - Has File

    @Test func hasFileCheck() throws {
        let (bookmarkStore, mediaStore) = try makeStoreWithSchema()
        try bookmarkStore.insert(BookmarkRecord(
            id: "1", tweetId: "1", url: "u", text: "t", syncedAt: "2024-01-01T00:00:00Z"
        ))

        #expect(try mediaStore.hasFile(bookmarkId: "1", sourceUrl: "https://example.com/a.jpg") == false)

        try mediaStore.insertRecord(
            bookmarkId: "1", tweetId: "1",
            sourceUrl: "https://example.com/a.jpg",
            localPath: "/tmp/a.jpg", status: "downloaded"
        )

        #expect(try mediaStore.hasFile(bookmarkId: "1", sourceUrl: "https://example.com/a.jpg") == true)
    }

    // MARK: - Failed / Skipped Status

    @Test func failedStatusRecorded() throws {
        let (bookmarkStore, mediaStore) = try makeStoreWithSchema()
        try bookmarkStore.insert(BookmarkRecord(
            id: "1", tweetId: "1", url: "u", text: "t", syncedAt: "2024-01-01T00:00:00Z"
        ))

        try mediaStore.insertRecord(
            bookmarkId: "1", tweetId: "1",
            sourceUrl: "https://pbs.twimg.com/photo.jpg",
            localPath: nil, status: "failed", reason: "HTTP 403"
        )

        let files = try mediaStore.filesForBookmark("1")
        #expect(files[0].status == "failed")
        #expect(files[0].reason == "HTTP 403")
        #expect(files[0].localPath == nil)
    }

    @Test func skippedTooLargeRecorded() throws {
        let (bookmarkStore, mediaStore) = try makeStoreWithSchema()
        try bookmarkStore.insert(BookmarkRecord(
            id: "1", tweetId: "1", url: "u", text: "t", syncedAt: "2024-01-01T00:00:00Z"
        ))

        try mediaStore.insertRecord(
            bookmarkId: "1", tweetId: "1",
            sourceUrl: "https://pbs.twimg.com/video.mp4",
            localPath: nil, byteCount: 100_000_000,
            status: "skipped_too_large", reason: "100000000 bytes exceeds max"
        )

        let files = try mediaStore.filesForBookmark("1")
        #expect(files[0].status == "skipped_too_large")
    }

    // MARK: - Size Limit

    @Test func sizeLimitSkips() {
        let db = try! SQLiteDatabase(path: ":memory:")
        let mediaStore = MediaStore(db: db, mediaDir: "/tmp")

        #expect(mediaStore.shouldSkip(dataSize: 10_000, maxBytes: 5_000) == true)
        #expect(mediaStore.shouldSkip(dataSize: 1_000, maxBytes: 5_000) == false)
    }

    // MARK: - Total Count (only downloaded)

    @Test func totalCountOnlyDownloaded() throws {
        let (bookmarkStore, mediaStore) = try makeStoreWithSchema()
        try bookmarkStore.insert(BookmarkRecord(id: "1", tweetId: "1", url: "u", text: "t", syncedAt: "2024-01-01T00:00:00Z"))

        try mediaStore.insertRecord(bookmarkId: "1", tweetId: "1", sourceUrl: "url1", localPath: "/tmp/a.jpg", status: "downloaded")
        try mediaStore.insertRecord(bookmarkId: "1", tweetId: "1", sourceUrl: "url2", localPath: nil, status: "failed", reason: "HTTP 404")
        try mediaStore.insertRecord(bookmarkId: "1", tweetId: "1", sourceUrl: "url3", localPath: "/tmp/b.jpg", status: "downloaded")

        #expect(try mediaStore.totalCount() == 2) // only the 2 downloaded
    }

    // MARK: - Pick Best Video Variant

    @Test func pickHighestBitrateMP4() {
        let variants = [
            BookmarkMediaVariant(url: "https://v.twimg.com/360.mp4", contentType: "video/mp4", bitrate: 632000),
            BookmarkMediaVariant(url: "https://v.twimg.com/720.mp4", contentType: "video/mp4", bitrate: 2176000),
            BookmarkMediaVariant(url: "https://v.twimg.com/480.mp4", contentType: "video/mp4", bitrate: 950000),
        ]

        let best = MediaStore.bestVideoVariant(variants)
        #expect(best?.url == "https://v.twimg.com/720.mp4")
        #expect(best?.bitrate == 2176000)
    }

    @Test func noVariantsReturnsNil() {
        let best = MediaStore.bestVideoVariant([])
        #expect(best == nil)
    }

    // MARK: - Download URL

    @Test func mediaUrlForPhoto() {
        let obj = BookmarkMediaObject(mediaUrl: "https://pbs.twimg.com/photo.jpg", type: "photo")
        #expect(MediaStore.downloadUrl(for: obj) == "https://pbs.twimg.com/photo.jpg")
    }

    @Test func mediaUrlForVideo() {
        let obj = BookmarkMediaObject(
            mediaUrl: "https://pbs.twimg.com/thumb.jpg",
            type: "video",
            variants: [
                BookmarkMediaVariant(url: "https://v.twimg.com/720.mp4", contentType: "video/mp4", bitrate: 2176000),
                BookmarkMediaVariant(url: "https://v.twimg.com/360.mp4", contentType: "video/mp4", bitrate: 632000),
            ]
        )
        #expect(MediaStore.downloadUrl(for: obj) == "https://v.twimg.com/720.mp4")
    }

    // MARK: - File Extension

    @Test func fileExtensionFromContentType() {
        #expect(MediaStore.fileExtension(contentType: "image/jpeg", sourceUrl: "") == ".jpg")
        #expect(MediaStore.fileExtension(contentType: "image/png", sourceUrl: "") == ".png")
        #expect(MediaStore.fileExtension(contentType: "video/mp4", sourceUrl: "") == ".mp4")
        #expect(MediaStore.fileExtension(contentType: nil, sourceUrl: "https://example.com/img.webp") == ".webp")
        #expect(MediaStore.fileExtension(contentType: nil, sourceUrl: "https://example.com/file") == ".bin")
    }
}
