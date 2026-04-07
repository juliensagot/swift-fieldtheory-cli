import Foundation

public struct SyncOptions: Sendable {
    public var incremental: Bool
    public var maxPages: Int
    public var delayMs: Int
    public var maxMinutes: Int
    public var stalePageLimit: Int
    public var checkpointEvery: Int

    public init(
        incremental: Bool = true,
        maxPages: Int = 500,
        delayMs: Int = 600,
        maxMinutes: Int = 30,
        stalePageLimit: Int = 3,
        checkpointEvery: Int = 25
    ) {
        self.incremental = incremental
        self.maxPages = maxPages
        self.delayMs = delayMs
        self.maxMinutes = maxMinutes
        self.stalePageLimit = stalePageLimit
        self.checkpointEvery = checkpointEvery
    }
}

public struct SyncProgress: Sendable {
    public let page: Int
    public let totalFetched: Int
    public let newAdded: Int
    public let running: Bool
    public let done: Bool
    public let stopReason: String?
}

public struct SyncResult: Sendable {
    public let added: Int
    public let totalBookmarks: Int
    public let pages: Int
    public let stopReason: String
}

public enum SyncError: Error, CustomStringConvertible {
    case authenticationError(String)
    case networkError(statusCode: Int, message: String)
    case allRetriesFailed(String)

    public var description: String {
        switch self {
        case .authenticationError(let msg): return msg
        case .networkError(let code, let msg): return "HTTP \(code): \(msg)"
        case .allRetriesFailed(let msg): return msg
        }
    }
}

public final class SyncEngine {
    private let httpClient: HTTPClientProtocol
    private let csrfToken: String
    private let cookieHeader: String

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"
    static let publicBearer = "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
    static let queryId = "Z9GWmP0kP2dajyckAaDUBw"
    static let operation = "Bookmarks"

    static let graphQLFeatures: [String: Bool] = [
        "graphql_timeline_v2_bookmark_timeline": true,
        "rweb_tipjar_consumption_enabled": true,
        "responsive_web_graphql_exclude_directive_enabled": true,
        "verified_phone_label_enabled": false,
        "creator_subscriptions_tweet_preview_api_enabled": true,
        "responsive_web_graphql_timeline_navigation_enabled": true,
        "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
        "communities_web_enable_tweet_community_results_fetch": true,
        "c9s_tweet_anatomy_moderator_badge_enabled": true,
        "articles_preview_enabled": true,
        "responsive_web_edit_tweet_api_enabled": true,
        "tweetypie_unmention_optimization_enabled": true,
        "responsive_web_uc_gql_enabled": true,
        "vibe_api_enabled": true,
        "responsive_web_text_conversations_enabled": false,
        "freedom_of_speech_not_reach_fetch_enabled": true,
        "longform_notetweets_rich_text_read_enabled": true,
        "longform_notetweets_inline_media_enabled": true,
        "responsive_web_enhance_cards_enabled": false,
        "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
        "responsive_web_media_download_video_enabled": false,
    ]

    public init(httpClient: HTTPClientProtocol, csrfToken: String, cookieHeader: String) {
        self.httpClient = httpClient
        self.csrfToken = csrfToken
        self.cookieHeader = cookieHeader
    }

    // MARK: - URL & Headers (internal for testing)

    static func buildURL(cursor: String? = nil) -> URL {
        var variables: [String: Any] = ["count": 20]
        if let cursor { variables["cursor"] = cursor }

        let variablesJSON = try! JSONSerialization.data(withJSONObject: variables)
        let featuresJSON = try! JSONSerialization.data(withJSONObject: graphQLFeatures)

        // Use percentEncodedQueryItems to control encoding — URLQueryItem's default
        // encoding doesn't encode "+" to "%2B", but the X API expects form-style
        // encoding where "+" means space. Cursor values contain "+" (base64).
        let variablesStr = String(data: variablesJSON, encoding: .utf8)!.formEncoded()
        let featuresStr = String(data: featuresJSON, encoding: .utf8)!.formEncoded()

        var components = URLComponents(string: "https://x.com/i/api/graphql/\(queryId)/\(operation)")!
        components.percentEncodedQuery = "variables=\(variablesStr)&features=\(featuresStr)"
        return components.url!
    }

