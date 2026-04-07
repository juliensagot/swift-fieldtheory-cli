import Testing
import Foundation
@testable import FieldTheory

// MARK: - Mock HTTP Client

final class MockHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    var responses: [(Data, HTTPURLResponse)] = []
    private var callIndex = 0
    var receivedRequests: [URLRequest] = []

    func enqueue(statusCode: Int, json: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(url: URL(string: "https://x.com")!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        responses.append((data, response))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        receivedRequests.append(request)
        guard callIndex < responses.count else {
            fatalError("MockHTTPClient: no more responses queued (call \(callIndex))")
        }
        let result = responses[callIndex]
        callIndex += 1
        return result
    }
}

// MARK: - Test Helpers

private func makeGraphQLResponse(
    tweetIds: [String],
    cursor: String? = nil
) -> [String: Any] {
    var entries: [[String: Any]] = tweetIds.map { id in
        [
            "entryId": "tweet-\(id)",
            "sortIndex": "1867614419191283712",
            "content": [
                "entryType": "TimelineTimelineItem",
                "itemContent": [
                    "tweet_results": [
                        "result": [
                            "__typename": "Tweet",
                            "tweet": [
                                "rest_id": id,
                                "legacy": [
                                    "id_str": id,
                                    "full_text": "Tweet \(id)",
                                    "favorite_count": 1,
                                    "retweet_count": 0,
                                    "reply_count": 0,
                                    "quote_count": 0,
                                    "bookmark_count": 0,
                                    "lang": "en",
                                    "entities": ["urls": []]
                                ] as [String: Any],
                                "core": [
                                    "user_results": [
                                        "result": [
                                            "core": [
                                                "screen_name": "user\(id)",
                                                "name": "User \(id)",
                                            ],
                                            "avatar": [
                                                "image_url": "https://img.jpg"
                                            ]
                                        ]
                                    ]
                                ],
                                "views": ["count": "100"]
                            ] as [String: Any]
                        ] as [String: Any]
                    ]
                ]
            ]
        ] as [String: Any]
    }

    if let cursor {
        entries.append([
            "entryId": "cursor-bottom-\(cursor)",
            "sortIndex": "0",
            "content": [
                "entryType": "TimelineTimelineCursor",
                "value": cursor,
                "cursorType": "Bottom"
            ]
        ])
    }

    return [
        "data": [
            "bookmark_timeline_v2": [
                "timeline": [
                    "instructions": [
                        ["type": "TimelineAddEntries", "entries": entries]
                    ]
                ]
            ]
        ]
    ]
}

private func emptyGraphQLResponse() -> [String: Any] {
    [
        "data": [
            "bookmark_timeline_v2": [
                "timeline": [
                    "instructions": [
                        ["type": "TimelineAddEntries", "entries": []]
                    ]
                ]
            ]
        ]
    ]
}

// MARK: - Tests

@Suite("SyncEngine")
struct SyncEngineTests {

    // MARK: - URL Building

    @Test func buildURLWithoutCursor() {
        let url = SyncEngine.buildURL()
        let urlStr = url.absoluteString
        #expect(urlStr.contains("x.com/i/api/graphql/"))
        #expect(urlStr.contains(SyncEngine.queryId))
        #expect(urlStr.contains(SyncEngine.operation))
        #expect(urlStr.contains("variables"))
        #expect(urlStr.contains("features"))
    }

    @Test func buildURLWithCursor() {
        let url = SyncEngine.buildURL(cursor: "DAACCgACGdy")
        let urlStr = url.absoluteString
        #expect(urlStr.contains("DAACCgACGdy"))
    }

    // MARK: - Headers

    @Test func requestHeaders() {
        let client = MockHTTPClient()
        let engine = SyncEngine(httpClient: client, csrfToken: "test_csrf", cookieHeader: "ct0=test_csrf; auth_token=xyz")
        let request = engine.buildRequest()

        #expect(request.value(forHTTPHeaderField: "authorization")?.contains(SyncEngine.publicBearer) == true)
        #expect(request.value(forHTTPHeaderField: "x-csrf-token") == "test_csrf")
        #expect(request.value(forHTTPHeaderField: "x-twitter-auth-type") == "OAuth2Session")
        #expect(request.value(forHTTPHeaderField: "cookie") == "ct0=test_csrf; auth_token=xyz")
        #expect(request.value(forHTTPHeaderField: "user-agent") == SyncEngine.userAgent)
    }

