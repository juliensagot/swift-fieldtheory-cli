import Foundation

public enum SnowflakeTimestamp {
    /// Twitter snowflake epoch: Nov 4, 2010 01:42:54.657 UTC (milliseconds)
    private static let twitterEpoch: UInt64 = 1_288_834_974_657

    /// Convert a Twitter snowflake ID string to an ISO 8601 timestamp.
    public static func toISO(_ snowflakeId: String) -> String? {
        guard !snowflakeId.isEmpty, let id = UInt64(snowflakeId) else {
            return nil
        }
        let timestampMs = (id >> 22) + twitterEpoch
        let date = Date(timeIntervalSince1970: Double(timestampMs) / 1000.0)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