    func buildRequest(cursor: String? = nil) -> URLRequest {
        var request = URLRequest(url: Self.buildURL(cursor: cursor))
        request.setValue("Bearer \(Self.publicBearer)", forHTTPHeaderField: "authorization")
        request.setValue(csrfToken, forHTTPHeaderField: "x-csrf-token")
        request.setValue("OAuth2Session", forHTTPHeaderField: "x-twitter-auth-type")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "user-agent")
        request.setValue(cookieHeader, forHTTPHeaderField: "cookie")
        return request
    }

    // MARK: - Fetch Page

    func fetchPage(cursor: String? = nil) async throws -> GraphQLParseResult {
        let request = buildRequest(cursor: cursor)
        let maxAttempts = 4

        var lastError: Error?

        for attempt in 0..<maxAttempts {
            let (data, response) = try await httpClient.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            if statusCode == 429 {
                let waitSeconds = min(15 * Int(pow(2.0, Double(attempt))), 120)
                lastError = SyncError.networkError(statusCode: 429, message: "Rate limited on attempt \(attempt + 1)")
                try await Task.sleep(for: .seconds(waitSeconds))
                continue
            }

            if statusCode >= 500 {
                lastError = SyncError.networkError(statusCode: statusCode, message: "Server error on attempt \(attempt + 1)")
                try await Task.sleep(for: .seconds(5 * (attempt + 1)))
                continue
            }

            if statusCode == 401 || statusCode == 403 {
                let text = String(data: data, encoding: .utf8) ?? ""
                throw SyncError.authenticationError(
                    "X API returned \(statusCode). Your session may have expired. " +
                    "Open Safari, go to https://x.com, make sure you're logged in, then retry.\n" +
                    "Response: \(String(text.prefix(300)))"
                )
            }

            if statusCode != 200 {
                let text = String(data: data, encoding: .utf8) ?? ""
                throw SyncError.networkError(statusCode: statusCode, message: String(text.prefix(300)))
            }

            return try GraphQLResponseParser.parse(data: data)
        }

        throw lastError ?? SyncError.allRetriesFailed("All retry attempts failed")
    }

    // MARK: - Merge

    public static func scoreRecord(_ record: BookmarkRecord) -> Int {
        var score = 0
        if record.postedAt != nil { score += 2 }
        if record.authorProfileImageUrl != nil { score += 2 }
        if record.author != nil { score += 3 }
        if record.engagement != nil { score += 3 }
        if (record.mediaObjects?.count ?? 0) > 0 { score += 3 }
        if (record.links?.count ?? 0) > 0 { score += 2 }
        return score
    }

    public static func mergeRecords(
        existing: [BookmarkRecord],
        incoming: [BookmarkRecord]
    ) -> (merged: [BookmarkRecord], added: Int) {
        var byId: [String: BookmarkRecord] = [:]
        for r in existing { byId[r.id] = r }

        var added = 0
        for record in incoming {
            if byId[record.id] == nil { added += 1 }
            if let prev = byId[record.id] {
                byId[record.id] = scoreRecord(record) >= scoreRecord(prev) ? record : prev
            } else {
                byId[record.id] = record
            }
        }

        let merged = Array(byId.values).sorted { a, b in
            (a.bookmarkedAt ?? a.postedAt ?? a.syncedAt) > (b.bookmarkedAt ?? b.postedAt ?? b.syncedAt)
        }
        return (merged, added)
    }

    // MARK: - Sync

    public func sync(
        options: SyncOptions = SyncOptions(),
        existingRecords: [BookmarkRecord] = [],
        onProgress: ((SyncProgress) -> Void)? = nil,
        onCheckpoint: (([BookmarkRecord]) -> Void)? = nil
    ) async throws -> (result: SyncResult, records: [BookmarkRecord]) {
        let started = Date()
        var existing = existingRecords
        let newestKnownId: String? = options.incremental
            ? existing.first?.id
            : nil

        var page = 0
        var totalAdded = 0
        var stalePages = 0
        var cursor: String?
        var allSeenIds: [String] = []
        var stopReason = "unknown"

        while page < options.maxPages {
            if Date().timeIntervalSince(started) > Double(options.maxMinutes) * 60 {
                stopReason = "max runtime reached"
                break
            }

            let pageResult = try await fetchPage(cursor: cursor)
            page += 1

            if pageResult.records.isEmpty && pageResult.nextCursor == nil {
                stopReason = "end of bookmarks"
                break
            }

            let (merged, added) = Self.mergeRecords(existing: existing, incoming: pageResult.records)
            existing = merged
            totalAdded += added
            allSeenIds.append(contentsOf: pageResult.records.map(\.id))

            let reachedLatest = newestKnownId != nil && pageResult.records.contains { $0.id == newestKnownId }
            stalePages = added == 0 ? stalePages + 1 : 0

            onProgress?(SyncProgress(
                page: page,
                totalFetched: allSeenIds.count,
                newAdded: totalAdded,
                running: true,
                done: false,
                stopReason: nil
            ))

            if reachedLatest {
                stopReason = "caught up to newest stored bookmark"
                break
            }
            if stalePages >= options.stalePageLimit {
                stopReason = "no new bookmarks (stale)"
                break
            }
            if pageResult.nextCursor == nil {
                stopReason = "end of bookmarks"
                break
            }

            if page % options.checkpointEvery == 0 {
                onCheckpoint?(existing)
            }

            cursor = pageResult.nextCursor

            if page < options.maxPages {
                try await Task.sleep(for: .milliseconds(options.delayMs))
            }
        }

        if stopReason == "unknown" {
            stopReason = page >= options.maxPages ? "max pages reached" : "unknown"
        }

        onProgress?(SyncProgress(
            page: page,
            totalFetched: allSeenIds.count,
            newAdded: totalAdded,
            running: false,
            done: true,
            stopReason: stopReason
        ))

        let result = SyncResult(
            added: totalAdded,
            totalBookmarks: existing.count,
            pages: page,
            stopReason: stopReason
        )
        return (result, existing)
    }
}

extension String {
    /// Percent-encode for use as a URL query parameter value, encoding "+" as "%2B".
    func formEncoded() -> String {
        var allowed = CharacterSet.urlQueryAllowed
        // Remove characters that need encoding in query values
        allowed.remove(charactersIn: "+&=")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
