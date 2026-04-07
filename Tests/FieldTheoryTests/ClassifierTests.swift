import Testing
import Foundation
@testable import FieldTheory

@Suite("Classifier")
struct ClassifierTests {

    private func record(text: String, links: [String]? = nil) -> BookmarkRecord {
        BookmarkRecord(
            id: "1", tweetId: "1",
            url: "https://x.com/user/status/1",
            text: text, syncedAt: "2024-01-01T00:00:00Z",
            links: links
        )
    }

    // MARK: - Category Detection

    @Test func toolCategory() {
        let r = Classifier.classify(record(text: "Check out github.com/apple/swift for the compiler"))
        #expect(r.categories.contains("tool"))
    }

    @Test func toolFromNpmInstall() {
        let r = Classifier.classify(record(text: "Run npm install my-package to get started"))
        #expect(r.categories.contains("tool"))
    }

    @Test func securityCategory() {
        let r = Classifier.classify(record(text: "New CVE-2024-1234 affects all versions"))
        #expect(r.categories.contains("security"))
    }

    @Test func securityFromVulnerability() {
        let r = Classifier.classify(record(text: "Critical vulnerability found in popular library"))
        #expect(r.categories.contains("security"))
    }

    @Test func techniqueCategory() {
        let r = Classifier.classify(record(text: "How I built a real-time chat system from scratch"))
        #expect(r.categories.contains("technique"))
    }

    @Test func techniqueFromTutorial() {
        let r = Classifier.classify(record(text: "Tutorial: Building your first SwiftUI app"))
        #expect(r.categories.contains("technique"))
    }

    @Test func launchCategory() {
        let r = Classifier.classify(record(text: "Just shipped v2.0 of our app!"))
        #expect(r.categories.contains("launch"))
    }

    @Test func launchFromAnnouncing() {
        let r = Classifier.classify(record(text: "Announcing our new API platform"))
        #expect(r.categories.contains("launch"))
    }

    @Test func researchCategory() {
        let r = Classifier.classify(record(text: "New paper on arxiv.org/abs/2024.12345"))
        #expect(r.categories.contains("research"))
    }

    @Test func researchFromStudy() {
        let r = Classifier.classify(record(text: "A recent study finds that LLMs can reason"))
        #expect(r.categories.contains("research"))
    }

    @Test func opinionCategory() {
        let r = Classifier.classify(record(text: "Unpopular opinion: tabs are better than spaces"))
        #expect(r.categories.contains("opinion"))
    }

    @Test func opinionFromHotTake() {
        let r = Classifier.classify(record(text: "Hot take: Rust is overrated for web development"))
        #expect(r.categories.contains("opinion"))
    }

    @Test func commerceCategory() {
        let r = Classifier.classify(record(text: "Get it on amazon.com for $29.99"))
        #expect(r.categories.contains("commerce"))
    }

    @Test func commerceFromAffiliate() {
        let r = Classifier.classify(record(text: "Use my affiliate link geni.us/abcdef"))
        #expect(r.categories.contains("commerce"))
    }

    // MARK: - Domain Shortcuts

    @Test func domainShortcutTool() {
        let r = Classifier.classify(record(
            text: "Cool project",
            links: ["https://github.com/user/repo"]
        ))
        #expect(r.categories.contains("tool"))
    }

    @Test func domainShortcutResearch() {
        let r = Classifier.classify(record(
            text: "Interesting findings",
            links: ["https://arxiv.org/abs/2024.12345"]
        ))
        #expect(r.categories.contains("research"))
    }

    @Test func domainShortcutCommerce() {
        let r = Classifier.classify(record(
            text: "Nice product",
            links: ["https://amazon.com/dp/B123"]
        ))
        #expect(r.categories.contains("commerce"))
    }

    // MARK: - Multi-category

    @Test func multiCategory() {
        let r = Classifier.classify(record(text: "CVE-2024-1234 found in github.com/lib/crypto"))
        #expect(r.categories.contains("security"))
        #expect(r.categories.contains("tool"))
    }

    // MARK: - No Match

    @Test func noMatchReturnsUnclassified() {
        let r = Classifier.classify(record(text: "Just had a great lunch"))
        #expect(r.categories.isEmpty)
        #expect(r.primary == "unclassified")
    }

    // MARK: - GitHub URL Extraction

    @Test func githubUrlExtraction() {
        let r = Classifier.classify(record(text: "Check https://github.com/apple/swift and https://github.com/vapor/vapor"))
        #expect(r.githubUrls.count == 2)
        #expect(r.githubUrls.contains("github.com/apple/swift"))
        #expect(r.githubUrls.contains("github.com/vapor/vapor"))
    }

    // MARK: - Batch Classification

    @Test func classifyCorpus() {
        let records = [
            record(text: "Check out github.com/foo/bar"),
            record(text: "CVE-2024-9999 is critical"),
            record(text: "Just had coffee"),
        ]
        let summary = Classifier.classifyCorpus(records)
        #expect(summary.total == 3)
        #expect(summary.categoryCounts["tool"] == 1)
        #expect(summary.categoryCounts["security"] == 1)
        #expect(summary.unclassifiedCount == 1)
    }
}
