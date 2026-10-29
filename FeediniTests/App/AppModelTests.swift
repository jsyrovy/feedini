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
            preferences: Preferences(defaults: UserDefaults(suiteName: "feedini-tests-\(UUID().uuidString)")!),
            store: LibraryStore(fileURL: directory.appending(path: "library.json")),
            coordinator: RefreshCoordinator(fetcher: FeedFetcher(session: session)),
            subscriber: FeedSubscriber(fetcher: FeedFetcher(session: session)))
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

    @Test func readStateChangesAreSaved() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let feed = Feed.stub()
        let article = Article.stub(feed: feed.id)
        model.update { $0 = Library(feeds: [feed], articles: [article]) }

        model.markRead([article.id])
        #expect(model.library.articles[article.id]?.isRead == true)
        model.markUnread([article.id])
        model.markRead([])
        #expect(model.library.articles[article.id]?.isRead == false)
    }
}
