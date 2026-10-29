import Foundation
import Testing

@testable import Feedini

struct RetentionTests {
    private let feed = Feed.stub("Tech", lastSuccess: referenceDate)
    /// Just older than the attach window.
    private let old = -73.0

    private func pruned(_ library: Library) -> Library {
        var library = library
        Retention.prune(&library, now: referenceDate)
        return library
    }

    @Test func keepsUnreadArticlesForever() {
        let ancient = Article.stub(feed: feed.id, hours: -24 * 365)
        let library = pruned(Library(feeds: [feed], articles: [ancient]))
        #expect(library.articles[ancient.id] != nil)
        #expect(library.tombstones.isEmpty)
    }

    @Test func removesOldReadArticlesAndLeavesTombstones() {
        let stale = Article.stub(feed: feed.id, key: "stale", hours: old, read: true)
        let recent = Article.stub(feed: feed.id, hours: -71, read: true)
        let library = pruned(Library(feeds: [feed], articles: [stale, recent]))

        #expect(Set(library.articles.keys) == [recent.id])
        #expect(Array(library.tombstones.values) == [Tombstone(feedID: feed.id, key: "stale", lastSeen: referenceDate)])
    }

    @Test func keepsAReadStoryWhileItsNewestArticleIsInTheAttachWindow() {
        let older = Article.stub(feed: feed.id, hours: old, read: true)
        let newer = Article.stub(feed: feed.id, hours: -10, read: true)
        let story = Story(title: "Story", articleIDs: [older.id, newer.id])
        let library = pruned(Library(feeds: [feed], articles: [older, newer], stories: [story]))

        #expect(library.stories[story.id] != nil)
        #expect(library.articles.count == 2)
    }

    @Test func keepsOldReadArticlesOfAStoryWithUnreadOnes() {
        let read = Article.stub(feed: feed.id, hours: old - 100, read: true)
        let unread = Article.stub(feed: feed.id, hours: old)
        let story = Story(title: "Story", articleIDs: [read.id, unread.id])
        let library = pruned(Library(feeds: [feed], articles: [read, unread], stories: [story]))

        #expect(library.stories[story.id]?.articleIDs == [read.id, unread.id])
    }

    @Test func removesAStaleReadStoryWithAllItsArticlesAndItsTopic() {
        let topic = Topic(name: "Games", description: "Games.")
        let kept = Topic(name: "Apple", description: "Apple.")
        let first = Article.stub(feed: feed.id, hours: old, read: true)
        let second = Article.stub(feed: feed.id, hours: old - 1, read: true)
        let stale = Story(title: "Stale", topicID: topic.id, articleIDs: [first.id, second.id])
        let unread = Article.stub(feed: feed.id)
        let live = Story(title: "Live", topicID: kept.id, articleIDs: [unread.id])
        let library = pruned(
            Library(
                feeds: [feed], articles: [first, second, unread], stories: [stale, live], topics: [topic, kept]))

        #expect(Set(library.stories.keys) == [live.id])
        #expect(Set(library.articles.keys) == [unread.id])
        #expect(library.tombstones.count == 2)
        #expect(Set(library.topics.keys) == [kept.id])
    }

    @Test func removesStoriesWhoseArticlesAreAllMissing() {
        let story = Story(title: "Broken", articleIDs: [UUID()])
        let library = pruned(Library(feeds: [feed], articles: [], stories: [story]))
        #expect(library.stories.isEmpty)
    }

    @Test func dropsTombstonesMissingFromTheFeedLongerThanTheMargin() {
        let failing = Feed.stub("Failing", lastSuccess: .hours(-24 * 30))
        let never = Feed.stub("Never")
        var library = Library(feeds: [feed, failing, never], articles: [])
        let tombstones = [
            Tombstone(feedID: feed.id, key: "expired", lastSeen: .hours(-72.5)),
            Tombstone(feedID: feed.id, key: "kept", lastSeen: .hours(-71.5)),
            // The feed hasn't been downloaded for a month: its tombstones stay.
            Tombstone(feedID: failing.id, key: "failing", lastSeen: .hours(-24 * 31)),
            Tombstone(feedID: never.id, key: "never", lastSeen: .hours(-24 * 100)),
        ]
        library.tombstones = Dictionary(uniqueKeysWithValues: tombstones.map { ($0.id, $0) })

        let keys = Set(pruned(library).tombstones.values.map(\.key))

        #expect(keys == ["kept", "failing", "never"])
    }

    @Test func aRemovedArticleKeepsALaterTombstoneDate() {
        let stale = Article.stub(feed: feed.id, key: "again", hours: old, read: true)
        var library = Library(feeds: [feed], articles: [stale])
        let later = Tombstone(feedID: feed.id, key: "again", lastSeen: .hours(1))
        library.tombstones[later.id] = later

        #expect(pruned(library).tombstones[later.id]?.lastSeen == .hours(1))
    }
}
