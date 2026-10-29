import Foundation
import Testing

@testable import Feedini

struct RefreshCoordinatorTests {
    private let coordinator = RefreshCoordinator(fetcher: FeedFetcher(session: StubURLProtocol.session()))

    private func feed(_ url: URL) -> Feed {
        Feed(title: "Feed", url: url, etag: "\"old\"")
    }

    @Test func downloadsAndParsesEveryFeed() async throws {
        let good = feed(StubURLProtocol.uniqueURL())
        let unchanged = feed(StubURLProtocol.uniqueURL())
        let missing = feed(StubURLProtocol.uniqueURL())
        let page = feed(StubURLProtocol.uniqueURL())
        StubURLProtocol.stub(good.url, try .feed("rss2.xml", headers: ["ETag": "\"new\""]))
        StubURLProtocol.stub(unchanged.url, .response(status: 304))
        StubURLProtocol.stub(missing.url, .response(status: 404))
        StubURLProtocol.stub(page.url, try .feed("not-a-feed.html"))

        let refreshes = await coordinator.refresh([good, unchanged, missing, page])

        let expected = try FeedParser.parse(Fixture.data("rss2.xml"), baseURL: good.url)
        #expect(refreshes[good.id] == .updated(expected, etag: "\"new\"", lastModified: nil))
        #expect(refreshes[unchanged.id] == .notModified)
        #expect(refreshes[missing.id] == .failed("The server answered with HTTP 404 (not found)."))
        #expect(refreshes[page.id] == .failed("This isn't an RSS or Atom feed."))
        #expect(
            StubURLProtocol.requests(to: good.url.host()!).first?.value(forHTTPHeaderField: "If-None-Match")
                == "\"old\"")
    }

    @Test func explainsBrokenFeeds() {
        #expect(FeedParserError.invalid("line 3").message == "The feed couldn't be read: line 3")
        #expect(
            RefreshCoordinator.refresh(from: .fetched(FetchedFeed(data: Data("nonsense".utf8))), url: nil)
                != .notModified)
    }
}
