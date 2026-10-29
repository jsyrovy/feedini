import Foundation
import Testing

@testable import Feedini

struct LibraryTests {
    private let feed = Feed.stub("Tech")
    private let other = Feed.stub("News")

    @Test func markReadSetsTheDateOnlyOnUnreadArticles() {
        let unread = Article.stub(feed: feed.id)
        let read = Article.stub(feed: feed.id, hours: -5, read: true)
        var library = Library(feeds: [feed], articles: [unread, read])

        library.markRead([unread.id, read.id, UUID()], at: .hours(1))

        #expect(library.articles[unread.id]?.readAt == .hours(1))
        #expect(library.articles[read.id]?.readAt == .hours(-5))
    }

    @Test func markUnreadClearsTheDate() {
        let read = Article.stub(feed: feed.id, read: true)
        var library = Library(feeds: [feed], articles: [read])

        library.markUnread([read.id])

        #expect(library.articles[read.id]?.isRead == false)
    }

    @Test func readingTheWholeStoryClearsItsNewMarks() {
        let first = Article.stub(feed: feed.id, read: true)
        let second = Article.stub(feed: feed.id)
        let third = Article.stub(feed: feed.id)
        let story = Story(
            title: "Story", articleIDs: [first.id, second.id, third.id], newArticleIDs: [second.id, third.id])
        var library = Library(feeds: [feed], articles: [first, second, third], stories: [story])

        library.markRead([second.id], at: .hours(1))
        #expect(library.stories[story.id]?.newArticleIDs == [second.id, third.id])

        library.markRead([third.id], at: .hours(1))
        #expect(library.stories[story.id]?.newArticleIDs == [])
    }

    @Test func removingAFeedRemovesItsArticlesTombstonesAndEmptiedStories() {
        let mine = Article.stub(feed: feed.id)
        let theirs = Article.stub(feed: other.id)
        let onlyMine = Article.stub(feed: feed.id)
        let shared = Story(title: "Shared", articleIDs: [mine.id, theirs.id], newArticleIDs: [mine.id])
        let alone = Story(title: "Alone", articleIDs: [onlyMine.id])
        var library = Library(feeds: [feed, other], articles: [mine, theirs, onlyMine], stories: [shared, alone])
        let kept = Tombstone(feedID: other.id, key: "k", lastSeen: referenceDate)
        library.tombstones = [
            Tombstone.Key(feedID: feed.id, key: "k"): Tombstone(feedID: feed.id, key: "k", lastSeen: referenceDate),
            kept.id: kept,
        ]

        library.removeFeed(feed.id)

        #expect(library.feeds == [other])
        #expect(Set(library.articles.keys) == [theirs.id])
        #expect(library.stories[shared.id]?.articleIDs == [theirs.id])
        #expect(library.stories[shared.id]?.newArticleIDs == [])
        #expect(library.stories[alone.id] == nil)
        #expect(Array(library.tombstones.values) == [kept])
    }

    @Test func storyIndexMapsArticlesToTheirStories() {
        let first = Article.stub(feed: feed.id)
        let second = Article.stub(feed: feed.id)
        let loose = Article.stub(feed: feed.id)
        let story = Story(title: "Story", articleIDs: [first.id, second.id])
        let library = Library(feeds: [feed], articles: [first, second, loose], stories: [story])

        #expect(library.storyIDsByArticle() == [first.id: story.id, second.id: story.id])
        #expect(library.feed(feed.id) == feed)
        #expect(library.feed(UUID()) == nil)
    }

    @Test func articleDateIsThePublishedDateButNotLaterThanTheFirstSighting() {
        var article = Article.stub(feed: feed.id, hours: 0)
        article.published = .hours(-3)
        #expect(article.date == .hours(-3))
        article.published = .hours(5)
        #expect(article.date == .hours(0))
        article.published = nil
        #expect(article.date == .hours(0))
    }

    @Test func codableRoundTripKeepsEverything() throws {
        let article = Article.stub(feed: feed.id, read: true)
        let topic = Topic(name: "Apple", description: "News about Apple.")
        let story = Story(title: "Story", topicID: topic.id, articleIDs: [article.id], newArticleIDs: [article.id])
        var library = Library(feeds: [feed], articles: [article], stories: [story], topics: [topic])
        let tombstone = Tombstone(feedID: feed.id, key: "gone", lastSeen: referenceDate)
        library.tombstones[tombstone.id] = tombstone

        let decoded = try LibraryStore.decoder.decode(Library.self, from: LibraryStore.encoder.encode(library))

        #expect(decoded == library)
    }
}
