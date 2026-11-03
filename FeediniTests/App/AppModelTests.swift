import Foundation
import Testing

@testable import Feedini

@MainActor
struct AppModelTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "feedini-model-\(UUID().uuidString)")
    private let model: AppModel

    init() {
        let session = StubURLProtocol.session()
        model = AppModel(
            preferences: Preferences.test(),
            store: LibraryStore(fileURL: directory.appending(path: "library.json")),
            coordinator: RefreshCoordinator(fetcher: FeedFetcher(session: session)),
            subscriber: FeedSubscriber(fetcher: FeedFetcher(session: session)), backupStore: .temporary())
    }

    @Test func subscribingAddsTheFeedWithItsArticles() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = StubURLProtocol.uniqueURL()
        StubURLProtocol.stub(url, try .feed("rss2.xml"))

        #expect(await model.subscribe(to: url.absoluteString) == nil)

        let feed = try #require(model.library.feeds.first)
        #expect(feed.title == "Example Tech Daily")
        #expect(feed.url == url)
        #expect(feed.language == "cs")
        #expect(feed.lastSuccess != nil)
        #expect(model.library.articles.count == 3)
        #expect(model.entries.count == 3)
        #expect(await model.subscribe(to: url.absoluteString) == .alreadySubscribed)

        await model.flush()
        // Dates are saved in whole seconds, so compare what was saved, not the exact dates.
        let saved = await LibraryStore(fileURL: directory.appending(path: "library.json")).load().library
        #expect(saved.feeds.map(\.url) == [url])
        #expect(Set(saved.articles.values.map(\.key)) == Set(model.library.articles.values.map(\.key)))
    }

    @Test func refreshingMergesNewArticles() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = StubURLProtocol.uniqueURL()
        StubURLProtocol.stub(url, try .feed("atom.xml"))
        _ = await model.subscribe(to: url.absoluteString)
        let known = model.library.articles.count
        StubURLProtocol.stub(url, try .feed("rss2.xml"))

        await model.refresh(model.library.feeds)

        #expect(model.library.articles.count == known + 3)
    }

    @Test func importsAndExportsOPMLAndRemovesFeeds() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = StubURLProtocol.uniqueURL()
        StubURLProtocol.stub(url, try .feed("atom.xml"))
        let opml = OPML.export([Feed(title: "Blog", url: url)])

        let result = try await model.importOPML(opml)

        #expect(result.added.map(\.url) == [url])
        #expect(model.library.feeds.map(\.title) == ["Example Engineering Blog"])
        #expect(try OPML.parse(model.exportOPML()).map(\.feedURL) == [url.absoluteString])
        await #expect(throws: OPML.ParseError.notOPML) { try await model.importOPML(Fixture.data("rss2.xml")) }

        model.removeFeeds([model.library.feeds[0].id])
        #expect(model.library.feeds.isEmpty)
        #expect(model.library.articles.isEmpty)
    }

    @Test func subscribingIntoAFolderAndImportingCategoriesAsFolders() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let (first, second, third) = (
            StubURLProtocol.uniqueURL(), StubURLProtocol.uniqueURL(), StubURLProtocol.uniqueURL()
        )
        StubURLProtocol.stub(first, try .feed("rss2.xml"))
        StubURLProtocol.stub(second, try .feed("atom.xml"))
        StubURLProtocol.stub(third, try .feed("rdf.xml"))
        let daily = try model.addFolder(named: "Daily")

        #expect(await model.subscribe(to: first.absoluteString, folder: daily) == nil)
        let work = Folder(name: "Work")
        let opml = OPML.export(
            [
                Feed(title: "Second", url: second, folderID: work.id),
                Feed(title: "Third", url: third, folderID: UUID()),
            ], folders: [Folder(id: UUID(), name: "daily"), work])
        _ = try await model.importOPML(opml)

        // The OPML category "Work" is a new folder; "Third" is in none.
        #expect(model.library.folders.map(\.name) == ["Daily", "Work"])
        let folders = model.library.feeds.map { $0.folderID.flatMap { model.library.folder($0)?.name } }
        #expect(folders == ["Daily", "Work", nil])
        let exported = try OPML.parse(model.exportOPML())
        #expect(exported.map(\.folder) == ["Daily", "Work", nil])
    }

    @Test func savedEntriesFollowSavingAndReading() {
        let tech = Feed.stub("Tech")
        let article = Article.stub(feed: tech.id)
        model.update { $0 = Library(feeds: [tech], articles: [article]) }
        #expect(model.savedEntries().isEmpty)

        model.setSaved(.article(article.id), at: .hours(1))
        #expect(model.savedEntries().map(\.id) == [.savedArticle(article.id)])
        #expect(model.unreadCounts.saved == 1)

        model.markRead([article.id])
        #expect(model.entry(.savedArticle(article.id))?.isRead == true)
        #expect(model.unreadCounts.saved == 1)
        #expect(model.unreadCounts.all == 0)

        model.setSaved(.article(article.id), at: nil)
        #expect(model.savedEntries().isEmpty)
        #expect(model.unreadCounts.saved == 0)
        // Built on demand for an entry removed from Saved while it is shown.
        #expect(model.entry(.savedArticle(article.id))?.articles.map(\.id) == [article.id])
        #expect(model.entry(.savedArticle(UUID())) == nil)
    }

    @Test func managesFoldersAndTheirCounts() throws {
        let tech = Feed.stub("Tech")
        let news = Feed.stub("News")
        let techArticle = Article.stub(feed: tech.id)
        let newsArticle = Article.stub(feed: news.id)
        model.update { $0 = Library(feeds: [tech, news], articles: [techArticle, newsArticle]) }
        #expect(model.unreadCounts.all == 2)

        let daily = try model.addFolder(named: "Daily", moving: [tech.id])
        #expect(model.unreadCounts.count(for: .folder(daily)) == 1)
        #expect(model.folderIDsByFeed == [tech.id: daily])
        #expect(throws: FolderNameError.taken) { try model.addFolder(named: "daily") }

        model.moveFeeds([news.id], to: daily)
        #expect(model.unreadCounts.count(for: .folder(daily)) == 2)
        model.markRead([newsArticle.id])
        #expect(model.unreadCounts.count(for: .folder(daily)) == 1)

        let work = try model.addFolder(named: "Work")
        try model.renameFolder(work, to: "Office")
        #expect(throws: FolderNameError.empty) { try model.renameFolder(work, to: "") }
        model.moveFolder(work, by: -1)
        #expect(model.library.folders.map(\.name) == ["Office", "Daily"])
        #expect(model.drop(.feed(tech.id), onto: .folder(work)))
        #expect(!model.drop(.feed(tech.id), onto: .folder(work)))
        #expect(model.unreadCounts.count(for: .folder(work)) == 1)
        #expect(model.unreadCounts.count(for: .folder(daily)) == 0)

        model.removeFolder(work)
        #expect(model.library.folders.map(\.name) == ["Daily"])
        #expect(model.library.feed(tech.id)?.folderID == nil)
        #expect(model.unreadCounts.count(for: .folder(work)) == 0)
    }

    @Test func readStateChangesAreSaved() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let feed = Feed.stub()
        let article = Article.stub(feed: feed.id)
        model.update { $0 = Library(feeds: [feed], articles: [article]) }

        _ = model.entries
        model.markRead([article.id])
        #expect(model.library.articles[article.id]?.isRead == true)
        // The cached entries follow the read state.
        #expect(model.entries.first?.isRead == true)
        model.markUnread([article.id])
        model.markRead([])
        #expect(model.library.articles[article.id]?.isRead == false)
    }

    @Test func storesPageTextsAndForgetsOnesWhoseFileIsGone() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let feed = Feed.stub("Tech")
        let article = Article.stub(feed: feed.id)
        model.update { $0 = Library(feeds: [feed], articles: [article]) }
        let entries = model.entries

        try await model.storePageText("The text of the page.", for: article.id)
        try await model.storePageText("Gone meanwhile.", for: UUID())

        #expect(model.library.pageTextIDs == [article.id])
        #expect(model.entries == entries)
        #expect(await model.pageText(article.id) == "The text of the page.")
        #expect(await model.pageText(UUID()) == nil)

        let store = LibraryStore(fileURL: directory.appending(path: "library.json"))
        try FileManager.default.removeItem(at: store.pageTextURL(article.id))
        #expect(await model.pageText(article.id) == nil)
        #expect(model.library.pageTextIDs.isEmpty)
    }

    @Test func savingALinkAddsItToSavedAndLoadsItsPage() async throws {
        let extractor = FakePageExtractor()
        extractor.metadata = { _ in PageMetadata(title: "An Essay", site: "Example Magazine") }
        let model = AppModel.test(extractor: extractor)
        model.preferences.aiEnabled = false
        let feed = Feed.stub("Tech")
        let article = Article.stub(feed: feed.id)
        model.update { $0 = Library(feeds: [feed], articles: [article]) }

        #expect(throws: SavedLink.Failure.invalidAddress) { try model.saveLink("no address") }
        let outcome = try model.saveLink("example.com/essay")
        guard case .added(let id) = outcome else {
            Issue.record("Not added: \(outcome)")
            return
        }
        await model.pageQueue?.waitUntilIdle()

        #expect(extractor.requests == [URL(string: "https://example.com/essay")!])
        #expect(model.library.pageTextIDs == [id])
        #expect(model.savedEntries().map(\.id) == [.savedArticle(id)])
        #expect(model.savedEntries().first?.title == "An Essay")
        #expect(model.unreadCounts.saved == 1)
        #expect(model.unreadCounts.all == 1)
        #expect(try model.saveLink("https://example.com/essay#top") == .alreadySaved(id))

        // The address of a feed's article saves that article, as Shift+S would.
        #expect(try model.saveLink(article.link!.absoluteString) == .saved(article.id))
        await model.pageQueue?.waitUntilIdle()
        #expect(model.library.articles.count == 2)
        #expect(model.library.pageTextIDs == [id, article.id])
        #expect(model.aiStatus.pages[article.id]?.phase == .failed(AIStatus.State.offMessage))
    }

    @Test func droppedLinksAreSavedUnlessTheyAreNoWebAddresses() async {
        let model = AppModel.test()
        model.preferences.aiEnabled = false

        #expect(!model.saveLinks([URL(filePath: "/tmp/page.html"), URL(string: "mailto:someone@example.com")!]))
        #expect(model.saveLinks([URL(string: "https://example.com/a")!, URL(string: "http://example.com/b")!]))
        await model.pageQueue?.waitUntilIdle()

        #expect(Set(model.library.articles.values.map(\.key)) == ["example.com/a", "example.com/b"])
    }

    @Test func reloadingASavedLinkLoadsItsPageAgain() async throws {
        let extractor = FakePageExtractor()
        let model = AppModel.test(extractor: extractor)
        model.preferences.aiEnabled = false
        guard case .added(let id) = try model.saveLink("example.com/essay") else {
            Issue.record("Not added")
            return
        }
        await model.pageQueue?.waitUntilIdle()

        model.pageOpened(id)
        model.reloadPage(id)
        await model.pageQueue?.waitUntilIdle()

        #expect(extractor.requests.count == 2)
        #expect(model.library.pageTextIDs == [id])
    }
}
