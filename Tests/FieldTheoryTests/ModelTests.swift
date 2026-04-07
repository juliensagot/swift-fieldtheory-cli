import Testing
import Foundation
@testable import FieldTheory

@Suite("Models")
struct ModelTests {

    // MARK: - BookmarkRecord

    @Test func bookmarkRecordCodableRoundTrip() throws {
        let record = BookmarkRecord(
            id: "1234567890123456789",
            tweetId: "1234567890123456789",
            url: "https://x.com/user/status/1234567890123456789",
            text: "Hello world",
            syncedAt: "2024-01-15T10:30:00Z"
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(BookmarkRecord.self, from: data)
        #expect(decoded == record)
    }

    @Test func bookmarkRecordWithAllFields() throws {
        let record = BookmarkRecord(
            id: "123",
            tweetId: "123",
            authorHandle: "swiftdev",
            authorName: "Swift Dev",
            authorProfileImageUrl: "https://pbs.twimg.com/photo.jpg",
            author: BookmarkAuthor(
                handle: "swiftdev",
                name: "Swift Dev",
                profileImageUrl: "https://pbs.twimg.com/photo.jpg",
                description: "iOS developer",
                location: "San Francisco",
                url: "https://example.com",
                verified: true,
                followersCount: 1000,
                followingCount: 500,
                statusesCount: 2000
            ),
            url: "https://x.com/swiftdev/status/123",
            text: "Check out this repo https://github.com/apple/swift",
            postedAt: "2024-01-15T10:00:00Z",
            bookmarkedAt: "2024-01-15T12:00:00Z",
            syncedAt: "2024-01-15T14:00:00Z",
            conversationId: "100",
            inReplyToStatusId: "99",
            inReplyToUserId: "50",
            quotedStatusId: "80",
            quotedTweet: QuotedTweetSnapshot(
                id: "80",
                text: "Original tweet",
                authorHandle: "other",
                authorName: "Other User",
                authorProfileImageUrl: nil,
                postedAt: "2024-01-14T09:00:00Z",
                media: ["https://pbs.twimg.com/media/img.jpg"],
                mediaObjects: nil,
                url: "https://x.com/other/status/80"
            ),
            language: "en",
            sourceApp: "Twitter for iPhone",
            possiblySensitive: false,
            engagement: BookmarkEngagement(
                likeCount: 42,
                repostCount: 10,
                replyCount: 5,
                quoteCount: 3,
                bookmarkCount: 7,
                viewCount: 10000
            ),
            media: ["https://pbs.twimg.com/media/photo.jpg"],
            mediaObjects: [
                BookmarkMediaObject(
                    mediaUrl: "https://pbs.twimg.com/media/photo.jpg",
                    previewUrl: "https://pbs.twimg.com/media/photo_small.jpg",
                    type: "photo",
                    extAltText: "A screenshot",
                    width: 1920,
                    height: 1080,
                    variants: nil
                )
            ],
            links: ["https://github.com/apple/swift"],
            tags: ["swift", "open-source"],
            ingestedVia: "graphql"
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(BookmarkRecord.self, from: data)
        #expect(decoded == record)
    }

    // MARK: - BookmarkMediaObject

    @Test func mediaObjectWithVideoVariants() throws {
        let media = BookmarkMediaObject(
            mediaUrl: "https://video.twimg.com/video.mp4",
            previewUrl: "https://pbs.twimg.com/thumb.jpg",
            type: "video",
            extAltText: nil,
            width: 1280,
            height: 720,
            variants: [
                BookmarkMediaVariant(url: "https://video.twimg.com/720.mp4", contentType: "video/mp4", bitrate: 2176000),
                BookmarkMediaVariant(url: "https://video.twimg.com/480.mp4", contentType: "video/mp4", bitrate: 950000),
                BookmarkMediaVariant(url: "https://video.twimg.com/360.mp4", contentType: "video/mp4", bitrate: 632000),
            ]
        )

        let data = try JSONEncoder().encode(media)
        let decoded = try JSONDecoder().decode(BookmarkMediaObject.self, from: data)
        #expect(decoded == media)
        #expect(decoded.variants?.count == 3)
        #expect(decoded.variants?[0].bitrate == 2176000)
    }

    @Test func mediaObjectAnimatedGif() throws {
        let media = BookmarkMediaObject(
            mediaUrl: "https://video.twimg.com/tweet_video/gif.mp4",
            previewUrl: nil,
            type: "animated_gif",
            extAltText: nil,
            width: 320,
            height: 240,
            variants: [
                BookmarkMediaVariant(url: "https://video.twimg.com/tweet_video/gif.mp4", contentType: "video/mp4", bitrate: 0)
            ]
        )

        let data = try JSONEncoder().encode(media)
        let decoded = try JSONDecoder().decode(BookmarkMediaObject.self, from: data)
        #expect(decoded == media)
        #expect(decoded.type == "animated_gif")
    }

    // MARK: - QuotedTweetSnapshot

    @Test func quotedTweetRoundTrip() throws {
        let qt = QuotedTweetSnapshot(
            id: "999",
            text: "This is the quoted tweet",
            authorHandle: "quoteduser",
            authorName: "Quoted User",
            authorProfileImageUrl: "https://pbs.twimg.com/qt.jpg",
            postedAt: "2024-01-10T08:00:00Z",
            media: ["https://pbs.twimg.com/media/qt_img.jpg"],
            mediaObjects: [
                BookmarkMediaObject(
                    mediaUrl: "https://pbs.twimg.com/media/qt_img.jpg",
                    previewUrl: nil,
                    type: "photo",
                    extAltText: nil,
                    width: 800,
                    height: 600,
                    variants: nil
                )
            ],
            url: "https://x.com/quoteduser/status/999"
        )

        let data = try JSONEncoder().encode(qt)
        let decoded = try JSONDecoder().decode(QuotedTweetSnapshot.self, from: data)
        #expect(decoded == qt)
    }

    @Test func quotedTweetNilPostedAt() throws {
        let qt = QuotedTweetSnapshot(
            id: "999",
            text: "No date",
            url: "https://x.com/user/status/999"
        )

        let data = try JSONEncoder().encode(qt)
        let decoded = try JSONDecoder().decode(QuotedTweetSnapshot.self, from: data)
        #expect(decoded.postedAt == nil)
    }

    // MARK: - BookmarkEngagement

    @Test func engagementAllOptional() throws {
        let empty = BookmarkEngagement()
        let data = try JSONEncoder().encode(empty)
        let decoded = try JSONDecoder().decode(BookmarkEngagement.self, from: data)
        #expect(decoded.likeCount == nil)
        #expect(decoded.viewCount == nil)
    }

    @Test func engagementPartialFields() throws {
        let partial = BookmarkEngagement(likeCount: 100, viewCount: 50000)
        let data = try JSONEncoder().encode(partial)
        let decoded = try JSONDecoder().decode(BookmarkEngagement.self, from: data)
        #expect(decoded.likeCount == 100)
        #expect(decoded.repostCount == nil)
        #expect(decoded.viewCount == 50000)
    }

    // MARK: - Snowflake ID

    @Test func snowflakeIdAsString() throws {
        let record = BookmarkRecord(
            id: "1867614419191283712",
            tweetId: "1867614419191283712",
            url: "https://x.com/user/status/1867614419191283712",
            text: "Large snowflake ID",
            syncedAt: "2024-12-13T12:00:00Z"
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(BookmarkRecord.self, from: data)
        #expect(decoded.id == "1867614419191283712")
        #expect(decoded.tweetId == "1867614419191283712")
    }

    // MARK: - BookmarkAuthor

    @Test func authorRoundTrip() throws {
        let author = BookmarkAuthor(
            handle: "dev",
            name: "Developer",
            profileImageUrl: "https://example.com/pic.jpg",
            description: "Building things",
            location: "NYC",
            url: "https://example.com",
            verified: true,
            followersCount: 5000,
            followingCount: 200,
            statusesCount: 10000
        )

        let data = try JSONEncoder().encode(author)
        let decoded = try JSONDecoder().decode(BookmarkAuthor.self, from: data)
        #expect(decoded == author)
    }

    // MARK: - SyncState models

    @Test func backfillStateRoundTrip() throws {
        let state = BookmarkBackfillState(
            lastRunAt: "2024-01-15T10:00:00Z",
            totalRuns: 5,
            totalAdded: 1200,
            lastAdded: 50,
            lastSeenIds: ["123", "456", "789"],
            stopReason: "caught up to newest stored bookmark"
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BookmarkBackfillState.self, from: data)
        #expect(decoded == state)
    }

    @Test func cacheMetaRoundTrip() throws {
        let meta = BookmarkCacheMeta(
            schemaVersion: 5,
            lastFullSyncAt: "2024-01-15T10:00:00Z",
            lastIncrementalSyncAt: "2024-01-16T10:00:00Z",
            totalBookmarks: 3500
        )

        let data = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(BookmarkCacheMeta.self, from: data)
        #expect(decoded == meta)
    }
}
