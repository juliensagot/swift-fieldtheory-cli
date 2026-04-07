import Testing
import Foundation
@testable import FieldTheory

@Suite("BookmarkStore")
struct BookmarkStoreTests {

    private func makeStore() throws -> BookmarkStore {
        let db = try SQLiteDatabase(path: ":memory:")
        let store = BookmarkStore(db: db)
        try store.initSchema()
        return store
    }

    private func sampleRecord(
        id: String = "100",
        text: String = "Hello world",
        authorHandle: String? = "alice",
        authorName: String? = "Alice",
        postedAt: String? = "2024-06-15T10:00:00Z",
        bookmarkedAt: String? = "2024-06-15T12:00:00Z",
        language: String? = "en",
        categories: String? = nil,
        primaryCategory: String? = nil,
        domains: String? = nil,
        primaryDomain: String? = nil
    ) -> BookmarkRecord {
        BookmarkRecord(
            id: id,
            tweetId: id,
            authorHandle: authorHandle,
            authorName: authorName,
            url: "https://x.com/\(authorHandle ?? "user")/status/\(id)",
            text: text,
            postedAt: postedAt,
            bookmarkedAt: bookmarkedAt,
            syncedAt: "2024-06-15T14:00:00Z",
            language: language,
            engagement: BookmarkEngagement(likeCount: 10, repostCount: 2, replyCount: 1, quoteCount: 0, bookmarkCount: 5, viewCount: 500),
            media: [],
            links: [],
            ingestedVia: "graphql",
            categories: categories,
            primaryCategory: primaryCategory,
            domains: domains,
            primaryDomain: primaryDomain
        )
    }

    // MARK: - Schema

    @Test func schemaCreation() throws {
        let store = try makeStore()

        let tables = try store.db.query(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        )
        let tableNames = tables.map { row -> String in
            if case .text(let name) = row[0] { return name }
            return ""
        }

        #expect(tableNames.contains("bookmarks"))
        #expect(tableNames.contains("bookmarks_fts"))
        #expect(tableNames.contains("media_files"))
        #expect(tableNames.contains("meta"))
    }

    @Test func schemaVersion() throws {
        let store = try makeStore()
        let rows = try store.db.query("SELECT value FROM meta WHERE key = 'schema_version'")
        #expect(rows[0][0] == .text("5"))
    }

    @Test func indexesExist() throws {
        let store = try makeStore()
        let indexes = try store.db.query(
            "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%' ORDER BY name"
        )
        let names = indexes.compactMap { row -> String? in
            if case .text(let n) = row[0] { return n }
            return nil
        }

        #expect(names.contains("idx_bookmarks_author"))
        #expect(names.contains("idx_bookmarks_posted"))
        #expect(names.contains("idx_bookmarks_language"))
        #expect(names.contains("idx_bookmarks_category"))
        #expect(names.contains("idx_bookmarks_domain"))
        #expect(names.contains("idx_media_files_bookmark"))
    }

    // MARK: - Insert & Retrieve

    @Test func insertAndGetById() throws {
        let store = try makeStore()
        let record = sampleRecord()

        try store.insert(record)
        let fetched = try store.getById("100")

        #expect(fetched != nil)
        #expect(fetched?.id == "100")
        #expect(fetched?.text == "Hello world")
        #expect(fetched?.authorHandle == "alice")
        #expect(fetched?.language == "en")
    }

    @Test func getByIdReturnsNilForMissing() throws {
        let store = try makeStore()
        let fetched = try store.getById("nonexistent")
        #expect(fetched == nil)
    }

    // MARK: - Upsert

    @Test func upsertOverwritesExisting() throws {
        let store = try makeStore()

        try store.insert(sampleRecord(id: "1", text: "Original"))
        try store.insert(sampleRecord(id: "1", text: "Updated"))

        let fetched = try store.getById("1")
        #expect(fetched?.text == "Updated")

        let count = try store.count()
        #expect(count == 1)
    }

    // MARK: - FTS5 Search

    @Test func ftsSearchFindsMatch() throws {
        let store = try makeStore()

        try store.insert(sampleRecord(id: "1", text: "Swift is a great programming language"))
        try store.insert(sampleRecord(id: "2", text: "Rust is a systems programming language"))
        try store.insert(sampleRecord(id: "3", text: "Python is popular for data science"))
        try store.rebuildFTS()

        let results = try store.search("swift")
        #expect(results.count == 1)
        #expect(results[0].id == "1")
    }

    @Test func ftsSearchByAuthor() throws {
        let store = try makeStore()

        try store.insert(sampleRecord(id: "1", text: "Hello", authorHandle: "swiftdev", authorName: "Swift Developer"))
        try store.insert(sampleRecord(id: "2", text: "World", authorHandle: "rustdev", authorName: "Rust Developer"))
        try store.rebuildFTS()

        let results = try store.search("swiftdev")
        #expect(results.count == 1)
        #expect(results[0].authorHandle == "swiftdev")
    }

