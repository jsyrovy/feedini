import Foundation
import Testing

@testable import Feedini

struct SyncChangesTests {
    typealias F = SyncRecord.Field

    private let feed = Feed.stub("Tech")
    private let article: Article
    private let library: Library

    init() {
        article = Article.stub(feed: feed.id)
        library = Library(feeds: [feed], articles: [article], folders: [Folder(name: "A"), Folder(name: "B")])
    }

    @Test func aRefreshThatChangesNothingSyncedSendsNothing() {
        var new = library
        new.feeds[0].lastChecked = .hours(1)
        new.feeds[0].etag = "\"e2\""
        new.usage = [AIUsageDay(day: "2026-10-29", calls: 1)]

        #expect(SyncChanges.diff(old: library, new: new).isEmpty)
        #expect(SyncChanges.diff(old: library, new: library).isEmpty)
    }

    @Test func readingSendsOnlyTheReadDate() {
        var new = library
        new.markRead([article.id], at: .hours(1))

        #expect(SyncChanges.diff(old: library, new: new) == SyncChanges(saves: [.article(article.id): [F.readAt]]))
    }

    @Test func onlyTheNamedArticlesAreComparedWhenTheyAreKnown() {
        let other = Article.stub("Other", feed: feed.id)
        var old = library
        old.articles[other.id] = other
        var new = old
        new.markRead([article.id, other.id], at: .hours(1))

        let changes = SyncChanges.diff(old: old, new: new, articles: [article.id])

        #expect(changes.saves == [.article(article.id): [F.readAt]])
    }

    @Test func newArticlesSendEveryFieldAndRemovedOnesAreDeleted() {
        let added = Article.stub("New", feed: feed.id)
        var new = library
        new.articles[added.id] = added
        new.articles[article.id] = nil

        let changes = SyncChanges.diff(old: library, new: new)

        #expect(changes.saves == [.article(added.id): SyncRecord.articleFields])
        #expect(changes.deletes == [.article(article.id)])
    }

    @Test func feedsFoldersStoriesAndTopics() throws {
        let story = Story(title: "S", articleIDs: [article.id])
        let topic = Topic(name: "T", description: "")
        var new = library
        new.feeds[0].title = "Renamed"
        new.moveFolder(new.folders[1].id, by: -1)
        new.stories[story.id] = story
        new.topics[topic.id] = topic

        let changes = SyncChanges.diff(old: library, new: new)

        #expect(changes.saves[.feed(feed.id)] == [F.title])
        // Both folders changed their position.
        #expect(changes.saves[.folder(library.folders[0].id)] == [F.position])
        #expect(changes.saves[.folder(library.folders[1].id)] == [F.position])
        #expect(changes.saves[.story(story.id)] == SyncRecord.storyFields)
        #expect(changes.saves[.topic(topic.id)] == SyncRecord.topicFields)

        var removed = new
        removed.removeFeed(feed.id)
        removed.removeFolder(new.folders[0].id)
        let removal = SyncChanges.diff(old: new, new: removed)
        #expect(
            removal.deletes == [
                .feed(feed.id), .folder(new.folders[0].id), .article(article.id), .story(story.id),
            ])
    }

    @Test func tombstonesAreSentOnceAndTheirSightingsAreNot() {
        let key = Tombstone.Key(feedID: feed.id, key: "gone")
        var withTombstone = library
        withTombstone.tombstones[key] = Tombstone(feedID: feed.id, key: "gone", lastSeen: .hours(-1))
        #expect(
            SyncChanges.diff(old: library, new: withTombstone).saves == [.tombstone(key): SyncRecord.tombstoneFields])

        var seen = withTombstone
        seen.tombstones[key]?.lastSeen = .hours(1)
        #expect(SyncChanges.diff(old: withTombstone, new: seen).isEmpty)
        #expect(SyncChanges.diff(old: withTombstone, new: library).deletes == [.tombstone(key)])
    }

    @Test func removedFeedsPageTextsAndSettings() {
        let removed = UUID()
        var new = library
        new.removedFeeds = [removed: "Old"]
        new.pageTextIDs = [article.id]
        new.summarySettings = SummarySettings(language: "cs")

        let changes = SyncChanges.diff(old: library, new: new)

        #expect(
            changes.saves == [
                .removedFeed(removed): [F.title], .pageText(article.id): [F.text],
                .settings: SyncRecord.settingsFields,
            ])
        var other = new
        other.summarySettings = SummarySettings(language: "cs", singleArticles: .always)
        #expect(SyncChanges.diff(old: new, new: other).saves == [.settings: [F.singleArticleSummaries]])
        // The settings are never deleted.
        #expect(SyncChanges.diff(old: new, new: library).deletes == [.removedFeed(removed), .pageText(article.id)])
    }

    @Test func laterChangesAddUp() {
        var changes = SyncChanges(saves: [.article(article.id): [F.readAt]], deletes: [.feed(feed.id)])

        changes.add(SyncChanges(saves: [.article(article.id): [F.savedAt], .feed(feed.id): [F.title]]))
        #expect(changes.saves == [.article(article.id): [F.readAt, F.savedAt], .feed(feed.id): [F.title]])
        #expect(changes.deletes.isEmpty)

        changes.add(SyncChanges(deletes: [.article(article.id)]))
        #expect(changes.saves == [.feed(feed.id): [F.title]])
        #expect(changes.deletes == [.article(article.id)])
    }
}
