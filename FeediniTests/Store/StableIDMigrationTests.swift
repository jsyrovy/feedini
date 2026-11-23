import Foundation
import Testing

@testable import Feedini

struct StableIDMigrationTests {
    private let tech = Feed.stub("Tech")
    private let folder = Folder(name: "Daily")

    @Test func rewritesFeedAndArticleIDsAndEveryReferenceToThem() throws {
        var feed = tech
        feed.folderID = folder.id
        let first = Article.stub("First", feed: feed.id, key: "1", savedAt: .hours(1))
        let second = Article.stub("Second", feed: feed.id, key: "2", read: true)
        // A random ID, as before schema 3.
        let link = Article(
            id: UUID(), feedID: SavedLink.feedID, key: "example.com/essay", title: "Essay", firstSeen: referenceDate,
            savedAt: referenceDate)
        let removedFeed = UUID()
        let kept = Article.stub("Kept", feed: removedFeed, key: "k", savedAt: .hours(2))
        let story = Story(
            title: "Story", articleIDs: [first.id, second.id],
            summary: Summary(title: "S", text: "T", language: "en", articleIDs: [first.id, second.id]))
        var library = Library(
            feeds: [feed], articles: [first, second, link, kept], stories: [story], folders: [folder])
        library.tombstones[Tombstone.Key(feedID: feed.id, key: "gone")] = Tombstone(
            feedID: feed.id, key: "gone", lastSeen: .hours(-1))
        library.removedFeeds = [removedFeed: "Old Feed"]
        library.pageTextIDs = [first.id, link.id]

        let renames = StableIDMigration.migrate(&library)

        let feedID = StableID.feed(url: feed.url)
        let firstID = StableID.article(feed: feedID, key: "1")
        let secondID = StableID.article(feed: feedID, key: "2")
        let linkID = StableID.article(feed: SavedLink.feedID, key: "example.com/essay")
        let keptID = StableID.article(feed: removedFeed, key: "k")
        #expect(library.feeds.map(\.id) == [feedID])
        #expect(library.feeds.first?.folderID == folder.id)
        #expect(Set(library.articles.keys) == [firstID, secondID, linkID, keptID])
        #expect(library.articles[firstID]?.feedID == feedID)
        #expect(library.articles[firstID]?.savedAt == .hours(1))
        #expect(library.articles[secondID]?.isRead == true)
        #expect(library.articles[keptID]?.feedID == removedFeed)
        #expect(library.stories[story.id]?.articleIDs == [firstID, secondID])
        #expect(library.stories[story.id]?.summary?.articleIDs == [firstID, secondID])
        #expect(Array(library.tombstones.keys) == [Tombstone.Key(feedID: feedID, key: "gone")])
        #expect(library.removedFeeds == [removedFeed: "Old Feed"])
        #expect(library.pageTextIDs == [firstID, linkID])
        #expect(renames[first.id] == firstID)
        #expect(renames.count == 4)

        // Migrating again changes nothing.
        let migrated = library
        #expect(StableIDMigration.migrate(&library).isEmpty)
        #expect(library == migrated)
    }

    @Test func feedsWithTheSameAddressBecomeOne() throws {
        let twin = Feed(id: UUID(), title: "Tech again", url: URL(string: "HTTPS://EXAMPLE.com/tech.xml/")!)
        let unread = Article.stub("Unread", feed: tech.id, key: "same", savedAt: .hours(4))
        let read = Article.stub("Read", feed: twin.id, key: "same", hours: 1, read: true, savedAt: .hours(3))
        let other = Article.stub("Other", feed: twin.id, key: "other")
        var library = Library(feeds: [tech, twin], articles: [unread, read, other])
        library.tombstones[Tombstone.Key(feedID: tech.id, key: "gone")] = Tombstone(
            feedID: tech.id, key: "gone", lastSeen: .hours(-1))
        library.tombstones[Tombstone.Key(feedID: twin.id, key: "gone")] = Tombstone(
            feedID: twin.id, key: "gone", lastSeen: .hours(-5))

        StableIDMigration.migrate(&library)

        let feedID = StableID.feed(url: tech.url)
        #expect(library.feeds.map(\.title) == ["Tech"])
        let same = try #require(library.articles[StableID.article(feed: feedID, key: "same")])
        // The first seen stays, read and saved when either was.
        #expect(same.title == "Unread")
        #expect(same.readAt == .hours(1))
        #expect(same.savedAt == .hours(3))
        #expect(library.articles[StableID.article(feed: feedID, key: "other")]?.feedID == feedID)
        #expect(library.articles.count == 2)
        #expect(library.tombstones.values.map(\.lastSeen) == [.hours(-1)])
    }
}
