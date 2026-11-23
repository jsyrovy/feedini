import Foundation
import Testing

@testable import Feedini

struct SyncMergeTests {
    typealias F = SyncRecord.Field

    private let feed = Feed.stub("Tech", lastSuccess: .hours(-1))
    private let article: Article
    private var library: Library

    init() {
        article = Article.stub(feed: feed.id, key: "a")
        library = Library(feeds: [feed], articles: [article])
    }

    // MARK: Applying

    @Test mutating func aFeedOfTheOtherDeviceKeepsTheDownloadStateHere() throws {
        var renamed = feed
        renamed.title = "Renamed"
        renamed.lastSuccess = nil
        let new = Feed.stub("News")

        SyncMerge.apply(SyncRecord(feed: renamed), to: &library)
        SyncMerge.apply(SyncRecord(feed: new), to: &library)

        #expect(library.feeds.map(\.title) == ["Renamed", "News"])
        #expect(library.feeds[0].lastSuccess == .hours(-1))
        #expect(library.feeds[1].lastSuccess == nil)
        SyncMerge.apply(SyncRecord(.feed(UUID())), to: &library)
        #expect(library.feeds.count == 2)
    }

    @Test mutating func fieldsChangedHereAndNotSentYetStay() {
        library.markRead([article.id], at: .hours(1))
        var server = SyncRecord(article: article)
        server[F.savedAt] = .date(.hours(2))
        server[F.title] = .string("Edited title")

        SyncMerge.apply(server, to: &library, pending: [F.readAt])

        let local = library.articles[article.id]
        #expect(local?.readAt == .hours(1))
        #expect(local?.savedAt == .hours(2))
        #expect(local?.title == "Edited title")
    }

    @Test mutating func foldersGoToTheirPlaceAndOneOfTheSameNameBecomesTheirs() throws {
        let local = Folder(name: "news")
        library.folders = [local]
        library.moveFeeds([feed.id], to: local.id)
        let first = Folder(name: "Daily")
        let news = Folder(name: "News")

        SyncMerge.apply(SyncRecord(folder: first, position: 0), to: &library)
        let changes = SyncMerge.apply(SyncRecord(folder: news, position: 1), to: &library)

        #expect(library.folders == [first, news])
        #expect(library.feeds[0].folderID == news.id)
        #expect(changes.saves == [.feed(feed.id): [F.folderID]])
        #expect(changes.deletes == [.folder(local.id)])
        // A renamed folder stays at its place; a position beyond the end goes last.
        SyncMerge.apply(SyncRecord(folder: Folder(id: first.id, name: "Morning"), position: 0), to: &library)
        SyncMerge.apply(SyncRecord(folder: Folder(name: "Later"), position: 9), to: &library)
        #expect(library.folders.map(\.name) == ["Morning", "News", "Later"])
        SyncMerge.apply(SyncRecord(.folder(UUID())), to: &library)
        #expect(library.folders.count == 3)
    }

    @Test mutating func storiesTopicsTombstonesRemovedFeedsAndSettings() throws {
        let story = Story(title: "S", articleIDs: [article.id])
        let topic = Topic(name: "T", description: "")
        let tombstone = Tombstone(feedID: feed.id, key: "gone", lastSeen: .hours(-5))
        library.tombstones[tombstone.id] = Tombstone(feedID: feed.id, key: "gone", lastSeen: .hours(1))
        let other = Tombstone(feedID: feed.id, key: "other", lastSeen: .hours(-5))
        let removed = UUID()

        for record in [
            SyncRecord(story: story), SyncRecord(topic: topic), SyncRecord(tombstone: tombstone),
            SyncRecord(tombstone: other), SyncRecord(removedFeed: removed, title: "Old"),
            SyncRecord(settings: SummarySettings(language: "cs")), SyncRecord(minimumVersion: 1),
            SyncRecord(pageText: "Text", of: article.id),
        ] {
            #expect(SyncMerge.apply(record, to: &library).isEmpty)
        }

        #expect(library.stories[story.id] == story)
        #expect(library.topics[topic.id] == topic)
        // A sighting here stays.
        #expect(library.tombstones[tombstone.id]?.lastSeen == .hours(1))
        #expect(library.tombstones[other.id] == other)
        #expect(library.removedFeeds == [removed: "Old"])
        #expect(library.summarySettings == SummarySettings(language: "cs"))
        // Page texts go into files: not here.
        #expect(library.pageTextIDs.isEmpty)
        // Broken records change nothing.
        SyncMerge.apply(SyncRecord(.story(story.id)), to: &library)
        SyncMerge.apply(SyncRecord(.topic(topic.id)), to: &library)
        SyncMerge.apply(SyncRecord(.removedFeed(removed)), to: &library)
        SyncMerge.apply(SyncRecord(.settings), to: &library)
        SyncMerge.apply(SyncRecord(.article(UUID())), to: &library)
        #expect(library.stories[story.id] == story && library.topics[topic.id] == topic)
        #expect(library.summarySettings != nil && library.removedFeeds.count == 1 && library.articles.count == 1)
    }

