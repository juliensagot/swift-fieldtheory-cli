import Foundation

public struct BookmarkStats: Sendable {
    public let totalBookmarks: Int
    public let uniqueAuthors: Int
    public let earliestDate: String?
    public let latestDate: String?
    public let topAuthors: [(handle: String, count: Int)]
    public let languages: [(language: String, count: Int)]
}

public final class BookmarkStore {
    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    // MARK: - Schema

    public func initSchema() throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS meta (
                key TEXT PRIMARY KEY,
                value TEXT
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS bookmarks (
                id TEXT PRIMARY KEY,
                tweet_id TEXT NOT NULL,
                url TEXT NOT NULL,
                text TEXT NOT NULL,
                author_handle TEXT,
                author_name TEXT,
                author_profile_image_url TEXT,
                posted_at TEXT,
                bookmarked_at TEXT,
                synced_at TEXT NOT NULL,
                conversation_id TEXT,
                in_reply_to_status_id TEXT,
                quoted_status_id TEXT,
                language TEXT,
                like_count INTEGER,
                repost_count INTEGER,
                reply_count INTEGER,
                quote_count INTEGER,
                bookmark_count INTEGER,
                view_count INTEGER,
                media_count INTEGER DEFAULT 0,
                media_json TEXT,
                link_count INTEGER DEFAULT 0,
                links_json TEXT,
                tags_json TEXT,
                ingested_via TEXT,
                categories TEXT,
                primary_category TEXT,
                github_urls TEXT,
                domains TEXT,
                primary_domain TEXT,
                quoted_tweet_json TEXT
            )
        """)

        try db.execute("CREATE INDEX IF NOT EXISTS idx_bookmarks_author ON bookmarks(author_handle)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_bookmarks_posted ON bookmarks(posted_at)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_bookmarks_language ON bookmarks(language)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_bookmarks_category ON bookmarks(primary_category)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_bookmarks_domain ON bookmarks(primary_domain)")

        try db.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS bookmarks_fts USING fts5(
                text,
                author_handle,
                author_name,
                content=bookmarks,
                content_rowid=rowid,
                tokenize='porter unicode61'
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS media_files (
                id TEXT PRIMARY KEY,
                bookmark_id TEXT NOT NULL,
                source_url TEXT NOT NULL,
                local_path TEXT,
                content_type TEXT,
                width INTEGER,
                height INTEGER,
                alt_text TEXT,
                byte_count INTEGER,
                status TEXT NOT NULL DEFAULT 'pending',
                reason TEXT,
                fetched_at TEXT NOT NULL,
                UNIQUE(bookmark_id, source_url)
            )
        """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_media_files_bookmark ON media_files(bookmark_id)")

        try db.execute("INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', '5')")
    }

    // MARK: - Insert

