import Foundation

public struct GraphQLParseResult: Sendable {
    public let records: [BookmarkRecord]
    public let nextCursor: String?
}

public enum GraphQLResponseParser {

    public static func parse(_ json: [String: Any]) throws -> GraphQLParseResult {
        guard
            let data = json["data"] as? [String: Any],
            let timeline = data["bookmark_timeline_v2"] as? [String: Any],
            let tl = timeline["timeline"] as? [String: Any],
            let instructions = tl["instructions"] as? [[String: Any]]
        else {
            return GraphQLParseResult(records: [], nextCursor: nil)
        }

        var records: [BookmarkRecord] = []
        var nextCursor: String?

        for instruction in instructions {
            guard
                let type = instruction["type"] as? String,
                type == "TimelineAddEntries",
                let entries = instruction["entries"] as? [[String: Any]]
            else { continue }

            for entry in entries {
                let entryId = entry["entryId"] as? String ?? ""

                // Cursor entry
                if entryId.hasPrefix("cursor-bottom") {
                    if let content = entry["content"] as? [String: Any],
                       let value = content["value"] as? String {
                        nextCursor = value
                    }
                    continue
                }

                // Tweet entry
                guard
                    let content = entry["content"] as? [String: Any],
                    let itemContent = content["itemContent"] as? [String: Any],
                    let tweetResults = itemContent["tweet_results"] as? [String: Any],
                    let result = tweetResults["result"] as? [String: Any]
                else { continue }

                // Handle TweetWithVisibilityResults or direct Tweet
                let tweetObj = result["tweet"] as? [String: Any] ?? result

                let sortIndex = entry["sortIndex"] as? String
                if let record = convertTweetToRecord(tweetObj, sortIndex: sortIndex) {
                    records.append(record)
                }
            }
        }

        return GraphQLParseResult(records: records, nextCursor: nextCursor)
    }

