import Foundation

public struct QuotedTweetSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var authorHandle: String?
    public var authorName: String?
    public var authorProfileImageUrl: String?
    public var postedAt: String?
    public var media: [String]?
    public var mediaObjects: [BookmarkMediaObject]?
    public var url: String

    public init(
        id: String,
        text: String,
        authorHandle: String? = nil,
        authorName: String? = nil,
        authorProfileImageUrl: String? = nil,
        postedAt: String? = nil,
        media: [String]? = nil,
        mediaObjects: [BookmarkMediaObject]? = nil,
        url: String
    ) {
        self.id = id
        self.text = text
        self.authorHandle = authorHandle
        self.authorName = authorName
        self.authorProfileImageUrl = authorProfileImageUrl
        self.postedAt = postedAt
        self.media = media
        self.mediaObjects = mediaObjects
        self.url = url
    }
}
