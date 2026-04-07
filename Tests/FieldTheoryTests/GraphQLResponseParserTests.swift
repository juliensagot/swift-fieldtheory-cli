import Testing
import Foundation
@testable import FieldTheory

@Suite("GraphQLResponseParser")
struct GraphQLResponseParserTests {

    // MARK: - Helpers

    private func makeResponse(instructions: [[String: Any]]) -> [String: Any] {
        [
            "data": [
                "bookmark_timeline_v2": [
                    "timeline": [
                        "instructions": instructions
                    ]
                ]
            ]
        ]
    }

    private func makeAddEntriesInstruction(entries: [[String: Any]]) -> [String: Any] {
        ["type": "TimelineAddEntries", "entries": entries]
    }

    private func makeTweetEntry(
        entryId: String = "tweet-123",
        sortIndex: String = "1867614419191283712",
        tweetId: String = "123",
        fullText: String = "Hello world",
        authorHandle: String = "testuser",
        authorName: String = "Test User",
        authorProfileImage: String = "https://pbs.twimg.com/photo.jpg",
        likeCount: Int = 42,
        retweetCount: Int = 10,
        replyCount: Int = 5,
        quoteCount: Int = 2,
        bookmarkCount: Int = 3,
        viewCount: String = "1000",
        language: String = "en",
        media: [[String: Any]]? = nil,
        urls: [[String: Any]]? = nil,
        noteTweetText: String? = nil,
        quotedTweet: [String: Any]? = nil
    ) -> [String: Any] {
        var legacy: [String: Any] = [
            "id_str": tweetId,
            "full_text": fullText,
            "favorite_count": likeCount,
            "retweet_count": retweetCount,
            "reply_count": replyCount,
            "quote_count": quoteCount,
            "bookmark_count": bookmarkCount,
            "lang": language,
            "entities": ["urls": urls ?? []] as [String: Any]
        ]

        if let media {
            legacy["extended_entities"] = ["media": media]
        }

        var tweet: [String: Any] = [
            "rest_id": tweetId,
            "legacy": legacy,
            "core": [
                "user_results": [
                    "result": [
                        "core": [
                            "screen_name": authorHandle,
                            "name": authorName,
                        ],
                        "avatar": [
                            "image_url": authorProfileImage
                        ]
                    ]
                ]
            ],
            "views": ["count": viewCount]
        ]

        if let noteTweetText {
            tweet["note_tweet"] = [
                "note_tweet_results": [
                    "result": ["text": noteTweetText]
                ]
            ]
        }

        if let quotedTweet {
            tweet["quoted_status_result"] = ["result": quotedTweet]
        }

        return [
            "entryId": entryId,
            "sortIndex": sortIndex,
            "content": [
                "entryType": "TimelineTimelineItem",
                "itemContent": [
                    "tweet_results": [
                        "result": [
                            "__typename": "Tweet",
                            "tweet": tweet
                        ] as [String: Any]
                    ]
                ]
            ]
        ]
    }

    private func makeCursorEntry(cursor: String) -> [String: Any] {
        [
            "entryId": "cursor-bottom-\(cursor)",
            "sortIndex": "0",
            "content": [
                "entryType": "TimelineTimelineCursor",
                "value": cursor,
                "cursorType": "Bottom"
            ]
        ]
    }

    // MARK: - Empty Response

    @Test func emptyResponse() throws {
        let json = makeResponse(instructions: [])
        let result = try GraphQLResponseParser.parse(json)
        #expect(result.records.isEmpty)
        #expect(result.nextCursor == nil)
    }

    @Test func emptyEntries() throws {
        let json = makeResponse(instructions: [
            makeAddEntriesInstruction(entries: [])
        ])
        let result = try GraphQLResponseParser.parse(json)
        #expect(result.records.isEmpty)
    }

    // MARK: - Single Tweet

    @Test func parseSingleTweet() throws {
        let json = makeResponse(instructions: [
            makeAddEntriesInstruction(entries: [
                makeTweetEntry(
                    tweetId: "456",
                    fullText: "Swift is great",
                    authorHandle: "swiftdev",
                    authorName: "Swift Developer"
                )
            ])
        ])

        let result = try GraphQLResponseParser.parse(json)
        #expect(result.records.count == 1)

        let record = result.records[0]
        #expect(record.tweetId == "456")
        #expect(record.text == "Swift is great")
        #expect(record.authorHandle == "swiftdev")
        #expect(record.authorName == "Swift Developer")
        #expect(record.url == "https://x.com/swiftdev/status/456")
    }