    @Test func ftsSearchWithBM25Ranking() throws {
        let store = try makeStore()

        try store.insert(sampleRecord(id: "1", text: "Swift"))
        try store.insert(sampleRecord(id: "2", text: "Swift is the best Swift language for Swift development"))
        try store.rebuildFTS()

        let results = try store.search("swift")
        #expect(results.count == 2)
        let ids = Set(results.map(\.id))
        #expect(ids.contains("1"))
        #expect(ids.contains("2"))
    }

    // MARK: - List with Filters

    @Test func listAll() throws {
        let store = try makeStore()

        try store.insert(sampleRecord(id: "1", text: "First"))
        try store.insert(sampleRecord(id: "2", text: "Second"))
        try store.insert(sampleRecord(id: "3", text: "Third"))

        let results = try store.list()
        #expect(results.count == 3)
    }

    @Test func listFilterByAuthor() throws {
        let store = try makeStore()

        try store.insert(sampleRecord(id: "1", authorHandle: "alice"))
        try store.insert(sampleRecord(id: "2", authorHandle: "bob"))
        try store.insert(sampleRecord(id: "3", authorHandle: "alice"))

        let results = try store.list(author: "alice")
        #expect(results.count == 2)
    }

    @Test func listFilterByDateRange() throws {
        let store = try makeStore()

        try store.insert(sampleRecord(id: "1", postedAt: "2024-01-01T00:00:00Z"))
        try store.insert(sampleRecord(id: "2", postedAt: "2024-06-15T00:00:00Z"))
        try store.insert(sampleRecord(id: "3", postedAt: "2024-12-31T00:00:00Z"))

        let results = try store.list(after: "2024-03-01", before: "2024-09-01")
        #expect(results.count == 1)
        #expect(results[0].id == "2")
    }

    @Test func listFilterByCategory() throws {
        let store = try makeStore()

        try store.insert(sampleRecord(id: "1", categories: "tool,technique", primaryCategory: "tool"))
        try store.insert(sampleRecord(id: "2", categories: "security", primaryCategory: "security"))

        let results = try store.list(category: "tool")
        #expect(results.count == 1)
        #expect(results[0].id == "1")
    }

    @Test func listFilterByDomain() throws {
        let store = try makeStore()

        try store.insert(sampleRecord(id: "1", domains: "ai,ml", primaryDomain: "ai"))
        try store.insert(sampleRecord(id: "2", domains: "finance", primaryDomain: "finance"))

        let results = try store.list(domain: "ai")
        #expect(results.count == 1)
        #expect(results[0].id == "1")
    }

    @Test func listWithLimit() throws {
        let store = try makeStore()

        for i in 1...10 {
            try store.insert(sampleRecord(id: "\(i)"))
        }

        let results = try store.list(limit: 3)
        #expect(results.count == 3)
    }

    // MARK: - Count

    @Test func countBookmarks() throws {
        let store = try makeStore()

        try store.insert(sampleRecord(id: "1"))
        try store.insert(sampleRecord(id: "2"))
        try store.insert(sampleRecord(id: "3"))

        #expect(try store.count() == 3)
    }

    // MARK: - Stats

    @Test func stats() throws {
        let store = try makeStore()

        try store.insert(sampleRecord(id: "1", authorHandle: "alice", postedAt: "2024-01-01T00:00:00Z", language: "en"))
        try store.insert(sampleRecord(id: "2", authorHandle: "bob", postedAt: "2024-06-15T00:00:00Z", language: "en"))
        try store.insert(sampleRecord(id: "3", authorHandle: "alice", postedAt: "2024-12-31T00:00:00Z", language: "fr"))

        let stats = try store.getStats()
        #expect(stats.totalBookmarks == 3)
        #expect(stats.uniqueAuthors == 2)
        #expect(stats.earliestDate == "2024-01-01T00:00:00Z")
        #expect(stats.latestDate == "2024-12-31T00:00:00Z")
        #expect(stats.topAuthors.first?.handle == "alice")
        #expect(stats.topAuthors.first?.count == 2)
        #expect(stats.languages.count == 2)
    }

    // MARK: - Category / Domain Counts

    @Test func categoryCounts() throws {
        let store = try makeStore()

        try store.insert(sampleRecord(id: "1", primaryCategory: "tool"))
        try store.insert(sampleRecord(id: "2", primaryCategory: "tool"))
        try store.insert(sampleRecord(id: "3", primaryCategory: "security"))

        let counts = try store.getCategoryCounts()
        #expect(counts["tool"] == 2)
        #expect(counts["security"] == 1)
    }

    @Test func domainCounts() throws {
        let store = try makeStore()

        try store.insert(sampleRecord(id: "1", primaryDomain: "ai"))
        try store.insert(sampleRecord(id: "2", primaryDomain: "ai"))
        try store.insert(sampleRecord(id: "3", primaryDomain: "finance"))

        let counts = try store.getDomainCounts()
        #expect(counts["ai"] == 2)
        #expect(counts["finance"] == 1)
    }

    // MARK: - Bulk Insert

    @Test func bulkInsert() throws {
        let store = try makeStore()

        let records = (1...50).map { i in
            sampleRecord(id: "\(i)", text: "Record \(i)")
        }

        try store.bulkInsert(records)
        #expect(try store.count() == 50)
    }
}