    // MARK: - Merge

    @Test func mergeRecordsDedup() {
        let existing = [
            BookmarkRecord(id: "1", tweetId: "1", url: "u", text: "A", syncedAt: "2024-01-01T00:00:00Z"),
            BookmarkRecord(id: "2", tweetId: "2", url: "u", text: "B", syncedAt: "2024-01-01T00:00:00Z"),
        ]
        let incoming = [
            BookmarkRecord(id: "2", tweetId: "2", url: "u", text: "B updated", syncedAt: "2024-01-02T00:00:00Z"),
            BookmarkRecord(id: "3", tweetId: "3", url: "u", text: "C", syncedAt: "2024-01-02T00:00:00Z"),
        ]

        let (merged, added) = SyncEngine.mergeRecords(existing: existing, incoming: incoming)
        #expect(merged.count == 3)
        #expect(added == 1) // only "3" is new
    }

    @Test func mergeHigherScoreWins() {
        let sparse = BookmarkRecord(id: "1", tweetId: "1", url: "u", text: "sparse", syncedAt: "2024-01-01T00:00:00Z")
        let rich = BookmarkRecord(
            id: "1", tweetId: "1", url: "u", text: "rich",
            postedAt: "2024-01-01T00:00:00Z", syncedAt: "2024-01-01T00:00:00Z",
            engagement: BookmarkEngagement(likeCount: 42),
            mediaObjects: [BookmarkMediaObject(type: "photo")]
        )

        #expect(SyncEngine.scoreRecord(rich) > SyncEngine.scoreRecord(sparse))

        let (merged, _) = SyncEngine.mergeRecords(existing: [sparse], incoming: [rich])
        #expect(merged[0].text == "rich")
    }

    // MARK: - Single Page Fetch

    @Test func singlePageFetch() async throws {
        let client = MockHTTPClient()
        client.enqueue(statusCode: 200, json: makeGraphQLResponse(tweetIds: ["10", "11"]))

        let engine = SyncEngine(httpClient: client, csrfToken: "csrf", cookieHeader: "ct0=csrf")
        let result = try await engine.fetchPage()

        #expect(result.records.count == 2)
        #expect(result.records[0].tweetId == "10")
    }

    // MARK: - Pagination

    @Test func cursorPagination() async throws {
        let client = MockHTTPClient()
        // Page 1: 2 tweets + cursor
        client.enqueue(statusCode: 200, json: makeGraphQLResponse(tweetIds: ["1", "2"], cursor: "cur1"))
        // Page 2: 2 tweets + cursor
        client.enqueue(statusCode: 200, json: makeGraphQLResponse(tweetIds: ["3", "4"], cursor: "cur2"))
        // Page 3: 1 tweet, no cursor → end
        client.enqueue(statusCode: 200, json: makeGraphQLResponse(tweetIds: ["5"]))

        let engine = SyncEngine(httpClient: client, csrfToken: "csrf", cookieHeader: "ct0=csrf")
        let (result, records) = try await engine.sync(
            options: SyncOptions(delayMs: 0)
        )

        #expect(result.pages == 3)
        #expect(result.added == 5)
        #expect(result.stopReason == "end of bookmarks")
        #expect(records.count == 5)
    }

    // MARK: - Incremental Stop