    public static func parse(data: Data) throws -> GraphQLParseResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return GraphQLParseResult(records: [], nextCursor: nil)
        }
        return try parse(json)
    }

    // MARK: - Convert Tweet to Record

    static func convertTweetToRecord(_ tweetObj: [String: Any], sortIndex: String?) -> BookmarkRecord? {
        guard let legacy = tweetObj["legacy"] as? [String: Any] else { return nil }

        let tweetId = tweetObj["rest_id"] as? String
            ?? legacy["id_str"] as? String
            ?? ""
        guard !tweetId.isEmpty else { return nil }

        // Text: prefer note_tweet (long-form) over legacy.full_text
        let text: String
        if let noteTweet = tweetObj["note_tweet"] as? [String: Any],
           let noteResults = noteTweet["note_tweet_results"] as? [String: Any],
           let noteResult = noteResults["result"] as? [String: Any],
           let noteText = noteResult["text"] as? String {
            text = noteText
        } else {
            text = legacy["full_text"] as? String ?? legacy["text"] as? String ?? ""
        }

        // Author — X API moved screen_name/name to user.core, avatar to user.avatar
        var authorHandle: String?
        var authorName: String?
        var authorProfileImageUrl: String?
        if let core = tweetObj["core"] as? [String: Any],
           let userResults = core["user_results"] as? [String: Any],
           let userResult = userResults["result"] as? [String: Any] {
            // New location: user_results.result.core
            if let userCore = userResult["core"] as? [String: Any] {
                authorHandle = userCore["screen_name"] as? String
                authorName = userCore["name"] as? String
            }
            // Fallback: legacy location
            if authorHandle == nil, let userLegacy = userResult["legacy"] as? [String: Any] {
                authorHandle = userLegacy["screen_name"] as? String
                authorName = userLegacy["name"] as? String
                authorProfileImageUrl = userLegacy["profile_image_url_https"] as? String
            }
            // New avatar location
            if authorProfileImageUrl == nil, let avatar = userResult["avatar"] as? [String: Any] {
                authorProfileImageUrl = avatar["image_url"] as? String
            }
        }

        // Posted at — parse Twitter date format from legacy.created_at
        let postedAt: String? = (legacy["created_at"] as? String).flatMap { parseTwitterDate($0) }

        // Engagement
        let engagement = BookmarkEngagement(
            likeCount: legacy["favorite_count"] as? Int,
            repostCount: legacy["retweet_count"] as? Int,
            replyCount: legacy["reply_count"] as? Int,
            quoteCount: legacy["quote_count"] as? Int,
            bookmarkCount: legacy["bookmark_count"] as? Int,
            viewCount: (tweetObj["views"] as? [String: Any])?["count"].flatMap { v -> Int? in
                if let s = v as? String { return Int(s) }
                if let i = v as? Int { return i }
                return nil
            }
        )

        // Media
        let mediaObjects = parseMedia(legacy)
        let mediaUrls = mediaObjects.compactMap(\.mediaUrl)

        // Links (exclude t.co)
        var links: [String] = []
        if let entities = legacy["entities"] as? [String: Any],
           let urls = entities["urls"] as? [[String: Any]] {
            for urlObj in urls {
                if let expanded = urlObj["expanded_url"] as? String,
                   !expanded.hasPrefix("https://t.co/"),
                   !expanded.hasPrefix("http://t.co/") {
                    links.append(expanded)
                }
            }
        }

        // Language
        let language = legacy["lang"] as? String

        // Bookmarked at (from sortIndex snowflake)
        let bookmarkedAt = sortIndex.flatMap { SnowflakeTimestamp.toISO($0) }

        // Quoted tweet
        var quotedTweet: QuotedTweetSnapshot?
        if let qtResult = tweetObj["quoted_status_result"] as? [String: Any],
           let qtData = qtResult["result"] as? [String: Any] {
            let qtObj = qtData["tweet"] as? [String: Any] ?? qtData
            quotedTweet = convertToQuotedTweet(qtObj)
        }

        let url = "https://x.com/\(authorHandle ?? "i")/status/\(tweetId)"

        let now = ISO8601DateFormatter().string(from: Date())

        return BookmarkRecord(
            id: tweetId,
            tweetId: tweetId,
            authorHandle: authorHandle,
            authorName: authorName,
            authorProfileImageUrl: authorProfileImageUrl,
            url: url,
            text: text,
            postedAt: postedAt,
            bookmarkedAt: bookmarkedAt,
            syncedAt: now,
            quotedStatusId: quotedTweet?.id,
            quotedTweet: quotedTweet,
            language: language,
            engagement: engagement,
            media: mediaUrls.isEmpty ? nil : mediaUrls,
            mediaObjects: mediaObjects.isEmpty ? nil : mediaObjects,
            links: links.isEmpty ? nil : links,
            ingestedVia: "graphql"
        )
    }

    // MARK: - Twitter Date Parsing

    /// Parse Twitter date format "Wed Oct 10 20:19:24 +0000 2018" → ISO 8601
    static func parseTwitterDate(_ dateStr: String) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        guard let date = formatter.date(from: dateStr) else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.string(from: date)
    }

    // MARK: - Media Parsing

    private static func parseMedia(_ legacy: [String: Any]) -> [BookmarkMediaObject] {
        let mediaArray: [[String: Any]]
        if let extEntities = legacy["extended_entities"] as? [String: Any],
           let media = extEntities["media"] as? [[String: Any]] {
            mediaArray = media
        } else if let entities = legacy["entities"] as? [String: Any],
                  let media = entities["media"] as? [[String: Any]] {
            mediaArray = media
        } else {
            return []
        }

        return mediaArray.map { item in
            let type = item["type"] as? String
            let url = item["media_url_https"] as? String ?? item["media_url"] as? String
            let altText = item["ext_alt_text"] as? String

            var width: Int?
            var height: Int?
            if let originalInfo = item["original_info"] as? [String: Any] {
                width = originalInfo["width"] as? Int
                height = originalInfo["height"] as? Int
            }

            var variants: [BookmarkMediaVariant]?
            if let videoInfo = item["video_info"] as? [String: Any],
               let rawVariants = videoInfo["variants"] as? [[String: Any]] {
                variants = rawVariants
                    .filter { ($0["content_type"] as? String) == "video/mp4" }
                    .sorted { ($0["bitrate"] as? Int ?? 0) > ($1["bitrate"] as? Int ?? 0) }
                    .map { v in
                        BookmarkMediaVariant(
                            url: v["url"] as? String,
                            contentType: v["content_type"] as? String,
                            bitrate: v["bitrate"] as? Int
                        )
                    }
            }

            return BookmarkMediaObject(
                mediaUrl: url,
                type: type,
                extAltText: altText,
                width: width,
                height: height,
                variants: variants
            )
        }
    }

    // MARK: - Quoted Tweet

    private static func convertToQuotedTweet(_ tweetObj: [String: Any]) -> QuotedTweetSnapshot? {
        guard let legacy = tweetObj["legacy"] as? [String: Any] else { return nil }

        let id = tweetObj["rest_id"] as? String ?? legacy["id_str"] as? String ?? ""
        guard !id.isEmpty else { return nil }

        let text = legacy["full_text"] as? String ?? legacy["text"] as? String ?? ""

        var authorHandle: String?
        var authorName: String?
        var authorProfileImageUrl: String?
        if let core = tweetObj["core"] as? [String: Any],
           let userResults = core["user_results"] as? [String: Any],
           let userResult = userResults["result"] as? [String: Any] {
            if let userCore = userResult["core"] as? [String: Any] {
                authorHandle = userCore["screen_name"] as? String
                authorName = userCore["name"] as? String
            }
            if authorHandle == nil, let userLegacy = userResult["legacy"] as? [String: Any] {
                authorHandle = userLegacy["screen_name"] as? String
                authorName = userLegacy["name"] as? String
                authorProfileImageUrl = userLegacy["profile_image_url_https"] as? String
            }
            if authorProfileImageUrl == nil, let avatar = userResult["avatar"] as? [String: Any] {
                authorProfileImageUrl = avatar["image_url"] as? String
            }
        }

        let mediaObjects = parseMedia(legacy)
        let mediaUrls = mediaObjects.compactMap(\.mediaUrl)

        let url = "https://x.com/\(authorHandle ?? "i")/status/\(id)"

        return QuotedTweetSnapshot(
            id: id,
            text: text,
            authorHandle: authorHandle,
            authorName: authorName,
            authorProfileImageUrl: authorProfileImageUrl,
            media: mediaUrls.isEmpty ? nil : mediaUrls,
            mediaObjects: mediaObjects.isEmpty ? nil : mediaObjects,
            url: url
        )
    }
}