    @Test mutating func mergingKeepsWhatWasReadOrSavedOnEitherSide() throws {
        library.markRead([article.id], at: .hours(2))
        var server = article
        server.readAt = .hours(3)
        server.savedAt = .hours(1)
        server.title = "Zone title"
        let summary = PageSummary(tldr: "Old", details: [], language: "en", date: .hours(-2))
        library.articles[article.id]?.pageSummary = PageSummary(
            tldr: "New", details: [], language: "en", date: .hours(-1))
        server.pageSummary = summary

        let changes = SyncMerge.apply(SyncRecord(article: server), to: &library, mode: .merge)

        let merged = try #require(library.articles[article.id])
        #expect(merged.title == "Zone title")
        #expect(merged.readAt == .hours(2))
        #expect(merged.savedAt == .hours(1))
        #expect(merged.pageSummary?.tldr == "New")
        #expect(changes.saves == [.article(article.id): [F.readAt, F.pageSummary]])
        // The same again: nothing to send.
        #expect(SyncMerge.apply(SyncRecord(article: merged), to: &library, mode: .merge).isEmpty)
    }

    // MARK: Deleting

    @Test mutating func anUnreadOrSavedArticleStaysAndIsCreatedAgain() {
        let saved = Article.stub("Saved", feed: feed.id, read: true, savedAt: .hours(1))
        let read = Article.stub("Read", feed: feed.id, read: true)
        library.articles[saved.id] = saved
        library.articles[read.id] = read

        #expect(
            SyncMerge.delete(.article(article.id), from: &library).saves == [
                .article(article.id): SyncRecord.articleFields
            ])
        #expect(!SyncMerge.delete(.article(saved.id), from: &library).isEmpty)
        #expect(SyncMerge.delete(.article(read.id), from: &library).isEmpty)

        #expect(Set(library.articles.keys) == [article.id, saved.id])
    }

    @Test mutating func aStoryOrTopicWithAnUnreadArticleStays() {
        let topic = Topic(name: "T", description: "")
        let story = Story(title: "S", topicID: topic.id, articleIDs: [article.id])
        library.stories[story.id] = story
        library.topics[topic.id] = topic

        #expect(!SyncMerge.delete(.story(story.id), from: &library).isEmpty)
        #expect(!SyncMerge.delete(.topic(topic.id), from: &library).isEmpty)

        library.markRead([article.id], at: .hours(1))
        SyncMerge.delete(.story(story.id), from: &library)
        SyncMerge.delete(.topic(topic.id), from: &library)
        #expect(library.stories.isEmpty && library.topics.isEmpty)
    }

    @Test mutating func everythingElseGoes() {
        let folder = Folder(name: "Daily")
        let tombstone = Tombstone(feedID: feed.id, key: "gone", lastSeen: .hours(-1))
        let removed = UUID()
        let saved = Article.stub("Saved", feed: feed.id, savedAt: .hours(1))
        library.articles[saved.id] = saved
        library.folders = [folder]
        library.tombstones[tombstone.id] = tombstone
        library.removedFeeds = [removed: "Old"]
        library.pageTextIDs = [article.id]
        library.summarySettings = SummarySettings()

        for id in [
            SyncRecord.ID.pageText(article.id), .folder(folder.id), .tombstone(tombstone.id), .removedFeed(removed),
            .meta, .feed(feed.id),
        ] {
            #expect(SyncMerge.delete(id, from: &library).isEmpty)
        }
        // The settings stay.
        #expect(SyncMerge.delete(.settings, from: &library).saves == [.settings: SyncRecord.settingsFields])

        #expect(library.folders.isEmpty && library.tombstones.isEmpty && library.pageTextIDs.isEmpty)
        // A removed feed keeps its saved articles, as when it is removed here.
        #expect(library.feeds.isEmpty)
        #expect(Set(library.articles.keys) == [saved.id])
        #expect(library.removedFeeds == [feed.id: "Tech"])
        #expect(!SyncMerge.recreates(.story(UUID()), in: library))
        #expect(!SyncMerge.recreates(.topic(UUID()), in: library))
        #expect(!SyncMerge.recreates(.article(UUID()), in: library))
    }

    // MARK: Conflicts

    @Test func aConflictKeepsTheZonesContentAndThisDevicesReading() {
        var local = SyncRecord(article: article)
        local[F.readAt] = .date(.hours(1))
        local[F.title] = .string("Downloaded here")
        var server = SyncRecord(article: article)
        server[F.savedAt] = .date(.hours(2))
        server["color"] = .string("blue")

        let resolved = SyncMerge.resolve(server: server, local: local, changed: SyncRecord.articleFields)

        #expect(resolved.date(F.readAt) == .hours(1))
        #expect(resolved.string(F.title) == article.title)
        #expect(resolved["color"] == .string("blue"))
        // Not changed here: the zone's value stays.
        let onlyRead = SyncMerge.resolve(server: server, local: local, changed: [F.readAt])
        #expect(onlyRead.date(F.savedAt) == .hours(2))
    }

    @Test func aConflictOfAFeedOrTombstone() {
        var renamed = feed
        renamed.title = "Renamed here"
        let resolved = SyncMerge.resolve(
            server: SyncRecord(feed: feed), local: SyncRecord(feed: renamed), changed: [F.title])
        #expect(resolved.string(F.title) == "Renamed here")

        let first = Tombstone(feedID: feed.id, key: "gone", lastSeen: .hours(-5))
        let later = Tombstone(feedID: feed.id, key: "gone", lastSeen: .hours(1))
        let tombstone = SyncMerge.resolve(
            server: SyncRecord(tombstone: first), local: SyncRecord(tombstone: later),
            changed: SyncRecord.tombstoneFields)
        #expect(tombstone.tombstone() == first)
    }

    @Test func everythingInTheLibraryForAFirstUpload() {
        var library = library
        library.summarySettings = SummarySettings()

        let changes = SyncMerge.everything(in: library)

        #expect(Set(changes.saves.keys) == [.feed(feed.id), .article(article.id), .settings, .meta])
        #expect(changes.deletes.isEmpty)
    }
}
