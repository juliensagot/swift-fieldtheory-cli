import Foundation

public struct BookmarkCacheMeta: Codable, Equatable, Sendable {
    public var provider: String = "twitter"
    public var schemaVersion: Int
    public var lastFullSyncAt: String?
    public var lastIncrementalSyncAt: String?
    public var totalBookmarks: Int

    public init(
        schemaVersion: Int,
        lastFullSyncAt: String? = nil,
        lastIncrementalSyncAt: String? = nil,
        totalBookmarks: Int
    ) {
        self.schemaVersion = schemaVersion
        self.lastFullSyncAt = lastFullSyncAt
        self.lastIncrementalSyncAt = lastIncrementalSyncAt
        self.totalBookmarks = totalBookmarks
    }
}

public struct BookmarkBackfillState: Codable, Equatable, Sendable {
    public var provider: String = "twitter"
    public var lastRunAt: String?
    public var totalRuns: Int
    public var totalAdded: Int
    public var lastAdded: Int
    public var lastSeenIds: [String]
    public var stopReason: String?

    public init(
        lastRunAt: String? = nil,
        totalRuns: Int,
        totalAdded: Int,
        lastAdded: Int,
        lastSeenIds: [String] = [],
        stopReason: String? = nil
    ) {
        self.lastRunAt = lastRunAt
        self.totalRuns = totalRuns
        self.totalAdded = totalAdded
        self.lastAdded = lastAdded
        self.lastSeenIds = lastSeenIds
        self.stopReason = stopReason
    }
}
