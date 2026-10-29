import Foundation
import Testing

@testable import Feedini

struct FeedMergeTests {
    private var feed = Feed.stub("Tech", lastSuccess: .hours(-1))

    private func item(_ key: String, hours: Double? = -2, language: String? = "en") -> ParsedItem {
        ParsedItem(
            key: key, title: "Title \(key)", link: URL(string: "https://example.com/\(key)"),
            published: hours.map(Date.hours), author: "Author", text: "Text \(key)", language: language)
    }

    private func updated(_ items: [ParsedItem], language: String? = "en-GB") -> FeedRefresh {
        .updated(
            ParsedFeed(
                title: "Feed title", siteURL: URL(string: "https://example.com/"), language: language, items: items),
            etag: "\"e2\"", lastModified: "Thu, 29 Oct 2026 12:00:00 GMT")
    }

    @Test func addsNewItemsAsUnreadArticles() throws {
        var library = Library(feeds: [feed], articles: [])

        let added = FeedMerge.merge(
            [feed.id: updated([item("a"), item("b", hours: nil)])], into: &library, now: referenceDate)

        #expect(added.count == 2)
        let articles = added.compactMap { library.articles[$0] }
        #expect(articles.map(\.key) == ["a", "b"])
        let first = try #require(articles.first)
        #expect(first.feedID == feed.id)
        #expect(first.title == "Title a")
        #expect(first.link == URL(string: "https://example.com/a"))
        #expect(first.published == .hours(-2))
        #expect(first.author == "Author")
        #expect(first.text == "Text a")
        #expect(first.language == "en")
        #expect(first.firstSeen == referenceDate)
        #expect(!first.isRead)
    }

    @Test func updatesTheFeedAfterAFullDownload() throws {
        var library = Library(feeds: [feed], articles: [])
        library.feeds[0].lastError = "Old error"

        FeedMerge.merge([feed.id: updated([])], into: &library, now: referenceDate)

        let merged = try #require(library.feeds.first)
        #expect(merged.title == "Tech")
        #expect(merged.siteURL == URL(string: "https://example.com/"))
        #expect(merged.language == "en")
        #expect(merged.etag == "\"e2\"")
        #expect(merged.lastModified == "Thu, 29 Oct 2026 12:00:00 GMT")
        #expect(merged.lastSuccess == referenceDate)
        #expect(merged.lastChecked == referenceDate)
        #expect(merged.lastError == nil)
    }

    @Test func skipsKnownArticlesAndRefreshesTombstones() {
        var known = Article.stub("Known", feed: feed.id, key: "known", hours: -3)
        known.text = "Original"
        var library = Library(feeds: [feed], articles: [known])
        let tombstone = Tombstone(feedID: feed.id, key: "read", lastSeen: .hours(-10))
        library.tombstones[tombstone.id] = tombstone

        let added = FeedMerge.merge(
            [feed.id: updated([item("known"), item("read"), item("new")])], into: &library, now: referenceDate)

        #expect(added.map { library.articles[$0]?.key } == ["new"])
        #expect(library.articles[known.id] == known)
        #expect(library.tombstones[tombstone.id]?.lastSeen == referenceDate)
        #expect(library.articles.count == 2)
    }

    @Test func keysAreScopedToTheirFeed() {
        let other = Feed.stub("Other", lastSuccess: .hours(-1))
        var library = Library(feeds: [feed, other], articles: [.stub(feed: other.id, key: "same")])
        library.tombstones[Tombstone.Key(feedID: other.id, key: "gone")] = Tombstone(
            feedID: other.id, key: "gone", lastSeen: .hours(-1))

        let added = FeedMerge.merge(
            [feed.id: updated([item("same"), item("gone")])], into: &library, now: referenceDate)

        #expect(added.count == 2)
    }

    @Test func theFirstDownloadSkipsOldItems() {
        var fresh = Feed.stub("Fresh")
        fresh.lastSuccess = nil
        var library = Library(feeds: [fresh], articles: [])
        let old = -FeedMerge.firstDownloadMaxAge / 3600 - 1

        let added = FeedMerge.merge(
            [fresh.id: updated([item("recent", hours: -24), item("old", hours: old), item("undated", hours: nil)])],
            into: &library, now: referenceDate)

        #expect(Set(added.compactMap { library.articles[$0]?.key }) == ["recent", "undated"])
        #expect(Array(library.tombstones.values) == [Tombstone(feedID: fresh.id, key: "old", lastSeen: referenceDate)])

        // Later downloads add old items they haven't seen.
        let later = FeedMerge.merge(
            [fresh.id: updated([item("older", hours: old - 1)])], into: &library, now: .hours(1))
        #expect(later.count == 1)
    }

    @Test func notModifiedOnlyMarksTheFeedChecked() throws {
        var library = Library(feeds: [feed], articles: [])
        library.feeds[0].lastError = "Old error"

        FeedMerge.merge([feed.id: .notModified], into: &library, now: referenceDate)

        let merged = try #require(library.feeds.first)
        #expect(merged.lastChecked == referenceDate)
        #expect(merged.lastSuccess == .hours(-1))
        #expect(merged.lastError == nil)
    }

    @Test func aFailureKeepsEverythingButRecordsTheError() throws {
        let article = Article.stub(feed: feed.id)
        var library = Library(feeds: [feed], articles: [article])

        let added = FeedMerge.merge(
            [feed.id: .failed("The server didn't respond in time.")], into: &library, now: referenceDate)

        #expect(added.isEmpty)
        #expect(library.feeds.first?.lastError == "The server didn't respond in time.")
        #expect(library.feeds.first?.lastSuccess == .hours(-1))
        #expect(library.articles[article.id] == article)
    }

    @Test func ignoresResultsOfRemovedFeeds() {
        var library = Library(feeds: [feed], articles: [])
        let added = FeedMerge.merge([UUID(): updated([item("x")])], into: &library, now: referenceDate)
        #expect(added.isEmpty)
        #expect(library.articles.isEmpty)
    }
}
