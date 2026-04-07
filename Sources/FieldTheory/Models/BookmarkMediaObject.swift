import Foundation

public struct BookmarkMediaVariant: Codable, Equatable, Sendable {
    public var url: String?
    public var contentType: String?
    public var bitrate: Int?

    public init(url: String? = nil, contentType: String? = nil, bitrate: Int? = nil) {
        self.url = url
        self.contentType = contentType
        self.bitrate = bitrate
    }
}

public struct BookmarkMediaObject: Codable, Equatable, Sendable {
    public var mediaUrl: String?
    public var previewUrl: String?
    public var type: String?
    public var extAltText: String?
    public var width: Int?
    public var height: Int?
    public var variants: [BookmarkMediaVariant]?

    public init(
        mediaUrl: String? = nil,
        previewUrl: String? = nil,
        type: String? = nil,
        extAltText: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        variants: [BookmarkMediaVariant]? = nil
    ) {
        self.mediaUrl = mediaUrl
        self.previewUrl = previewUrl
        self.type = type
        self.extAltText = extAltText
        self.width = width
        self.height = height
        self.variants = variants
    }
}