    // MARK: - Cursor

    @Test func cursorExtracted() throws {
        let json = makeResponse(instructions: [
            makeAddEntriesInstruction(entries: [
                makeTweetEntry(tweetId: "1"),
                makeCursorEntry(cursor: "DAACCgACGdy")
            ])
        ])

        let result = try GraphQLResponseParser.parse(json)
        #expect(result.records.count == 1)
        #expect(result.nextCursor == "DAACCgACGdy")
    }

    // MARK: - Note Tweet

    @Test func noteTweetTextTakesPriority() throws {
        let json = makeResponse(instructions: [
            makeAddEntriesInstruction(entries: [
                makeTweetEntry(
                    tweetId: "789",
                    fullText: "Truncated text...",
                    noteTweetText: "This is the full long-form article text that was truncated in the legacy field"
                )
            ])
        ])

        let result = try GraphQLResponseParser.parse(json)
        #expect(result.records[0].text == "This is the full long-form article text that was truncated in the legacy field")
    }

    // MARK: - Media

    @Test func parsePhotoMedia() throws {
        let json = makeResponse(instructions: [
            makeAddEntriesInstruction(entries: [
                makeTweetEntry(
                    tweetId: "100",
                    fullText: "Check this photo",
                    media: [
                        [
                            "type": "photo",
                            "media_url_https": "https://pbs.twimg.com/media/photo.jpg",
                            "original_info": ["width": 1920, "height": 1080],
                            "ext_alt_text": "A nice photo"
                        ] as [String: Any]
                    ]
                )
            ])
        ])

        let result = try GraphQLResponseParser.parse(json)
        let record = result.records[0]
        #expect(record.mediaObjects?.count == 1)
        #expect(record.mediaObjects?[0].type == "photo")
        #expect(record.mediaObjects?[0].mediaUrl == "https://pbs.twimg.com/media/photo.jpg")
        #expect(record.mediaObjects?[0].width == 1920)
        #expect(record.mediaObjects?[0].height == 1080)
        #expect(record.mediaObjects?[0].extAltText == "A nice photo")
    }

    @Test func parseVideoMedia() throws {
        let json = makeResponse(instructions: [
            makeAddEntriesInstruction(entries: [
                makeTweetEntry(
                    tweetId: "101",
                    fullText: "Watch this",
                    media: [
                        [
                            "type": "video",
                            "media_url_https": "https://pbs.twimg.com/thumb.jpg",
                            "video_info": [
                                "variants": [
                                    ["bitrate": 2176000, "content_type": "video/mp4", "url": "https://video.twimg.com/720.mp4"],
                                    ["content_type": "application/x-mpegURL", "url": "https://video.twimg.com/pl.m3u8"],
                                    ["bitrate": 632000, "content_type": "video/mp4", "url": "https://video.twimg.com/360.mp4"],
                                ] as [[String: Any]]
                            ] as [String: Any]
                        ] as [String: Any]
                    ]
                )
            ])
        ])

        let result = try GraphQLResponseParser.parse(json)
        let media = result.records[0].mediaObjects?[0]
        #expect(media?.type == "video")
        // Should only include mp4 variants, sorted by bitrate desc
        #expect(media?.variants?.count == 2)
        #expect(media?.variants?[0].bitrate == 2176000)
        #expect(media?.variants?[1].bitrate == 632000)
    }

    // MARK: - Engagement

    @Test func parseEngagement() throws {
        let json = makeResponse(instructions: [
            makeAddEntriesInstruction(entries: [
                makeTweetEntry(
                    tweetId: "200",
                    likeCount: 100,
                    retweetCount: 50,
                    replyCount: 25,
                    quoteCount: 10,
                    bookmarkCount: 5,
                    viewCount: "50000"
                )
            ])
        ])

        let result = try GraphQLResponseParser.parse(json)
        let eng = result.records[0].engagement
        #expect(eng?.likeCount == 100)
        #expect(eng?.repostCount == 50)
        #expect(eng?.replyCount == 25)
        #expect(eng?.quoteCount == 10)
        #expect(eng?.bookmarkCount == 5)
        #expect(eng?.viewCount == 50000)
    }

