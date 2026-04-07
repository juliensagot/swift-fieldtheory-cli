import Foundation

public struct ClassifyResult: Sendable {
    public let categories: [String]
    public let primary: String
    public let githubUrls: [String]
}

public struct ClassifySummary: Sendable {
    public let total: Int
    public let categoryCounts: [String: Int]
    public let unclassifiedCount: Int
}

public enum Classifier {

    // MARK: - Pattern Sets

    private static let toolPatterns: [NSRegularExpression] = compile([
        #"github\.com/[\w-]+/[\w-]+"#,
        #"\bnpm\s+(install|i)\b"#,
        #"\bpip\s+install\b"#,
        #"\bcargo\s+add\b"#,
        #"\bbrew\s+install\b"#,
        #"\bopen[\s-]?source\b"#,
        #"\bcli\b.*\btool\b"#,
        #"\btool\b.*\bcli\b"#,
        #"\brust\s+crate\b"#,
        #"\bvscode\s+extension\b"#,
        #"\bnpx\s+"#,
        #"\brepo\b.*\bgithub\b"#,
        #"\bgithub\b.*\brepo\b"#,
        #"\bself[\s-]?hosted\b"#,
        #"\bopen[\s-]?sourced?\b"#,
    ])

    private static let securityPatterns: [NSRegularExpression] = compile([
        #"\bcve[-\s]?\d{4}"#,
        #"\bvulnerabilit"#,
        #"\bexploit"#,
        #"\bmalware\b"#,
        #"\bransomware\b"#,
        #"\bsupply[\s-]?chain\s+attack"#,
        #"\bsecurity\s+(flaw|bug|issue|patch|advisory|update|breach)"#,
        #"\bbreach\b"#,
        #"\bbackdoor\b"#,
        #"\bzero[\s-]?day\b"#,
        #"\bremote\s+code\s+execution\b"#,
        #"\brce\b"#,
        #"\bprivilege\s+escalation\b"#,
        #"\bcompromised?\b"#,
    ])

    private static let techniquePatterns: [NSRegularExpression] = compile([
        #"\bhow\s+(I|we|to)\b"#,
        #"\btutorial\b"#,
        #"\bwalkthrough\b"#,
        #"\bstep[\s-]?by[\s-]?step\b"#,
        #"\bbuilt\s+(with|using|this|a|an|my)\b"#,
        #"\bhere'?s?\s+how\b"#,
        #"\bcode\s+(pattern|example|snippet|sample)\b"#,
        #"\barchitecture\b.*\b(of|for|behind)\b"#,
        #"\bimplemented?\b.*\bfrom\s+scratch\b"#,
        #"\bunder\s+the\s+hood\b"#,
        #"\bdeep[\s-]?dive\b"#,
        #"\btechnique\b"#,
        #"\bpattern\b.*\b(for|in|to)\b"#,
    ])

    private static let launchPatterns: [NSRegularExpression] = compile([
        #"\bjust\s+(launched|shipped|released|dropped|published)\b"#,
        #"\bwe('re|\s+are)\s+(launching|shipping|releasing)\b"#,
        #"\bannouncing\b"#,
        #"\bintroduc(ing|es?)\b"#,
        #"\bnow\s+(available|live|in\s+beta)\b"#,
        #"\bv\d+\.\d+"#,
        #"\b(alpha|beta)\s+(release|launch|is\s+here)\b"#,
        #"\bproduct\s+hunt\b"#,
        #"🚀.*\b(launch|ship|live)\b"#,
        #"\bcheck\s+it\s+out\b"#,
    ])

    private static let researchPatterns: [NSRegularExpression] = compile([
        #"arxiv\.org"#,
        #"\bpaper\b.*\b(new|our|this|the)\b"#,
        #"\b(new|our|this)\b.*\bpaper\b"#,
        #"\bstudy\b.*\b(finds?|shows?|reveals?)\b"#,
        #"\bfindings?\b"#,
        #"\bpeer[\s-]?review"#,
        #"\bpreprint\b"#,
        #"\bresearch\b.*\b(from|by|at|shows?)\b"#,
        #"\bpublished\s+in\b"#,
        #"\bjournal\b"#,
        #"\bstate[\s-]?of[\s-]?the[\s-]?art\b"#,
    ])

