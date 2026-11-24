import Foundation
import Testing

@testable import Feedini

struct SyncRecordTests {
    typealias F = SyncRecord.Field

    private let feed = Feed(
        title: "Tech", url: URL(string: "https://example.com/tech.xml")!,
        siteURL: URL(string: "https://example.com/"), language: "en", etag: "\"e1\"", lastSuccess: .hours(-1),
        folderID: UUID())

    @Test func namesRecordsByTypeAndID() throws {
        let id = UUID()
        for kind in SyncRecord.Kind.allCases {
            let recordID = SyncRecord.ID(kind, id)
            #expect(SyncRecord.ID(name: recordID.name) == recordID)
        }
        #expect(SyncRecord.ID.article(id).name == "article-\(id.uuidString)")
        #expect(SyncRecord.ID.pageText(id).name == "pagetext-\(id.uuidString)")
        #expect(SyncRecord.ID.settings.name == "settings")
        #expect(SyncRecord.ID(.meta, id) == .meta)
        // Types of a newer version and other names are left alone.
        #expect(SyncRecord.ID(name: "highlight-\(id.uuidString)") == nil)
        #expect(SyncRecord.ID(name: "article-nonsense") == nil)
        #expect(SyncRecord.ID(name: "article") == nil)
        let key = Tombstone.Key(feedID: feed.id, key: "a")
        #expect(SyncRecord.ID.tombstone(key) == SyncRecord.ID(.tombstone, StableID.article(feed: feed.id, key: "a")))
    }

    @Test func aFeedKeepsTheDownloadStateOfThisDevice() throws {
        let record = SyncRecord(feed: feed)
        #expect(Set(record.fields.keys) == SyncRecord.feedFields)

        var local = feed
        local.title = "Old title"
        local.lastChecked = .hours(-2)
        let received = try #require(record.feed(keeping: local))
        #expect(received.title == "Tech")
        #expect(received.etag == "\"e1\"")
        #expect(received.lastChecked == .hours(-2))

        let new = try #require(record.feed(keeping: nil))
        #expect(new.id == feed.id && new.siteURL == feed.siteURL && new.language == "en")
        #expect(new.folderID == feed.folderID)
        #expect(new.etag == nil && new.lastSuccess == nil)
        #expect(SyncRecord(.feed(feed.id), fields: [F.title: .string("No address")]).feed(keeping: nil) == nil)
    }

    @Test func anArticleGoesAndComesBackWhole() throws {
        let article = Article(
            feedID: feed.id, key: "a", title: "A", link: URL(string: "https://example.com/a"), published: .hours(-3),
            author: "Author", text: "Text", language: "cs", firstSeen: .hours(-2), readAt: .hours(-1),
            pageSummary: PageSummary(tldr: "Gist", details: ["One"], language: "cs", date: .hours(-1)),
            savedAt: .hours(-1), site: "Example")
        let record = SyncRecord(article: article)

        #expect(record.article() == article)
        #expect(Set(record.fields.keys) == SyncRecord.articleFields)
        // Unread, not saved, without the optional fields.
        let bare = Article(feedID: feed.id, key: "b", title: "B", firstSeen: .hours(-2))
        #expect(SyncRecord(article: bare).article() == bare)
        #expect(SyncRecord(article: bare)[F.readAt] == nil)
        var broken = record
        broken[F.firstSeen] = nil
        #expect(broken.article() == nil)
    }

    @Test func storiesTopicsTombstonesAndTheRest() throws {
        let story = Story(
            title: "Story", topicID: UUID(), articleIDs: [UUID(), UUID()],
            summary: Summary(title: "T", text: "S", language: "en", articleIDs: [UUID()]))
        #expect(SyncRecord(story: story).story() == story)
        let bare = Story(title: "Bare", articleIDs: [])
        #expect(SyncRecord(story: bare).story() == bare)
        let topic = Topic(name: "Gadgets", description: "Devices", language: "en")
        #expect(SyncRecord(topic: topic).topic() == topic)
        let tombstone = Tombstone(feedID: feed.id, key: "gone", lastSeen: .hours(-4))
        #expect(SyncRecord(tombstone: tombstone).tombstone() == tombstone)
        #expect(SyncRecord(removedFeed: feed.id, title: "Old").removedFeedTitle == "Old")
        #expect(SyncRecord(pageText: "Page", of: UUID()).pageText == "Page")
        let settings = SummarySettings(language: "cs", singleArticles: .otherLanguages)
        #expect(SyncRecord(settings: settings).settings() == settings)
        var unknownChoice = SyncRecord(settings: settings)
        unknownChoice[F.singleArticleSummaries] = .string("sometimes")
        #expect(unknownChoice.settings()?.singleArticles == .never)
        #expect(SyncRecord(.settings).settings() == nil)
        #expect(SyncRecord(minimumVersion: 2).minimumVersion == 2)
        #expect(SyncRecord(.story(UUID())).story() == nil)
        #expect(SyncRecord(.topic(UUID())).topic() == nil)
        #expect(SyncRecord(.tombstone(tombstone.id)).tombstone() == nil)
        #expect(SyncRecord(.folder(UUID())).folder() == nil)
    }