    // MARK: - Links

    @Test func parseLinks() throws {
        let json = makeResponse(instructions: [
            makeAddEntriesInstruction(entries: [
                makeTweetEntry(
                    tweetId: "300",
                    fullText: "Check out this link",
                    urls: [
                        ["expanded_url": "https://github.com/apple/swift"],
                        ["expanded_url": "https://t.co/abc123"], // should be excluded
                        ["expanded_url": "https://example.com/article"],
                    ]
                )
            ])
        ])

        let result = try GraphQLResponseParser.parse(json)
        let links = result.records[0].links ?? []
        #expect(links.count == 2)
        #expect(links.contains("https://github.com/apple/swift"))
        #expect(links.contains("https://example.com/article"))
        #expect(!links.contains("https://t.co/abc123"))
    }

    // MARK: - sortIndex → bookmarkedAt

    @Test func sortIndexToBookmarkedAt() throws {
        let json = makeResponse(instructions: [
            makeAddEntriesInstruction(entries: [
                makeTweetEntry(
                    sortIndex: "1867614419191283712",
                    tweetId: "400"
                )
            ])
        ])

        let result = try GraphQLResponseParser.parse(json)
        #expect(result.records[0].bookmarkedAt != nil)
        #expect(result.records[0].bookmarkedAt!.hasPrefix("2024-12-13"))
    }

    // MARK: - Multiple Entries

    @Test func multipleEntries() throws {
        let json = makeResponse(instructions: [
            makeAddEntriesInstruction(entries: [
                makeTweetEntry(tweetId: "1", fullText: "First"),
                makeTweetEntry(tweetId: "2", fullText: "Second"),
                makeTweetEntry(tweetId: "3", fullText: "Third"),
                makeCursorEntry(cursor: "next_cursor_value")
            ])
        ])

        let result = try GraphQLResponseParser.parse(json)
        #expect(result.records.count == 3)
        #expect(result.nextCursor == "next_cursor_value")
    }

    // MARK: - TweetWithVisibilityResults

    @Test func tweetWithVisibilityResultsExtraNesting() throws {
        // Sometimes result.__typename is "TweetWithVisibilityResults"
        // and the actual tweet is at result.tweet
        let entry: [String: Any] = [
            "entryId": "tweet-500",
            "sortIndex": "1867614419191283712",
            "content": [
                "entryType": "TimelineTimelineItem",
                "itemContent": [
                    "tweet_results": [
                        "result": [
                            "__typename": "TweetWithVisibilityResults",
                            "tweet": [
                                "rest_id": "500",
                                "legacy": [
                                    "id_str": "500",
                                    "full_text": "Visibility wrapped tweet",
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
                                                "screen_name": "visuser",
                                                "name": "Visible User",
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
        ]

        let json = makeResponse(instructions: [
            makeAddEntriesInstruction(entries: [entry])
        ])

        let result = try GraphQLResponseParser.parse(json)
        #expect(result.records.count == 1)
        #expect(result.records[0].tweetId == "500")
        #expect(result.records[0].authorHandle == "visuser")
    }

    // MARK: - Quoted Tweet

    @Test func parseQuotedTweet() throws {
        let quotedTweetData: [String: Any] = [
            "__typename": "Tweet",
            "rest_id": "999",
            "legacy": [
                "id_str": "999",
                "full_text": "I am the quoted tweet",
                "favorite_count": 5,
                "retweet_count": 1,
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
                            "screen_name": "quoteduser",
                            "name": "Quoted User",
                        ],
                        "avatar": [
                            "image_url": "https://qt.jpg"
                        ]
                    ]
                ]
            ],
            "views": ["count": "50"]
        ]

        let json = makeResponse(instructions: [
            makeAddEntriesInstruction(entries: [
                makeTweetEntry(
                    tweetId: "600",
                    fullText: "Check this quote tweet",
                    quotedTweet: quotedTweetData
                )
            ])
        ])

        let result = try GraphQLResponseParser.parse(json)
        let qt = result.records[0].quotedTweet
        #expect(qt != nil)
        #expect(qt?.id == "999")
        #expect(qt?.text == "I am the quoted tweet")
        #expect(qt?.authorHandle == "quoteduser")
    }
}