    private static let opinionPatterns: [NSRegularExpression] = compile([
        #"\bthread\b.*👇"#,
        #"\bunpopular\s+opinion\b"#,
        #"\bhot\s+take\b"#,
        #"\bhere'?s?\s+(why|what|my\s+take)\b"#,
        #"\bi\s+think\b.*\b(about|that)\b"#,
        #"\bcontroversial\b"#,
        #"\boverrated\b"#,
        #"\bunderrated\b"#,
        #"\blessons?\s+(learned|from)\b"#,
        #"\bmistakes?\s+(I|we)\b"#,
    ])

    private static let commercePatterns: [NSRegularExpression] = compile([
        #"\bamazon\.com\b"#,
        #"\bshop\s+(here|now)\b"#,
        #"\bbuy\s+(now|here|this)\b"#,
        #"\bdiscount\b"#,
        #"\bcoupon\b"#,
        #"\baffiliate\b"#,
        #"\bgeni\.us\b"#,
        #"\ba\.co/"#,
        #"\$\d+(\.\d{2})?\s*(off|USD|discount)"#,
    ])

    private static let githubUrlRegex = try! NSRegularExpression(pattern: #"github\.com/[\w.-]+/[\w.-]+"#, options: [.caseInsensitive])

    // MARK: - Domain Sets

    private static let toolDomains: Set<String> = [
        "github.com", "gitlab.com", "huggingface.co",
        "npmjs.com", "pypi.org", "crates.io", "pkg.go.dev"
    ]
    private static let researchDomains: Set<String> = [
        "arxiv.org", "scholar.google.com", "semanticscholar.org",
        "biorxiv.org", "medrxiv.org", "nature.com", "science.org"
    ]
    private static let commerceDomains: Set<String> = [
        "amazon.com", "www.amazon.com", "a.co",
        "store.steampowered.com", "geni.us", "ebay.com"
    ]

    // MARK: - Classify

    public static func classify(_ record: BookmarkRecord) -> ClassifyResult {
        let text = record.text
        var categories: [String] = []

        // Pattern matching
        let categoryChecks: [(String, [NSRegularExpression])] = [
            ("tool", toolPatterns),
            ("security", securityPatterns),
            ("technique", techniquePatterns),
            ("launch", launchPatterns),
            ("research", researchPatterns),
            ("opinion", opinionPatterns),
            ("commerce", commercePatterns),
        ]

        for (name, patterns) in categoryChecks {
            if matchesAny(text, patterns: patterns) {
                categories.append(name)
            }
        }

        // Domain-based detection from links
        let allLinks = (record.links ?? []) + extractUrls(from: text)
        for link in allLinks {
            if let host = extractHost(from: link) {
                if toolDomains.contains(host) && !categories.contains("tool") {
                    categories.append("tool")
                }
                if researchDomains.contains(host) && !categories.contains("research") {
                    categories.append("research")
                }
                if commerceDomains.contains(host) && !categories.contains("commerce") {
                    categories.append("commerce")
                }
            }
        }

        // GitHub URL extraction
        let githubUrls = extractGithubUrls(from: text)

        let primary = categories.first ?? "unclassified"

        return ClassifyResult(
            categories: categories,
            primary: primary,
            githubUrls: githubUrls
        )
    }

    // MARK: - Batch

    public static func classifyCorpus(_ records: [BookmarkRecord]) -> ClassifySummary {
        var categoryCounts: [String: Int] = [:]
        var unclassified = 0

        for record in records {
            let result = classify(record)
            if result.categories.isEmpty {
                unclassified += 1
            }
            for cat in result.categories {
                categoryCounts[cat, default: 0] += 1
            }
        }

        return ClassifySummary(
            total: records.count,
            categoryCounts: categoryCounts,
            unclassifiedCount: unclassified
        )
    }

    // MARK: - Helpers

    private static func compile(_ patterns: [String]) -> [NSRegularExpression] {
        patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }

    private static func matchesAny(_ text: String, patterns: [NSRegularExpression]) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return patterns.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    private static func extractGithubUrls(from text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        let matches = githubUrlRegex.matches(in: text, range: range)
        return matches.compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r])
        }
    }

    private static func extractUrls(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s)>\]]+"#, options: []) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            let url = String(text[r])
            // Exclude t.co
            if url.hasPrefix("https://t.co/") || url.hasPrefix("http://t.co/") { return nil }
            return url
        }
    }

    private static func extractHost(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        return url.host?.replacingOccurrences(of: "www.", with: "")
    }
}
