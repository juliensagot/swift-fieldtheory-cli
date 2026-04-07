import Foundation

public struct BookmarkEngagement: Codable, Equatable, Sendable {
    public var likeCount: Int?
    public var repostCount: Int?
    public var replyCount: Int?
    public var quoteCount: Int?
    public var bookmarkCount: Int?
    public var viewCount: Int?

    public init(
        likeCount: Int? = nil,
        repostCount: Int? = nil,
        replyCount: Int? = nil,
        quoteCount: Int? = nil,
        bookmarkCount: Int? = nil,
        viewCount: Int? = nil
    ) {
        self.likeCount = likeCount
        self.repostCount = repostCount
        self.replyCount = replyCount
        self.quoteCount = quoteCount
        self.bookmarkCount = bookmarkCount
        self.viewCount = viewCount
    }
}