    @Test func fieldsOfANewerVersionAreKept() {
        var record = SyncRecord(feed: feed)
        record["color"] = .string("blue")
        var changed = feed
        changed.title = "Renamed"

        let merged = record.taking([F.title, F.siteURL], from: SyncRecord(feed: changed))

        #expect(merged["color"] == .string("blue"))
        #expect(merged.string(F.title) == "Renamed")
        #expect(merged[F.siteURL] == record[F.siteURL])
        #expect(merged.taking([F.siteURL], from: SyncRecord(.feed(feed.id)))[F.siteURL] == nil)
    }

    @Test func readsOnlyValuesOfTheirType() {
        let record = SyncRecord(.meta, fields: ["a": .int(1), "b": .strings(["x"]), "c": .data(Data([1]))])
        #expect(record.string("a") == nil && record.int("b") == nil && record.date("a") == nil)
        #expect(record.strings("b") == ["x"] && record.data("c") == Data([1]) && record.data("a") == nil)
        #expect(record.strings("a") == nil)
        #expect(record.decoded(Summary.self, "c") == nil)
    }

    @Test func contentIsEncryptedButIDsDatesAndOrderAreNot() {
        #expect(SyncRecord.Kind.article.encryptedFields.contains(F.text))
        #expect(!SyncRecord.Kind.article.encryptedFields.contains(F.readAt))
        #expect(!SyncRecord.Kind.article.encryptedFields.contains(F.feedID))
        #expect(SyncRecord.Kind.folder.encryptedFields == [F.name])
        #expect(SyncRecord.Kind.meta.encryptedFields.isEmpty)
        for kind in SyncRecord.Kind.allCases {
            #expect(kind.encryptedFields.isSubset(of: kind.allFields))
        }
    }

    @Test func makesTheRecordOfAPartAsItIsNow() throws {
        let folder = Folder(name: "Daily")
        let article = Article.stub(feed: feed.id)
        let story = Story(title: "S", articleIDs: [article.id])
        let topic = Topic(name: "T", description: "")
        let tombstone = Tombstone(feedID: feed.id, key: "gone", lastSeen: .hours(-1))
        var library = Library(
            feeds: [feed], articles: [article], stories: [story], topics: [topic], folders: [Folder(name: "A"), folder])
        library.tombstones[tombstone.id] = tombstone
        library.removedFeeds = [UUID(): "Old"]
        library.pageTextIDs = [article.id]

        #expect(SyncRecord.make(.feed(feed.id), from: library) == SyncRecord(feed: feed))
        #expect(SyncRecord.make(.folder(folder.id), from: library) == SyncRecord(folder: folder, position: 1))
        #expect(SyncRecord.make(.article(article.id), from: library) == SyncRecord(article: article))
        #expect(SyncRecord.make(.story(story.id), from: library) == SyncRecord(story: story))
        #expect(SyncRecord.make(.topic(topic.id), from: library) == SyncRecord(topic: topic))
        #expect(SyncRecord.make(.tombstone(tombstone.id), from: library) == SyncRecord(tombstone: tombstone))
        let removed = try #require(library.removedFeeds.keys.first)
        #expect(SyncRecord.make(.removedFeed(removed), from: library)?.removedFeedTitle == "Old")
        #expect(SyncRecord.make(.pageText(article.id), from: library, pageText: "P")?.pageText == "P")
        #expect(SyncRecord.make(.pageText(article.id), from: library) == nil)
        #expect(SyncRecord.make(.settings, from: library) == nil)
        library.summarySettings = SummarySettings(language: "cs")
        #expect(SyncRecord.make(.settings, from: library)?.settings()?.language == "cs")
        #expect(SyncRecord.make(.meta, from: library)?.minimumVersion == SyncSchema.version)
        // Gone meanwhile.
        for id in [SyncRecord.ID.feed(UUID()), .folder(UUID()), .article(UUID()), .story(UUID())] {
            #expect(SyncRecord.make(id, from: library) == nil)
        }
        #expect(SyncRecord.make(SyncRecord.ID(.settings, nil), from: Library()) == nil)
    }

    @Test func supportsZonesUpToItsVersion() {
        #expect(SyncSchema.supports(minimumVersion: nil))
        #expect(SyncSchema.supports(minimumVersion: SyncSchema.version))
        #expect(!SyncSchema.supports(minimumVersion: SyncSchema.version + 1))
    }
}
