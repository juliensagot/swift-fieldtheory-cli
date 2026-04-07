import Foundation

public struct BookmarkRecord: Codable, Equatable, Sendable {
    public var id: String
    public var tweetId: String
    public var authorHandle: String?
    public var authorName: String?
    public var authorProfileImageUrl: String?
    public var author: BookmarkAuthor?
    public var url: String
    public var text: String
    public var postedAt: String?
    public var bookmarkedAt: String?
    public var syncedAt: String
    public var conversationId: String?
    public var inReplyToStatusId: String?
    public var inReplyToUserId: String?
    public var quotedStatusId: String?
    public var quotedTweet: QuotedTweetSnapshot?
    public var language: String?
    public var sourceApp: String?
    public var possiblySensitive: Bool?
    public var engagement: BookmarkEngagement?
    public var media: [String]?
    public var mediaObjects: [BookmarkMediaObject]?
    public var links: [String]?
    public var tags: [String]?
    public var ingestedVia: String?
    public var categories: String?
    public var primaryCategory: String?
    public var githubUrls: String?
    public var domains: String?
    public var primaryDomain: String?

    public init(
        id: String,
        tweetId: String,
        authorHandle: String? = nil,
        authorName: String? = nil,
        authorProfileImageUrl: String? = nil,
        author: BookmarkAuthor? = nil,
        url: String,
        text: String,
        postedAt: String? = nil,
        bookmarkedAt: String? = nil,
        syncedAt: String,
        conversationId: String? = nil,
        inReplyToStatusId: String? = nil,
        inReplyToUserId: String? = nil,
        quotedStatusId: String? = nil,
        quotedTweet: QuotedTweetSnapshot? = nil,
        language: String? = nil,
        sourceApp: String? = nil,
        possiblySensitive: Bool? = nil,
        engagement: BookmarkEngagement? = nil,
        media: [String]? = nil,
        mediaObjects: [BookmarkMediaObject]? = nil,
        links: [String]? = nil,
        tags: [String]? = nil,
        ingestedVia: String? = nil,
        categories: String? = nil,
        primaryCategory: String? = nil,
        githubUrls: String? = nil,
        domains: String? = nil,
        primaryDomain: String? = nil
    ) {
        self.id = id
        self.tweetId = tweetId
        self.authorHandle = authorHandle
        self.authorName = authorName
        self.authorProfileImageUrl = authorProfileImageUrl
        self.author = author
        self.url = url
        self.text = text
        self.postedAt = postedAt
        self.bookmarkedAt = bookmarkedAt
        self.syncedAt = syncedAt
        self.conversationId = conversationId
        self.inReplyToStatusId = inReplyToStatusId
        self.inReplyToUserId = inReplyToUserId
        self.quotedStatusId = quotedStatusId
        self.quotedTweet = quotedTweet
        self.language = language
        self.sourceApp = sourceApp
        self.possiblySensitive = possiblySensitive
        self.engagement = engagement
        self.media = media
        self.mediaObjects = mediaObjects
        self.links = links
        self.tags = tags
        self.ingestedVia = ingestedVia
        self.categories = categories
        self.primaryCategory = primaryCategory
        self.githubUrls = githubUrls
        self.domains = domains
        self.primaryDomain = primaryDomain
    }
}
