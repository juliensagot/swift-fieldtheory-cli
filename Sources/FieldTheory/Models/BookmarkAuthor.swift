import Foundation

public struct BookmarkAuthor: Codable, Equatable, Sendable {
    public var handle: String?
    public var name: String?
    public var profileImageUrl: String?
    public var description: String?
    public var location: String?
    public var url: String?
    public var verified: Bool?
    public var followersCount: Int?
    public var followingCount: Int?
    public var statusesCount: Int?

    public init(
        handle: String? = nil,
        name: String? = nil,
        profileImageUrl: String? = nil,
        description: String? = nil,
        location: String? = nil,
        url: String? = nil,
        verified: Bool? = nil,
        followersCount: Int? = nil,
        followingCount: Int? = nil,
        statusesCount: Int? = nil
    ) {
        self.handle = handle
        self.name = name
        self.profileImageUrl = profileImageUrl
        self.description = description
        self.location = location
        self.url = url
        self.verified = verified
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.statusesCount = statusesCount
    }
}