    @Test func incrementalStopsAtNewestKnown() async throws {
        let client = MockHTTPClient()
        // Page 1: new tweets
        client.enqueue(statusCode: 200, json: makeGraphQLResponse(tweetIds: ["5", "4"], cursor: "cur1"))
        // Page 2: contains known ID "3"
        client.enqueue(statusCode: 200, json: makeGraphQLResponse(tweetIds: ["3", "2"], cursor: "cur2"))

        let existing = [
            BookmarkRecord(id: "3", tweetId: "3", url: "u", text: "known", bookmarkedAt: "2024-01-01T00:00:00Z", syncedAt: "2024-01-01T00:00:00Z"),
        ]

        let engine = SyncEngine(httpClient: client, csrfToken: "csrf", cookieHeader: "ct0=csrf")
        let (result, _) = try await engine.sync(
            options: SyncOptions(delayMs: 0),
            existingRecords: existing
        )

        #expect(result.stopReason == "caught up to newest stored bookmark")
        #expect(result.pages == 2)
    }

    // MARK: - Stale Pages

    @Test func stalePageLimit() async throws {
        let client = MockHTTPClient()
        let existing = [
            BookmarkRecord(id: "1", tweetId: "1", url: "u", text: "existing", syncedAt: "2024-01-01T00:00:00Z"),
        ]

        // 3 pages all returning the same known ID → 0 new each time
        // Use incremental: false so newestKnownId is nil (won't trigger "caught up")
        for _ in 0..<3 {
            client.enqueue(statusCode: 200, json: makeGraphQLResponse(tweetIds: ["1"], cursor: "cur"))
        }

        let engine = SyncEngine(httpClient: client, csrfToken: "csrf", cookieHeader: "ct0=csrf")
        let (result, _) = try await engine.sync(
            options: SyncOptions(incremental: false, delayMs: 0, stalePageLimit: 3),
            existingRecords: existing
        )

        #expect(result.stopReason == "no new bookmarks (stale)")
    }

    // MARK: - Auth Error

    @Test func authErrorThrowsImmediately() async throws {
        let client = MockHTTPClient()
        client.enqueue(statusCode: 401, json: ["errors": [["message": "Unauthorized"]]])

        let engine = SyncEngine(httpClient: client, csrfToken: "csrf", cookieHeader: "ct0=csrf")

        await #expect(throws: SyncError.self) {
            try await engine.fetchPage()
        }
    }

    @Test func forbiddenErrorThrowsImmediately() async throws {
        let client = MockHTTPClient()
        client.enqueue(statusCode: 403, json: ["errors": [["message": "Forbidden"]]])

        let engine = SyncEngine(httpClient: client, csrfToken: "csrf", cookieHeader: "ct0=csrf")

        await #expect(throws: SyncError.self) {
            try await engine.fetchPage()
        }
    }

    // MARK: - Progress Callback

    @Test func progressCallback() async throws {
        let client = MockHTTPClient()
        client.enqueue(statusCode: 200, json: makeGraphQLResponse(tweetIds: ["1", "2"]))

        let engine = SyncEngine(httpClient: client, csrfToken: "csrf", cookieHeader: "ct0=csrf")

        var progressUpdates: [SyncProgress] = []
        let (_, _) = try await engine.sync(
            options: SyncOptions(delayMs: 0),
            onProgress: { progress in progressUpdates.append(progress) }
        )

        // Should have at least 2 updates: one in-flight + one final
        #expect(progressUpdates.count >= 2)
        #expect(progressUpdates.last?.done == true)
        #expect(progressUpdates.last?.running == false)
        #expect(progressUpdates.first?.running == true)
    }

    // MARK: - Checkpoint

    @Test func checkpointCallback() async throws {
        let client = MockHTTPClient()
        // 3 pages with cursor
        for i in 0..<3 {
            client.enqueue(statusCode: 200, json: makeGraphQLResponse(
                tweetIds: ["\(i * 2)", "\(i * 2 + 1)"],
                cursor: i < 2 ? "cur\(i)" : nil
            ))
        }

        let engine = SyncEngine(httpClient: client, csrfToken: "csrf", cookieHeader: "ct0=csrf")

        var checkpointCount = 0
        let (_, _) = try await engine.sync(
            options: SyncOptions(delayMs: 0, checkpointEvery: 2),
            onCheckpoint: { _ in checkpointCount += 1 }
        )

        #expect(checkpointCount >= 1)
    }
}