    public func insert(_ record: BookmarkRecord) throws {
        let mediaJSON = record.mediaObjects.flatMap { try? jsonEncode($0) }
        let linksJSON = record.links.flatMap { try? jsonEncode($0) }
        let tagsJSON = record.tags.flatMap { try? jsonEncode($0) }
        let quotedTweetJSON = record.quotedTweet.flatMap { try? jsonEncode($0) }

        try db.execute("""
            INSERT OR REPLACE INTO bookmarks (
                id, tweet_id, url, text, author_handle, author_name, author_profile_image_url,
                posted_at, bookmarked_at, synced_at, conversation_id, in_reply_to_status_id,
                quoted_status_id, language, like_count, repost_count, reply_count, quote_count,
                bookmark_count, view_count, media_count, media_json, link_count, links_json, tags_json,
                ingested_via, categories, primary_category, github_urls, domains, primary_domain,
                quoted_tweet_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            .text(record.id),
            .text(record.tweetId),
            .text(record.url),
            .text(record.text),
            optText(record.authorHandle),
            optText(record.authorName),
            optText(record.authorProfileImageUrl),
            optText(record.postedAt),
            optText(record.bookmarkedAt),
            .text(record.syncedAt),
            optText(record.conversationId),
            optText(record.inReplyToStatusId),
            optText(record.quotedStatusId),
            optText(record.language),
            optInt(record.engagement?.likeCount),
            optInt(record.engagement?.repostCount),
            optInt(record.engagement?.replyCount),
            optInt(record.engagement?.quoteCount),
            optInt(record.engagement?.bookmarkCount),
            optInt(record.engagement?.viewCount),
            .integer(Int64(record.media?.count ?? record.mediaObjects?.count ?? 0)),
            optText(mediaJSON),
            .integer(Int64(record.links?.count ?? 0)),
            optText(linksJSON),
            optText(tagsJSON),
            optText(record.ingestedVia),
            optText(record.categories),
            optText(record.primaryCategory),
            optText(record.githubUrls),
            optText(record.domains),
            optText(record.primaryDomain),
            optText(quotedTweetJSON),
        ])
    }

    public func bulkInsert(_ records: [BookmarkRecord]) throws {
        try db.transaction {
            for record in records {
                try insert(record)
            }
        }
    }

    // MARK: - Get

    public func getById(_ id: String) throws -> BookmarkRecord? {
        let rows = try db.query(
            "SELECT * FROM bookmarks WHERE id = ?",
            [.text(id)]
        )
        guard let row = rows.first else { return nil }
        return rowToRecord(row)
    }

    // MARK: - Count

    public func count() throws -> Int {
        let rows = try db.query("SELECT count(*) FROM bookmarks")
        if case .integer(let n) = rows[0][0] { return Int(n) }
        return 0
    }

    // MARK: - FTS

    public func rebuildFTS() throws {
        try db.execute("INSERT INTO bookmarks_fts(bookmarks_fts) VALUES('rebuild')")
    }

    public func search(_ query: String, limit: Int = 50) throws -> [BookmarkRecord] {
        let rows = try db.query("""
            SELECT b.* FROM bookmarks b
            WHERE b.rowid IN (
                SELECT rowid FROM bookmarks_fts WHERE bookmarks_fts MATCH ?
            )
            ORDER BY (
                SELECT bm25(bookmarks_fts, 5.0, 1.0, 1.0)
                FROM bookmarks_fts WHERE bookmarks_fts.rowid = b.rowid
            )
            LIMIT ?
        """, [.text(query), .integer(Int64(limit))])

        return rows.map { rowToRecord($0) }
    }

    // MARK: - List

    public func list(
        author: String? = nil,
        after: String? = nil,
        before: String? = nil,
        category: String? = nil,
        domain: String? = nil,
        limit: Int = 100,
        offset: Int = 0
    ) throws -> [BookmarkRecord] {
        var conditions: [String] = []
        var params: [SQLiteValue] = []

        if let author {
            conditions.append("author_handle = ?")
            params.append(.text(author))
        }
        if let after {
            conditions.append("posted_at > ?")
            params.append(.text(after))
        }
        if let before {
            conditions.append("posted_at < ?")
            params.append(.text(before))
        }
        if let category {
            conditions.append("primary_category = ?")
            params.append(.text(category))
        }
        if let domain {
            conditions.append("primary_domain = ?")
            params.append(.text(domain))
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")

        params.append(.integer(Int64(limit)))
        params.append(.integer(Int64(offset)))

        let rows = try db.query(
            "SELECT * FROM bookmarks \(whereClause) ORDER BY bookmarked_at DESC, posted_at DESC LIMIT ? OFFSET ?",
            params
        )

        return rows.map { rowToRecord($0) }
    }

    // MARK: - Stats

    public func getStats() throws -> BookmarkStats {
        let countRows = try db.query("SELECT count(*) FROM bookmarks")
        let total = countRows[0][0].intValue ?? 0

        let authorRows = try db.query("SELECT count(DISTINCT author_handle) FROM bookmarks")
        let uniqueAuthors = authorRows[0][0].intValue ?? 0

        let dateRows = try db.query("SELECT min(posted_at), max(posted_at) FROM bookmarks")
        let earliest = dateRows[0][0].textValue
        let latest = dateRows[0][1].textValue

        let topAuthorRows = try db.query("""
            SELECT author_handle, count(*) as cnt FROM bookmarks
            WHERE author_handle IS NOT NULL
            GROUP BY author_handle ORDER BY cnt DESC LIMIT 20
        """)
        let topAuthors = topAuthorRows.compactMap { row -> (handle: String, count: Int)? in
            guard let handle = row[0].textValue, let cnt = row[1].intValue else { return nil }
            return (handle, cnt)
        }

        let langRows = try db.query("""
            SELECT language, count(*) as cnt FROM bookmarks
            WHERE language IS NOT NULL
            GROUP BY language ORDER BY cnt DESC
        """)
        let languages = langRows.compactMap { row -> (language: String, count: Int)? in
            guard let lang = row[0].textValue, let cnt = row[1].intValue else { return nil }
            return (lang, cnt)
        }

        return BookmarkStats(
            totalBookmarks: total,
            uniqueAuthors: uniqueAuthors,
            earliestDate: earliest,
            latestDate: latest,
            topAuthors: topAuthors,
            languages: languages
        )
    }

    // MARK: - Category / Domain Counts

    public func getCategoryCounts() throws -> [String: Int] {
        let rows = try db.query("""
            SELECT primary_category, count(*) FROM bookmarks
            WHERE primary_category IS NOT NULL
            GROUP BY primary_category ORDER BY count(*) DESC
        """)
        var result: [String: Int] = [:]
        for row in rows {
            if let cat = row[0].textValue, let cnt = row[1].intValue {
                result[cat] = cnt
            }
        }
        return result
    }

    public func getDomainCounts() throws -> [String: Int] {
        let rows = try db.query("""
            SELECT primary_domain, count(*) FROM bookmarks
            WHERE primary_domain IS NOT NULL
            GROUP BY primary_domain ORDER BY count(*) DESC
        """)
        var result: [String: Int] = [:]
        for row in rows {
            if let dom = row[0].textValue, let cnt = row[1].intValue {
                result[dom] = cnt
            }
        }
        return result
    }

    // MARK: - Helpers

    private func optText(_ value: String?) -> SQLiteValue {
        value.map { .text($0) } ?? .null
    }

    private func optInt(_ value: Int?) -> SQLiteValue {
        value.map { .integer(Int64($0)) } ?? .null
    }

    private func jsonEncode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)!
    }

    private func rowToRecord(_ row: [SQLiteValue]) -> BookmarkRecord {
        // Column order matches CREATE TABLE:
        //  0: id, 1: tweet_id, 2: url, 3: text, 4: author_handle, 5: author_name,
        //  6: author_profile_image_url, 7: posted_at, 8: bookmarked_at, 9: synced_at,
        // 10: conversation_id, 11: in_reply_to_status_id, 12: quoted_status_id,
        // 13: language, 14-19: engagement counts, 20: media_count,
        // 21: media_json, 22: link_count, 23: links_json, 24: tags_json,
        // 25: ingested_via, 26: categories, 27: primary_category,
        // 28: github_urls, 29: domains, 30: primary_domain, 31: quoted_tweet_json
        var record = BookmarkRecord(
            id: row[0].textValue ?? "",
            tweetId: row[1].textValue ?? "",
            authorHandle: row[4].textValue,
            authorName: row[5].textValue,
            authorProfileImageUrl: row[6].textValue,
            url: row[2].textValue ?? "",
            text: row[3].textValue ?? "",
            postedAt: row[7].textValue,
            bookmarkedAt: row[8].textValue,
            syncedAt: row[9].textValue ?? "",
            conversationId: row[10].textValue,
            inReplyToStatusId: row[11].textValue,
            quotedStatusId: row[12].textValue,
            language: row[13].textValue,
            engagement: BookmarkEngagement(
                likeCount: row[14].intValue,
                repostCount: row[15].intValue,
                replyCount: row[16].intValue,
                quoteCount: row[17].intValue,
                bookmarkCount: row[18].intValue,
                viewCount: row[19].intValue
            ),
            ingestedVia: row[25].textValue,
            categories: row[26].textValue,
            primaryCategory: row[27].textValue,
            githubUrls: row[28].textValue,
            domains: row[29].textValue,
            primaryDomain: row[30].textValue
        )

        if let mediaJSON = row[21].textValue, let data = mediaJSON.data(using: .utf8) {
            record.mediaObjects = try? JSONDecoder().decode([BookmarkMediaObject].self, from: data)
        }
        if let linksJSON = row[23].textValue, let data = linksJSON.data(using: .utf8) {
            record.links = try? JSONDecoder().decode([String].self, from: data)
        }
        if let tagsJSON = row[24].textValue, let data = tagsJSON.data(using: .utf8) {
            record.tags = try? JSONDecoder().decode([String].self, from: data)
        }
        if let qtJSON = row[31].textValue, let data = qtJSON.data(using: .utf8) {
            record.quotedTweet = try? JSONDecoder().decode(QuotedTweetSnapshot.self, from: data)
        }

        return record
    }
}

// MARK: - SQLiteValue convenience

extension SQLiteValue {
    var textValue: String? {
        if case .text(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case .integer(let v) = self { return Int(v) }
        return nil
    }
}
